import io
import json
from types import SimpleNamespace
import unittest

from backend.codex_app_server import CodexAppServer, RpcError


class LoginNotificationTests(unittest.TestCase):
    def test_completion_after_device_code_response_unblocks_login_waiter(self):
        client = CodexAppServer('/unused')
        # The response was already consumed when the browser approves the code.
        event = {'method': 'account/login/completed', 'params': {
            'loginId': 'login-123', 'success': True, 'error': None,
        }}
        client.proc = SimpleNamespace(stdout=io.StringIO(json.dumps(event) + '\n'), poll=lambda: None)
        client._read_stdout()

        try:
            result = client.wait_for_login('login-123', timeout=0.05)
        except RpcError as exc:
            self.fail('Confirmed login never reached its waiter: ' + str(exc))
        self.assertTrue(result['success'])

    def test_rpc_response_stays_available_to_request_reader(self):
        client = CodexAppServer('/unused')
        client.proc = SimpleNamespace(stdout=io.StringIO('{"id":1,"result":{"ok":true}}\n'))
        client._read_stdout()

        self.assertEqual(client.messages.get_nowait()['result'], {'ok': True})
