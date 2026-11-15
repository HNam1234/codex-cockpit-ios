"""Validate and transactionally install ChatGPT OAuth credentials for Codex.

This module deliberately never formats token values into errors or logs.  The
caller supplies the live Codex snapshot reader; a failed read restores the
previous auth file before the exception escapes.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import secrets
from typing import Any, Callable
import uuid


AUTH_ISSUER = "https://auth.openai.com"
AUTH_CLAIM = "https://api.openai.com/auth"
CLIENT_ID_PATTERN = re.compile(r"^[A-Za-z0-9._~-]{8,256}$")


class OAuthImportError(ValueError):
    """A token-safe validation error suitable for the native API response."""


@dataclass(frozen=True)
class ImportedIdentity:
    account_id: str
    subject: str
    email: str


def _decode_segment(value: str, label: str) -> dict[str, Any]:
    try:
        padding = "=" * (-len(value) % 4)
        decoded = base64.urlsafe_b64decode((value + padding).encode("ascii"))
        parsed = json.loads(decoded)
    except (UnicodeError, ValueError, json.JSONDecodeError) as exc:
        raise OAuthImportError(f"{label} không hợp lệ") from exc
    if not isinstance(parsed, dict):
        raise OAuthImportError(f"{label} không hợp lệ")
    return parsed


def _decode_jwt(value: str, label: str) -> dict[str, Any]:
    if not isinstance(value, str) or not value or len(value) > 64 * 1024:
        raise OAuthImportError(f"{label} không hợp lệ")
    parts = value.split(".")
    if len(parts) != 3 or any(not part for part in parts):
        raise OAuthImportError(f"{label} không hợp lệ")
    header = _decode_segment(parts[0], label)
    if header.get("alg") != "RS256" or not str(header.get("kid") or "").strip():
        raise OAuthImportError(f"{label} không hợp lệ")
    return _decode_segment(parts[1], label)


def _single_audience(value: Any, client_id: str) -> bool:
    if isinstance(value, str):
        return value == client_id
    return isinstance(value, list) and client_id in value and all(isinstance(item, str) for item in value)


def _non_empty(value: Any, label: str, maximum: int = 512) -> str:
    text = str(value or "").strip()
    if not text or len(text) > maximum or any(ord(character) < 32 for character in text):
        raise OAuthImportError(f"{label} không hợp lệ")
    return text


def _account_id(claims: dict[str, Any], label: str) -> str:
    auth = claims.get(AUTH_CLAIM)
    if not isinstance(auth, dict):
        raise OAuthImportError(f"{label} thiếu account")
    return _non_empty(auth.get("chatgpt_account_id"), f"{label} account", 256)


def build_auth_document(
    client_id: str,
    id_token: str,
    access_token: str,
    refresh_token: str,
    *,
    now: str | None = None,
    login_owner_id: str | None = None,
) -> tuple[dict[str, Any], ImportedIdentity]:
    """Build the exact ChatGPT ``auth.json`` shape consumed by Codex."""

    client_id = _non_empty(client_id, "OAuth client", 256)
    if CLIENT_ID_PATTERN.fullmatch(client_id) is None:
        raise OAuthImportError("OAuth client không hợp lệ")
    refresh_token = _non_empty(refresh_token, "Refresh token", 16 * 1024)

    identity_claims = _decode_jwt(id_token, "ID token")
    access_claims = _decode_jwt(access_token, "Access token")
    if identity_claims.get("iss") != AUTH_ISSUER:
        raise OAuthImportError("ID token issuer không hợp lệ")
    if not _single_audience(identity_claims.get("aud"), client_id):
        raise OAuthImportError("ID token client không khớp")
    if access_claims.get("iss") not in (None, AUTH_ISSUER):
        raise OAuthImportError("Access token issuer không hợp lệ")
    if _non_empty(access_claims.get("client_id"), "Access token client", 256) != client_id:
        raise OAuthImportError("Access token client không khớp")

    subject = _non_empty(identity_claims.get("sub"), "ID token subject", 512)
    access_subject = _non_empty(access_claims.get("sub"), "Access token subject", 512)
    if not secrets.compare_digest(subject, access_subject):
        raise OAuthImportError("OAuth subject không khớp")
    if identity_claims.get("email_verified") is not True:
        raise OAuthImportError("Email OAuth chưa được xác minh")
    email = _non_empty(identity_claims.get("email"), "OAuth email", 320).lower()

    identity_account = _account_id(identity_claims, "ID token")
    access_account = _account_id(access_claims, "Access token")
    if not secrets.compare_digest(identity_account, access_account):
        raise OAuthImportError("OAuth account không khớp")

    refreshed_at = now or datetime.now(timezone.utc).isoformat(timespec="seconds")
    owner_id = login_owner_id or secrets.token_urlsafe(32)
    document = {
        "OPENAI_API_KEY": None,
        "auth_mode": "chatgpt",
        "last_refresh": refreshed_at,
        "tokens": {
            "access_token": access_token,
            "account_id": identity_account,
            "id_token": id_token,
            "login_owner_id": owner_id,
            "oauth_provenance": {
                "client_id": client_id,
                "issuer": AUTH_ISSUER,
            },
            "refresh_token": refresh_token,
        },
    }
    return document, ImportedIdentity(identity_account, subject, email)


def _atomic_write(path: Path, contents: bytes, mode: int) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        with temporary.open("wb") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def install_and_verify(
    auth_path: Path,
    document: dict[str, Any],
    snapshot_reader: Callable[[], dict[str, Any]],
) -> dict[str, Any]:
    """Install credentials and retain them only if Codex returns a healthy snapshot."""

    auth_path = Path(auth_path)
    existed = auth_path.is_file()
    previous = auth_path.read_bytes() if existed else None
    previous_mode = auth_path.stat().st_mode & 0o777 if existed else 0o600
    contents = (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    _atomic_write(auth_path, contents, 0o600)
    try:
        snapshot = snapshot_reader()
        if not isinstance(snapshot, dict) or snapshot.get("ok") is not True:
            raise OAuthImportError("Codex không xác nhận được account vừa đăng nhập")
        return snapshot
    except Exception:
        if previous is None:
            try:
                auth_path.unlink()
            except FileNotFoundError:
                pass
        else:
            _atomic_write(auth_path, previous, previous_mode)
        raise
