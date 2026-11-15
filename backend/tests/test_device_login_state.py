import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest

from backend.server import AppActionBridge, status_payload


class DeviceLoginStateTests(unittest.TestCase):
    def test_reopening_waiting_login_returns_json_serializable_device_code(self):
        bridge = AppActionBridge.__new__(AppActionBridge)
        bridge.lock = threading.Lock()
        bridge._config_and_account = lambda account_id: ({}, {"id": account_id})
        bridge.logins = {"existing": {
            "session_id": "existing",
            "account_id": "2",
            "status": "waiting",
            "user_code": "ABCD-EFGH",
            "ready": threading.Event(),
        }}

        result = bridge.start_login("2")
        response = json.loads(json.dumps({"ok": True, "login": result}))

        self.assertEqual(response["login"]["user_code"], "ABCD-EFGH")
        self.assertNotIn("ready", response["login"])
        self.assertEqual(len(bridge.logins), 1)

    def test_successful_device_login_persists_quota_for_next_status_load(self):
        class Client:
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def start_device_login(self):
                return {"loginId": "login", "userCode": "ABCD-EFGH"}
            def wait_for_login(self, *_args, **_kwargs): pass
            def snapshot(self): return {"raw": True}

        with tempfile.TemporaryDirectory() as directory:
            state_path = Path(directory) / "state.json"
            account = {"id": "3", "name": "Codex 3"}
            config = {"accounts": [account], "state_path": str(state_path)}
            normalized = {
                "ok": True,
                "email": "device@example.com",
                "windows": {"primary": {"remaining_percent": 73, "window_minutes": 300}},
            }
            bridge = AppActionBridge.__new__(AppActionBridge)
            bridge.lock = threading.Lock()
            bridge.cancelled_accounts = set()
            bridge.login_clients = {}
            bridge.logins = {"session": {"ready": threading.Event()}}
            bridge.watch = SimpleNamespace(normalize_snapshot=lambda *_: normalized)
            bridge._client = lambda *_: Client()

            bridge._login_worker_unlocked("session", config, account)

            self.assertEqual(bridge.logins["session"]["status"], "succeeded")
            state = json.loads(state_path.read_text())
            self.assertIsInstance(state["accounts"]["3"]["windows"], dict)
            reloaded = status_payload(config, state)["accounts"][0]
            self.assertEqual(reloaded["email"], "device@example.com")
            self.assertEqual(reloaded["windows"][0]["remaining_percent"], 73)
