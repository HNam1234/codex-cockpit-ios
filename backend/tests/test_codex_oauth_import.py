import base64
import json
import os
from pathlib import Path
import tempfile
import unittest

from backend.codex_oauth_import import (
    OAuthImportError,
    build_auth_document,
    install_and_verify,
)


def jwt(payload: dict) -> str:
    def encode(value: dict) -> str:
        raw = json.dumps(value, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    return f"{encode({'alg': 'RS256', 'kid': 'test-key'})}.{encode(payload)}.signature"


def token_pair(*, account_id: str = "acct-123", subject: str = "user-123", client_id: str = "client_1234567890"):
    auth = {
        "chatgpt_account_id": account_id,
        "chatgpt_plan_type": "plus",
        "chatgpt_user_id": subject,
    }
    identity = jwt({
        "iss": "https://auth.openai.com",
        "aud": client_id,
        "sub": subject,
        "email": "Person@Example.com",
        "email_verified": True,
        "https://api.openai.com/auth": auth,
    })
    access = jwt({
        "iss": "https://auth.openai.com",
        "client_id": client_id,
        "sub": subject,
        "https://api.openai.com/auth": auth,
    })
    return client_id, identity, access


class OAuthImportTests(unittest.TestCase):
    def test_builds_codex_auth_for_matching_identity(self):
        client_id, identity, access = token_pair()

        document, imported = build_auth_document(
            client_id,
            identity,
            access,
            "refresh-token-value",
            now="2026-11-15T08:00:00+00:00",
            login_owner_id="login-owner",
        )

        self.assertEqual(imported.account_id, "acct-123")
        self.assertEqual(imported.email, "person@example.com")
        self.assertEqual(document["auth_mode"], "chatgpt")
        self.assertIsNone(document["OPENAI_API_KEY"])
        self.assertEqual(document["tokens"]["id_token"], identity)
        self.assertEqual(document["tokens"]["access_token"], access)
        self.assertEqual(document["tokens"]["refresh_token"], "refresh-token-value")
        self.assertEqual(document["tokens"]["account_id"], "acct-123")
        self.assertEqual(document["tokens"]["login_owner_id"], "login-owner")
        self.assertEqual(document["tokens"]["oauth_provenance"], {
            "issuer": "https://auth.openai.com",
            "client_id": client_id,
        })

    def test_rejects_mismatched_chatgpt_account_before_writing(self):
        client_id, identity, _ = token_pair()
        _, _, other_access = token_pair(account_id="acct-other")

        with self.assertRaisesRegex(OAuthImportError, "account"):
            build_auth_document(client_id, identity, other_access, "refresh-token-value")

    def test_rejects_malformed_jwt(self):
        client_id, _, access = token_pair()

        with self.assertRaisesRegex(OAuthImportError, "ID token"):
            build_auth_document(client_id, "not-a-jwt", access, "refresh-token-value")

    def test_restores_previous_auth_exactly_when_codex_rejects_import(self):
        client_id, identity, access = token_pair()
        document, _ = build_auth_document(client_id, identity, access, "refresh-token-value")
        with tempfile.TemporaryDirectory() as directory:
            auth_path = Path(directory) / "auth.json"
            previous = b'{"old":true}\n'
            auth_path.write_bytes(previous)

            def reject():
                self.assertIn(b'"auth_mode": "chatgpt"', auth_path.read_bytes())
                raise RuntimeError("Codex rejected imported credentials")

            with self.assertRaisesRegex(RuntimeError, "Codex rejected"):
                install_and_verify(auth_path, document, reject)

            self.assertEqual(auth_path.read_bytes(), previous)

    @unittest.skipIf(os.name == "nt", "POSIX permission assertion")
    def test_new_auth_file_is_private_and_verified_snapshot_is_returned(self):
        client_id, identity, access = token_pair()
        document, _ = build_auth_document(client_id, identity, access, "refresh-token-value")
        with tempfile.TemporaryDirectory() as directory:
            auth_path = Path(directory) / "auth.json"

            result = install_and_verify(auth_path, document, lambda: {"ok": True, "windows": [1]})

            self.assertEqual(result, {"ok": True, "windows": [1]})
            self.assertEqual(auth_path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
