"""Check device-code issuance in a temporary VPS slot, then archive it."""
import importlib.util
import json
from pathlib import Path
import sys

path = Path('/opt/codex-cockpit/server.py')
sys.path.insert(0, str(path.parent))
spec = importlib.util.spec_from_file_location('device_smoke_server', path)
server = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = server
spec.loader.exec_module(server)
bridge = server.AppActionBridge(server.CONFIG_PATH)
before = {str(a['id']) for a in server.read_json(server.CONFIG_PATH, {})['accounts']}
account = bridge.create_account('Device login smoke')
try:
    session = bridge.start_login(account['id'])
    if session['status'] != 'waiting' or not session.get('user_code'):
        raise RuntimeError('Device login did not issue a code')
    reopened = json.loads(json.dumps(bridge.start_login(account['id'])))
    if reopened.get('user_code') != session['user_code']:
        raise RuntimeError('Reopening login did not return the existing code')
    print(json.dumps({'device_code_issued': True, 'status': session['status']}))
    print(json.dumps({'repeated_start_serializable': True, 'same_code_returned': True}))
finally:
    bridge.delete_account(account['id'])
after = {str(a['id']) for a in server.read_json(server.CONFIG_PATH, {})['accounts']}
if before != after:
    raise RuntimeError('Temporary account membership was not restored')
print(json.dumps({'temporary_slot_archived': True, 'membership_restored': True}))
