#!/usr/bin/env python3
"""Read-only Cockpit-style dashboard for Codex quota snapshots."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import importlib.util
import json
import mimetypes
import os
import re
import secrets
import sys
import threading
import time
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote, urlparse

if __package__:
    from .codex_oauth_import import import_oauth_credentials
else:
    from codex_oauth_import import import_oauth_credentials

try:
    from zoneinfo import ZoneInfo

    LOCAL_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
except Exception:
    LOCAL_TZ = timezone(timedelta(hours=7), name="Asia/Saigon")

CONFIG_PATH = Path(os.environ.get("CODEX_WATCH_CONFIG", "/etc/codex-usage-bot/config.json"))
STATIC_DIR = Path(os.environ.get("COCKPIT_STATIC_DIR", Path(__file__).with_name("static")))
SESSION_COOKIE = "codex_cockpit_session"
LOGIN_TTL = 10 * 60
SESSION_TTL = 7 * 24 * 60 * 60
APP_SESSION_TTL = 365 * 24 * 60 * 60


def load_watch_module() -> Any:
    candidates = [
        Path(os.environ.get("CODEX_WATCH_MODULE", "")),
        Path("/opt/codex-usage-bot/codex_watch.py"),
        Path(__file__).resolve().parent.parent / "codex-usage-telegram-bot" / "codex_watch.py",
    ]
    path = next((candidate for candidate in candidates if str(candidate) and candidate.is_file()), None)
    if path is None:
        raise RuntimeError("codex_watch.py bridge module was not found")
    name = "codex_watch_bridge"
    existing = sys.modules.get(name)
    if existing is not None:
        return existing
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load codex_watch.py bridge module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def read_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def save_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        os.chmod(temp, 0o640)
        os.replace(temp, path)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def dashboard_config(config: dict[str, Any]) -> dict[str, Any]:
    value = config.get("web_dashboard") or {}
    if not value.get("secret"):
        raise RuntimeError("web_dashboard.secret is missing")
    return value


def sign_token(secret: str, kind: str, issued_at: int, nonce: str) -> str:
    payload = f"{kind}:{issued_at}.{nonce}".encode()
    return hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()


def make_token(secret: str, kind: str, now: int | None = None) -> str:
    issued_at = int(now or time.time())
    nonce = secrets.token_urlsafe(18)
    signature = sign_token(secret, kind, issued_at, nonce)
    return f"{issued_at}.{nonce}.{signature}"


def validate_token(token: str, secret: str, kind: str, ttl: int, now: int | None = None) -> bool:
    try:
        issued_text, nonce, supplied = token.split(".", 2)
        issued_at = int(issued_text)
    except (ValueError, AttributeError):
        return False
    current = int(now or time.time())
    if issued_at > current + 60 or current - issued_at > ttl:
        return False
    expected = sign_token(secret, kind, issued_at, nonce)
    return hmac.compare_digest(supplied, expected)


def app_token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def validate_app_token(token: str, expected_hash: str) -> bool:
    return bool(token and expected_hash and hmac.compare_digest(app_token_hash(token), expected_hash))


def login_url(config: dict[str, Any], now: int | None = None) -> str:
    web = dashboard_config(config)
    base = str(web.get("base_url") or "").rstrip("/")
    if not base.startswith("https://") and not base.startswith("http://127.0.0.1"):
        raise RuntimeError("web_dashboard.base_url must be HTTPS")
    return f"{base}/login?t={quote(make_token(str(web['secret']), 'login', now))}"


def clean_error(value: Any) -> str:
    text = str(value or "Chưa đăng nhập hoặc chưa đọc được quota")
    lowered = text.lower()
    if "login" in lowered or "auth" in lowered or "credential" in lowered:
        return "Cần đăng nhập lại tài khoản Codex"
    if "timeout" in lowered:
        return "Codex phản hồi quá thời gian"
    return text[:180]


def safe_snapshot(account: dict[str, Any], snapshot: dict[str, Any] | None) -> dict[str, Any]:
    snapshot = snapshot or {}
    windows = []
    for window in (snapshot.get("windows") or {}).values():
        windows.append(
            {
                "label": str(window.get("label") or "Quota"),
                "remaining_percent": round(float(window.get("remaining_percent") or 0), 1),
                "used_percent": round(float(window.get("used_percent") or 0), 1),
                "resets_at": int(window.get("resets_at") or 0),
                "window_minutes": int(window.get("window_minutes") or 0),
            }
        )
    windows.sort(key=lambda item: (item["window_minutes"] or 10**9, item["label"]))
    ok = bool(snapshot.get("ok"))
    return {
        "id": str(account.get("id") or ""),
        "name": str(account.get("name") or f"Codex {account.get('id', '')}"),
        "display_name": snapshot.get("display_name"),
        "email": snapshot.get("email"),
        "plan": snapshot.get("plan"),
        "subscription_expires_at": int(snapshot.get("subscription_expires_at") or 0) or None,
        "ok": ok,
        "error": None if ok else clean_error(snapshot.get("error")),
        "windows": windows,
        "reset_credits": int(snapshot.get("reset_credits") or 0),
        "checked_at": int(snapshot.get("checked_at") or 0),
    }


def app_profiles(config: dict[str, Any]) -> list[dict[str, str]]:
    return [
        {
            "id": str(account.get("id") or ""),
            "name": str(account.get("name") or f"Codex {account.get('id', '')}"),
        }
        for account in config.get("accounts", [])
        if str(account.get("id") or "")
    ]


class TiboHintEngine:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.lock = threading.Lock()
        self.value: dict[str, Any] = {
            "status": "unknown",
            "kind": None,
            "message": "Chưa tải được dự đoán reset toàn hệ thống.",
            "latest_at": None,
            "pending_at": None,
            "fetched_at": 0,
            "source": "https://opentherank.com/codex-reset/",
            "x_source": "https://x.com/thsottiaux",
            "latest_post": None,
            "hint_post": None,
            "probability_today": None,
            "probability_basis": "Ước tính từ lịch sử reset và tín hiệu X công khai.",
            "stale": True,
        }
        self.last_fetched = 0
        threading.Thread(target=self._loop, daemon=True, name="tibo-hints").start()

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            result = json.loads(json.dumps(self.value))
        result["stale"] = int(time.time()) - int(result.get("fetched_at") or 0) > 60 * 60
        return result

    @staticmethod
    def _tweet_payload(text: str, tweet_id: str, created_at_ms: int) -> dict[str, Any]:
        return {
            "text": text.strip(),
            "id": tweet_id,
            "created_at": datetime.fromtimestamp(created_at_ms / 1000, timezone.utc).isoformat(),
            "url": f"https://x.com/thsottiaux/status/{tweet_id}",
        }

    @staticmethod
    def _parse_tibo_tweets(page: str) -> list[dict[str, Any]]:
        tweets: dict[str, dict[str, Any]] = {}

        def walk(value: Any) -> None:
            if isinstance(value, dict):
                details = value.get("details")
                tweet_id = str(value.get("rest_id") or "")
                user = (
                    value.get("core", {})
                    .get("user_results", {})
                    .get("result", {})
                    .get("core", {})
                )
                if (
                    isinstance(details, dict)
                    and tweet_id.isdigit()
                    and str(user.get("screen_name") or "").lower() == "thsottiaux"
                ):
                    text = str(details.get("full_text") or "").strip()
                    created = int(details.get("created_at_ms") or 0)
                    if text and created:
                        tweets[tweet_id] = TiboHintEngine._tweet_payload(text, tweet_id, created)
                for item in value.values():
                    walk(item)
            elif isinstance(value, list):
                for item in value:
                    walk(item)

        decoder = json.JSONDecoder()
        for script in re.findall(r"<script[^>]*>(.*?)</script>", page, re.DOTALL):
            if "profile_user_originals_timeline" not in script:
                continue
            offset = script.find("value:")
            if offset < 0:
                continue
            try:
                encoded, _ = decoder.raw_decode(script, offset + len("value:"))
                if isinstance(encoded, str):
                    walk(json.loads(encoded))
            except (json.JSONDecodeError, TypeError, ValueError):
                continue
        return sorted(tweets.values(), key=lambda item: item["created_at"], reverse=True)

    def _fetch_x(self) -> list[dict[str, Any]]:
        source = "https://x.com/thsottiaux?lang=en"
        request = urllib.request.Request(
            source,
            headers={
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
                "AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
                "Accept-Language": "en-US,en;q=0.9",
            },
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            page = response.read().decode("utf-8", "replace")
        return self._parse_tibo_tweets(page)

    @staticmethod
    def _reset_probability(
        reset_dates: list[datetime], now: int, hint_post: dict[str, Any] | None
    ) -> tuple[int, str]:
        today = datetime.fromtimestamp(now, timezone.utc).date()
        distinct = sorted({item.date() for item in reset_dates})
        if not distinct:
            return 20, "Ước tính sơ bộ; tracker chưa đủ lịch sử."
        if distinct[-1] == today:
            return 100, "Reset hôm nay đã được tracker xác nhận."

        weekday_total = 0
        cursor = distinct[0]
        while cursor <= today:
            if cursor.weekday() == today.weekday():
                weekday_total += 1
            cursor += timedelta(days=1)
        weekday_hits = sum(1 for item in distinct if item.weekday() == today.weekday())
        weekday_rate = 100 * (weekday_hits + 1) / (weekday_total + 2)

        gaps = [(right - left).days for left, right in zip(distinct, distinct[1:]) if right > left]
        gap_now = max(1, (today - distinct[-1]).days)
        survivors = [gap for gap in gaps if gap >= gap_now]
        exact = [gap for gap in survivors if gap == gap_now]
        hazard = 100 * (len(exact) + 1) / (len(survivors) + 2)
        probability = 0.65 * hazard + 0.35 * weekday_rate
        reason = "Lịch sử theo khoảng cách reset và thứ trong tuần."

        if hint_post:
            posted = datetime.fromisoformat(str(hint_post["created_at"])).timestamp()
            age_hours = max(0, (now - posted) / 3600)
            text = str(hint_post.get("text") or "").lower()
            if age_hours <= 72:
                if "reset" in text and ("today" in text or "hôm nay" in text):
                    probability = max(probability, 94)
                    reason = "TIBO nói reset hôm nay; tracker chưa xác nhận hoàn tất."
                elif "banked" in text:
                    probability = max(probability, 88)
                    reason = "TIBO nhắc banked reset gần đây."
                elif "reset" in text:
                    probability += 28
                    reason = "Lịch sử cộng tín hiệu reset gần đây trên X."
                elif "friday" in text:
                    probability += 16
                    reason = "Lịch sử cộng tín hiệu “It's Friday” gần đây của TIBO."
        return max(3, min(97, round(probability))), reason

    def _fetch(self, now: int) -> dict[str, Any]:
        source = "https://opentherank.com/codex-reset/"
        request = urllib.request.Request(source, headers={"User-Agent": "CodexCockpit/1.2"})
        with urllib.request.urlopen(request, timeout=12) as response:
            page = response.read().decode("utf-8", "replace")
        hero = re.search(r'<section class="cx-hero"[^>]*>', page)
        if hero is None:
            raise ValueError("OpenTheRank reset tracker format changed")
        tag = hero.group(0)
        last_match = re.search(r'data-last="([^"]+)"', tag)
        pending_match = re.search(r'data-pending="([^"]+)"', tag)
        kind_match = re.search(r'<article class="cx-post"[^>]*data-type="([^"]+)"', page)
        reset_dates = [
            datetime.fromisoformat(value.replace("Z", "+00:00"))
            for value in re.findall(
                r'class="cx-stamp"[^>]*data-at="([^"]+)"[^>]*data-type="(?:regular|banked)"',
                page,
            )
        ]
        latest_at = last_match.group(1) if last_match else None
        pending_at = pending_match.group(1) if pending_match else None
        kind = kind_match.group(1) if kind_match else None

        latest_dt = (
            datetime.fromisoformat(latest_at.replace("Z", "+00:00")) if latest_at else None
        )
        pending_dt = (
            datetime.fromisoformat(pending_at.replace("Z", "+00:00")) if pending_at else None
        )
        local_now = datetime.fromtimestamp(now, LOCAL_TZ)
        if pending_dt and pending_dt.timestamp() > now - 24 * 60 * 60:
            status = "likely"
            local_pending = pending_dt.astimezone(LOCAL_TZ).strftime("%H:%M %d/%m")
            message = f"TIBO: Có tín hiệu reset toàn hệ thống; dự kiến khoảng {local_pending}."
        elif latest_dt and latest_dt.astimezone(LOCAL_TZ).date() == local_now.date():
            status = "yes"
            local_latest = latest_dt.astimezone(LOCAL_TZ).strftime("%H:%M")
            label = "banked reset" if kind == "banked" else "reset toàn bộ"
            message = f"TIBO: Đã ghi nhận {label} hôm nay lúc {local_latest}."
        else:
            status = "no"
            if latest_dt:
                local_latest = latest_dt.astimezone(LOCAL_TZ).strftime("%H:%M %d/%m")
                message = f"TIBO: Chưa ghi nhận reset toàn bộ hôm nay. Lần gần nhất {local_latest}."
            else:
                message = "TIBO: Chưa ghi nhận reset toàn bộ hôm nay."
        try:
            tweets = self._fetch_x()
        except Exception as exc:
            print(f"TIBO X refresh failed: {exc}", flush=True)
            tweets = []
        latest_post = tweets[0] if tweets else None
        hint_post = next(
            (
                item
                for item in tweets
                if any(term in str(item.get("text") or "").lower() for term in ("reset", "banked", "friday"))
            ),
            None,
        )
        probability, probability_basis = self._reset_probability(reset_dates, now, hint_post)
        return {
            "status": status,
            "kind": kind,
            "message": message,
            "latest_at": latest_at,
            "pending_at": pending_at,
            "fetched_at": now,
            "source": source,
            "x_source": "https://x.com/thsottiaux",
            "latest_post": latest_post,
            "hint_post": hint_post,
            "probability_today": probability,
            "probability_basis": probability_basis,
            "stale": False,
        }

    def refresh(self, force: bool = False) -> None:
        now = int(time.time())
        with self.lock:
            due = force or now - self.last_fetched >= 15 * 60
        if not due:
            return
        value = self._fetch(now)
        with self.lock:
            self.value = value
            self.last_fetched = now

    def _loop(self) -> None:
        while True:
            try:
                self.refresh()
            except Exception as exc:
                print(f"TIBO hint refresh failed: {exc}", flush=True)
            time.sleep(60)


class AppActionBridge:
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.watch = load_watch_module()
        self.lock = threading.Lock()
        self.logins: dict[str, dict[str, Any]] = {}
        self.login_clients: dict[str, Any] = {}
        self.cancelled_accounts: set[str] = set()
        self.account_locks: dict[str, threading.Lock] = {}

    def _config_and_account(self, account_id: str) -> tuple[dict[str, Any], dict[str, Any]]:
        config = read_json(self.config_path, {})
        account = next(
            (item for item in config.get("accounts", []) if str(item.get("id")) == str(account_id)),
            None,
        )
        if account is None:
            raise ValueError("Tài khoản không tồn tại")
        return config, account

    def _client(self, config: dict[str, Any], account: dict[str, Any]) -> Any:
        return self.watch.CodexAppServer(
            str(account["codex_home"]),
            str(config.get("codex_bin") or "codex"),
            int(config.get("codex_timeout_seconds") or 25),
        )

    @staticmethod
    def _accounts_root(config: dict[str, Any]) -> Path:
        state_path = Path(config.get("state_path") or "/var/lib/codex-usage-bot/state.json")
        return Path(config.get("accounts_root") or state_path.parent / "accounts")

    def _account_lock(self, account_id: str) -> threading.Lock:
        with self.lock:
            return self.account_locks.setdefault(str(account_id), threading.Lock())

    def _commit_raw_snapshot(
        self, config: dict[str, Any], account_id: str, snapshot: dict[str, Any]
    ) -> None:
        state_path = Path(config.get("state_path") or "/var/lib/codex-usage-bot/state.json")
        with self.lock:
            state = read_json(state_path, {"accounts": {}, "muted_until": 0})
            accounts = state.setdefault("accounts", {})
            if not isinstance(accounts, dict):
                accounts = {}
                state["accounts"] = accounts
            accounts[str(account_id)] = snapshot
            save_json_atomic(state_path, state)

    def create_account(self, requested_name: str) -> dict[str, Any]:
        with self.lock:
            config = read_json(self.config_path, {})
            accounts = list(config.get("accounts") or [])
            numeric_ids = [int(str(item.get("id"))) for item in accounts if str(item.get("id") or "").isdigit()]
            sequence = max([int(config.get("account_sequence") or 0), *numeric_ids], default=0) + 1
            account_id = str(sequence)
            name = re.sub(r"\s+", " ", str(requested_name or "").strip())[:64]
            if not name:
                name = f"Codex {account_id}"
            root = self._accounts_root(config).resolve()
            root.mkdir(parents=True, exist_ok=True)
            home = (root / account_id).resolve()
            if home.parent != root or home.exists():
                raise ValueError("Không thể cấp vùng dữ liệu cho account mới")
            home.mkdir(mode=0o700)
            account = {"id": account_id, "name": name, "codex_home": str(home)}
            config["accounts"] = [*accounts, account]
            config["account_sequence"] = sequence
            try:
                save_json_atomic(self.config_path, config)
            except Exception:
                home.rmdir()
                raise
        return safe_snapshot(account, {"error": "Cần đăng nhập bằng device code"})

    def delete_account(self, account_id: str) -> bool:
        account_id = str(account_id)
        with self.lock:
            self.cancelled_accounts.add(account_id)
            client = self.login_clients.get(account_id)
            for session in self.logins.values():
                if session["account_id"] == account_id and session["status"] in ("creating", "waiting"):
                    session.update({"status": "failed", "error": "Account đã bị xóa"})
                    session["ready"].set()
        if client is not None and getattr(client, "proc", None) is not None:
            try:
                client.proc.terminate()
            except OSError:
                pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            with self.lock:
                if account_id not in self.login_clients:
                    break
            time.sleep(0.05)
        with self._account_lock(account_id), self.lock:
            config = read_json(self.config_path, {})
            accounts = list(config.get("accounts") or [])
            account = next((item for item in accounts if str(item.get("id")) == str(account_id)), None)
            if account is None:
                raise ValueError("Tài khoản không tồn tại")
            root = self._accounts_root(config).resolve()
            home = Path(str(account.get("codex_home") or "")).resolve()
            if home.parent != root:
                raise ValueError("Vùng dữ liệu account không hợp lệ")
            archive_root = (root.parent / "account-archive").resolve()
            archive_root.mkdir(mode=0o700, parents=True, exist_ok=True)
            archive = archive_root / f"{account_id}-{int(time.time())}"
            moved = False
            if home.exists():
                os.replace(home, archive)
                moved = True
            config["accounts"] = [item for item in accounts if str(item.get("id")) != str(account_id)]
            try:
                save_json_atomic(self.config_path, config)
            except Exception:
                if moved:
                    os.replace(archive, home)
                raise
            state_path = Path(config.get("state_path") or "/var/lib/codex-usage-bot/state.json")
            state = read_json(state_path, {})
            if isinstance(state.get("accounts"), dict):
                state["accounts"].pop(str(account_id), None)
                save_json_atomic(state_path, state)
            self.logins = {
                key: value for key, value in self.logins.items() if value["account_id"] != account_id
            }
        return True

    def refresh_account(self, account_id: str) -> dict[str, Any]:
        with self._account_lock(account_id):
            config, account = self._config_and_account(account_id)
            with self._client(config, account) as client:
                raw = client.snapshot()
            normalized = self.watch.normalize_snapshot(account, raw)
            self._commit_raw_snapshot(config, str(account_id), normalized)
            return safe_snapshot(account, normalized)

    def import_oauth(
        self,
        account_id: str,
        client_id: str,
        id_token: str,
        access_token: str,
        refresh_token: str,
    ) -> dict[str, Any]:
        account_id = str(account_id)
        with self._account_lock(account_id):
            config, account = self._config_and_account(account_id)

            def snapshot_reader() -> dict[str, Any]:
                with self._client(config, account) as client:
                    raw = client.snapshot()
                return self.watch.normalize_snapshot(account, raw)

            def commit_snapshot(snapshot: dict[str, Any]) -> None:
                self._commit_raw_snapshot(config, account_id, snapshot)

            snapshot, _ = import_oauth_credentials(
                auth_path=Path(str(account["codex_home"])) / "auth.json",
                client_id=client_id,
                id_token=id_token,
                access_token=access_token,
                refresh_token=refresh_token,
                snapshot_reader=snapshot_reader,
                commit=commit_snapshot,
            )
            return safe_snapshot(account, snapshot)

    def consume_reset_credit(
        self, account_id: str, idempotency_key: str, credit_id: str | None = None
    ) -> dict[str, Any]:
        with self._account_lock(account_id):
            config, account = self._config_and_account(account_id)
            with self._client(config, account) as client:
                result = client.consume_reset_credit(idempotency_key, credit_id)
                raw = client.snapshot()
            return {
                "outcome": str((result or {}).get("outcome") or "unknown"),
                "account": safe_snapshot(account, self.watch.normalize_snapshot(account, raw)),
            }

    def start_login(self, account_id: str) -> dict[str, Any]:
        config, account = self._config_and_account(account_id)
        with self.lock:
            for session in self.logins.values():
                if session["account_id"] == account_id and session["status"] in ("creating", "waiting"):
                    return {key: value for key, value in session.items() if key != "ready"}
            session_id = str(uuid.uuid4())
            session: dict[str, Any] = {
                "session_id": session_id,
                "account_id": account_id,
                "status": "creating",
                "created_at": int(time.time()),
                "expires_at": int(time.time()) + 15 * 60,
                "ready": threading.Event(),
            }
            self.logins[session_id] = session
        threading.Thread(
            target=self._login_worker,
            args=(session_id, config, account),
            daemon=True,
            name=f"codex-login-{account_id}",
        ).start()
        session["ready"].wait(timeout=15)
        return self.login_status(session_id)

    def _login_worker(self, session_id: str, config: dict[str, Any], account: dict[str, Any]) -> None:
        account_id = str(account["id"])
        with self._account_lock(account_id):
            try:
                config, account = self._config_and_account(account_id)
            except ValueError:
                return
            self._login_worker_unlocked(session_id, config, account)

    def _login_worker_unlocked(
        self, session_id: str, config: dict[str, Any], account: dict[str, Any]
    ) -> None:
        account_id = str(account["id"])
        try:
            client = self._client(config, account)
            with client:
                with self.lock:
                    if account_id in self.cancelled_accounts:
                        raise RuntimeError("Account đã bị xóa")
                    self.login_clients[account_id] = client
                login = client.start_device_login()
                login_id = str((login or {}).get("loginId") or "")
                code = str((login or {}).get("userCode") or "")
                if not login_id or not code:
                    raise RuntimeError("Codex app-server không trả device code")
                with self.lock:
                    session = self.logins[session_id]
                    session.update(
                        {
                            "status": "waiting",
                            "verification_url": str(
                                (login or {}).get("verificationUrl")
                                or "https://auth.openai.com/codex/device"
                            ),
                            "user_code": code,
                        }
                    )
                    session["ready"].set()
                client.wait_for_login(login_id, timeout=900)
                with self.lock:
                    if account_id in self.cancelled_accounts:
                        raise RuntimeError("Account đã bị xóa")
                raw = client.snapshot()
            normalized = self.watch.normalize_snapshot(account, raw)
            self._commit_raw_snapshot(config, account_id, normalized)
            snapshot = safe_snapshot(account, normalized)
            with self.lock:
                self.logins[session_id].update(
                    {"status": "succeeded", "completed_at": int(time.time()), "account": snapshot}
                )
        except Exception as exc:
            with self.lock:
                session = self.logins.get(session_id)
                if session is not None:
                    session.update(
                        {
                            "status": "failed",
                            "completed_at": int(time.time()),
                            "error": clean_error(exc),
                        }
                    )
                    session["ready"].set()
        finally:
            with self.lock:
                self.login_clients.pop(account_id, None)

    def login_status(self, session_id: str) -> dict[str, Any]:
        with self.lock:
            session = self.logins.get(session_id)
            if session is None:
                raise ValueError("Phiên đăng nhập không tồn tại hoặc đã hết hạn")
            result = {key: value for key, value in session.items() if key != "ready"}
        return result


def status_payload(
    config: dict[str, Any],
    state: dict[str, Any],
    now: int | None = None,
    tibo_reset: dict[str, Any] | None = None,
) -> dict[str, Any]:
    current = int(now or time.time())
    stored = state.get("accounts") or {}
    accounts = [safe_snapshot(account, stored.get(str(account.get("id")))) for account in config.get("accounts", [])]
    remaining = [w["remaining_percent"] for account in accounts if account["ok"] for w in account["windows"]]
    future_resets = [w["resets_at"] for account in accounts for w in account["windows"] if w["resets_at"] > current]
    updated = max((account["checked_at"] for account in accounts), default=0)
    return {
        "generated_at": current,
        "updated_at": updated,
        "poll_seconds": max(30, int(config.get("poll_seconds") or 120)),
        "capabilities": {
            "reauthorize": True,
            "refresh_usage": True,
            "reset_credit": True,
            "dynamic_profiles": True,
            "manage_accounts": True,
        },
        "tibo_reset": tibo_reset,
        "accounts": accounts,
        "summary": {
            "total": len(accounts),
            "connected": sum(1 for account in accounts if account["ok"]),
            "lowest_remaining": min(remaining) if remaining else None,
            "next_reset": min(future_resets) if future_resets else None,
        },
    }


def security_headers(handler: BaseHTTPRequestHandler) -> None:
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
    handler.send_header("Referrer-Policy", "no-referrer")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.send_header("X-Frame-Options", "DENY")
    handler.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "CodexCockpit/1.0"

    @property
    def app(self) -> "DashboardServer":
        return self.server  # type: ignore[return-value]

    def log_message(self, fmt: str, *args: Any) -> None:
        safe_args = tuple(
            re.sub(r"([?&](?:t|k)=)[^ &\"]+", r"\1<redacted>", value) if isinstance(value, str) else value
            for value in args
        )
        print(f"[{datetime.now(LOCAL_TZ).isoformat(timespec='seconds')}] {self.client_address[0]} {fmt % safe_args}", flush=True)

    def send_bytes(self, status: int, body: bytes, content_type: str, extra: list[tuple[str, str]] | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        security_headers(self)
        for key, value in extra or []:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status: int, value: Any) -> None:
        self.send_bytes(status, json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode(), "application/json; charset=utf-8")

    def normalized_path(self) -> str:
        path = urlparse(self.path).path
        prefix = self.app.base_path
        if prefix != "/" and path == prefix:
            return "/"
        if prefix != "/" and path.startswith(prefix + "/"):
            return path[len(prefix) :]
        return path

    def authenticated(self) -> bool:
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = cookie.get(SESSION_COOKIE)
        return bool(
            morsel
            and (
                validate_token(morsel.value, self.app.secret, "session", SESSION_TTL)
                or validate_token(morsel.value, self.app.secret, "app-session", APP_SESSION_TTL)
            )
        )

    def establish_session(self, kind: str, ttl: int) -> None:
        session = make_token(self.app.secret, kind)
        cookie_path = self.app.base_path if self.app.base_path != "/" else "/"
        headers = [
            ("Set-Cookie", f"{SESSION_COOKIE}={session}; Max-Age={ttl}; Path={cookie_path}; Secure; HttpOnly; SameSite=Strict"),
            ("Location", self.app.base_path.rstrip("/") + "/"),
        ]
        self.send_bytes(HTTPStatus.SEE_OTHER, b"", "text/plain", headers)

    def login_required(self) -> None:
        body = (STATIC_DIR / "login.html").read_bytes()
        self.send_bytes(HTTPStatus.UNAUTHORIZED, body, "text/html; charset=utf-8")

    def read_form(self) -> dict[str, list[str]] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 32 * 1024:
            return None
        return parse_qs(self.rfile.read(length).decode("utf-8", "replace"))

    @staticmethod
    def form_value(form: dict[str, list[str]], key: str) -> str:
        return str((form.get(key) or [""])[0]).strip()

    def native_error(self, status: int, message: str) -> None:
        self.send_json(status, {"ok": False, "error": message})

    def do_GET(self) -> None:  # noqa: N802
        path = self.normalized_path()
        query = parse_qs(urlparse(self.path).query)

        if path == "/api/health":
            self.send_json(HTTPStatus.OK, {"ok": True, "service": "codex-cockpit"})
            return
        if path == "/login":
            token = (query.get("t") or [""])[0]
            if not validate_token(token, self.app.secret, "login", LOGIN_TTL):
                self.login_required()
                return
            self.establish_session("session", SESSION_TTL)
            return
        if path == "/logout":
            cookie_path = self.app.base_path if self.app.base_path != "/" else "/"
            self.send_bytes(
                HTTPStatus.SEE_OTHER,
                b"",
                "text/plain",
                [("Set-Cookie", f"{SESSION_COOKIE}=; Max-Age=0; Path={cookie_path}; Secure; HttpOnly; SameSite=Strict"), ("Location", self.app.base_path.rstrip("/") + "/")],
            )
            return
        if not self.authenticated():
            self.login_required()
            return
        if path == "/api/status":
            config = read_json(self.app.config_path, {})
            state_path = Path(config.get("state_path") or "/var/lib/codex-usage-bot/state.json")
            self.send_json(
                HTTPStatus.OK,
                status_payload(config, read_json(state_path, {}), tibo_reset=self.app.tibo.snapshot()),
            )
            return

        if path in ("/", "/index.html"):
            asset = STATIC_DIR / "index.html"
        else:
            name = path.lstrip("/")
            if "/" in name or name.startswith("."):
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            asset = STATIC_DIR / name
        if not asset.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        mime = mimetypes.guess_type(asset.name)[0] or "application/octet-stream"
        if mime.startswith("text/") or mime in ("application/javascript", "application/json"):
            mime += "; charset=utf-8"
        self.send_bytes(HTTPStatus.OK, asset.read_bytes(), mime)

    def do_POST(self) -> None:  # noqa: N802
        path = self.normalized_path()
        native_paths = {
            "/app-config",
            "/app-status",
            "/app-refresh",
            "/app-auth/start",
            "/app-auth/status",
            "/app-auth/import",
            "/app-reset-credit",
            "/app-account/create",
            "/app-account/delete",
        }
        if path != "/app-login" and path not in native_paths:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        form = self.read_form()
        if form is None:
            if path == "/app-login":
                self.login_required()
            else:
                self.native_error(HTTPStatus.BAD_REQUEST, "Yêu cầu không hợp lệ")
            return
        token = self.form_value(form, "k")
        if not validate_app_token(token, self.app.app_token_sha256):
            if path == "/app-login":
                self.login_required()
            else:
                self.native_error(HTTPStatus.UNAUTHORIZED, "Khóa ứng dụng đã bị thu hồi")
            return
        if path == "/app-config":
            config = read_json(self.app.config_path, {})
            self.send_json(HTTPStatus.OK, {"accounts": app_profiles(config)})
            return
        if path == "/app-status":
            config = read_json(self.app.config_path, {})
            state_path = Path(config.get("state_path") or "/var/lib/codex-usage-bot/state.json")
            self.send_json(
                HTTPStatus.OK,
                status_payload(config, read_json(state_path, {}), tibo_reset=self.app.tibo.snapshot()),
            )
            return
        if path == "/app-login":
            self.establish_session("app-session", APP_SESSION_TTL)
            return

        try:
            if path == "/app-refresh":
                account = self.app.bridge.refresh_account(self.form_value(form, "account_id"))
                self.send_json(HTTPStatus.OK, {"ok": True, "account": account})
                return
            if path == "/app-account/create":
                account = self.app.bridge.create_account(self.form_value(form, "name"))
                self.send_json(HTTPStatus.OK, {"ok": True, "account": account})
                return
            if path == "/app-account/delete":
                deleted = self.app.bridge.delete_account(self.form_value(form, "account_id"))
                self.send_json(HTTPStatus.OK, {"ok": True, "deleted": deleted})
                return
            if path == "/app-auth/start":
                login = self.app.bridge.start_login(self.form_value(form, "account_id"))
                self.send_json(HTTPStatus.OK, {"ok": True, "login": login})
                return
            if path == "/app-auth/import":
                account = self.app.bridge.import_oauth(
                    self.form_value(form, "account_id"),
                    self.form_value(form, "client_id"),
                    self.form_value(form, "id_token"),
                    self.form_value(form, "access_token"),
                    self.form_value(form, "refresh_token"),
                )
                self.send_json(HTTPStatus.OK, {"ok": True, "account": account})
                return
            if path == "/app-auth/status":
                login = self.app.bridge.login_status(self.form_value(form, "session_id"))
                self.send_json(HTTPStatus.OK, {"ok": True, "login": login})
                return
            if path == "/app-reset-credit":
                idempotency_key = self.form_value(form, "idempotency_key")
                if not (8 <= len(idempotency_key) <= 128):
                    raise ValueError("Idempotency key không hợp lệ")
                value = self.app.bridge.consume_reset_credit(
                    self.form_value(form, "account_id"),
                    idempotency_key,
                    self.form_value(form, "credit_id") or None,
                )
                self.send_json(HTTPStatus.OK, {"ok": True, **value})
                return
        except ValueError as exc:
            self.native_error(HTTPStatus.BAD_REQUEST, str(exc))
        except Exception as exc:
            self.native_error(HTTPStatus.BAD_GATEWAY, clean_error(exc))


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], config_path: Path, base_path: str):
        config = read_json(config_path, {})
        web = dashboard_config(config)
        self.config_path = config_path
        self.secret = str(web["secret"])
        self.app_token_sha256 = str(web.get("app_token_sha256") or "")
        self.base_path = "/" + base_path.strip("/") if base_path.strip("/") else "/"
        self.bridge = AppActionBridge(config_path)
        self.tibo = TiboHintEngine(config_path)
        super().__init__(address, DashboardHandler)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("COCKPIT_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("COCKPIT_PORT", "8787")))
    parser.add_argument("--base-path", default=os.environ.get("COCKPIT_BASE_PATH", "/codex"))
    parser.add_argument("--config", type=Path, default=CONFIG_PATH)
    parser.add_argument("--login-url", action="store_true")
    args = parser.parse_args()
    config = read_json(args.config, {})
    if args.login_url:
        print(login_url(config))
        return 0
    server = DashboardServer((args.host, args.port), args.config, args.base_path)
    print(f"Codex Cockpit listening on http://{args.host}:{args.port}{server.base_path}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
