"""Codex app-server transport used by the VPS dashboard."""
from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time
from typing import Any

APP_VERSION = "1.0.0"

class RpcError(RuntimeError):
    pass


class CodexAppServer:
    def __init__(self, codex_home: str, codex_bin: str = "codex", timeout: int = 25):
        self.codex_home = codex_home
        self.codex_bin = codex_bin
        self.timeout = timeout
        self.proc: subprocess.Popen[str] | None = None
        self.messages: queue.Queue[dict[str, Any]] = queue.Queue()
        self.notifications: queue.Queue[dict[str, Any]] = queue.Queue()
        self.stderr_lines: list[str] = []
        self.next_id = 1

    def __enter__(self) -> "CodexAppServer":
        env = os.environ.copy()
        env["CODEX_HOME"] = self.codex_home
        self.proc = subprocess.Popen(
            [self.codex_bin, "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        self._request(
            "initialize",
            {
                "clientInfo": {
                    "name": "codex_usage_telegram_bot",
                    "title": "Codex Usage Telegram Bot",
                    "version": APP_VERSION,
                }
            },
        )
        self._send({"method": "initialized", "params": {}})
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        if not self.proc:
            return
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def _read_stdout(self) -> None:
        assert self.proc and self.proc.stdout
        for line in self.proc.stdout:
            try:
                message = json.loads(line)
                # Notifications must reach waiters even when no RPC is in flight.
                if message.get("method") and "id" not in message:
                    self.notifications.put(message)
                else:
                    self.messages.put(message)
            except json.JSONDecodeError:
                continue

    def _read_stderr(self) -> None:
        assert self.proc and self.proc.stderr
        for line in self.proc.stderr:
            clean = line.strip()
            if clean:
                self.stderr_lines = (self.stderr_lines + [clean])[-20:]

    def _send(self, message: dict[str, Any]) -> None:
        if not self.proc or not self.proc.stdin or self.proc.poll() is not None:
            detail = self.stderr_lines[-1] if self.stderr_lines else "process stopped"
            raise RpcError(detail)
        self.proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _request(self, method: str, params: dict[str, Any] | None = None) -> Any:
        request_id = self.next_id
        self.next_id += 1
        self._send({"method": method, "id": request_id, "params": params or {}})
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if self.proc and self.proc.poll() is not None:
                detail = self.stderr_lines[-1] if self.stderr_lines else "app-server exited"
                raise RpcError(detail)
            try:
                message = self.messages.get(timeout=min(0.5, max(0.01, deadline - time.monotonic())))
            except queue.Empty:
                continue
            if message.get("id") != request_id:
                if message.get("method"):
                    self.notifications.put(message)
                continue
            if message.get("error"):
                error = message["error"]
                raise RpcError(str(error.get("message") or error))
            return message.get("result")
        raise RpcError(f"timeout calling {method}")

    def snapshot(self) -> dict[str, Any]:
        account = self._request("account/read", {"refreshToken": True})
        limits = self._request("account/rateLimits/read", {"excludeResetCreditDetails": False})
        try:
            usage = self._request("account/usage/read", {"days": 7})
        except RpcError:
            usage = None
        return {"account": account, "limits": limits, "usage": usage}

    def start_device_login(self) -> dict[str, Any]:
        return self._request("account/login/start", {"type": "chatgptDeviceCode"})

    def consume_reset_credit(
        self, idempotency_key: str, credit_id: str | None = None
    ) -> dict[str, Any]:
        params: dict[str, Any] = {"idempotencyKey": idempotency_key}
        if credit_id:
            params["creditId"] = credit_id
        return self._request("account/rateLimitResetCredit/consume", params)

    def wait_for_login(self, login_id: str, timeout: int = 900) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.proc and self.proc.poll() is not None:
                detail = self.stderr_lines[-1] if self.stderr_lines else "app-server exited"
                raise RpcError(detail)
            try:
                message = self.notifications.get(
                    timeout=min(1.0, max(0.01, deadline - time.monotonic()))
                )
            except queue.Empty:
                continue
            if message.get("method") != "account/login/completed":
                continue
            params = message.get("params") or {}
            if str(params.get("loginId")) != str(login_id):
                continue
            if not params.get("success"):
                raise RpcError(str(params.get("error") or "device login failed"))
            return params
        raise RpcError("device login expired after 15 minutes")


