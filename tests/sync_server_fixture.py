"""Prepare and verify an isolated localhost backend for native sync tests."""
import json
from pathlib import Path
import http.cookiejar
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = 'http://127.0.0.1:8082'
folder = ROOT / '.cache/sync-tests'
client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

def request(path, value=None):
    body = json.dumps(value).encode() if value is not None else None
    req = urllib.request.Request(BASE + path, data=body, headers={'Content-Type': 'application/json'})
    with client.open(req, timeout=10) as response:
        return json.load(response)

status = request('/api/v1/auth/status')
if not status['initialized']:
    code = (folder / 'server-data/setup-code').read_text().strip()
    request('/api/v1/auth/setup', {'code': code, 'username': 'reader', 'password': 'test-password-only'})
else:
    request('/api/v1/auth/login', {'username': 'reader', 'password': 'test-password-only'})

import sys
if '--verify' in sys.argv:
    result = json.loads((folder/'result.json').read_text())
    data = request('/api/v1/dashboard?device=' + result['device_id'])
    assert not data['demo'] and len(data['books']) == 3 and len(data['achievements']) == 42
    assert len(data['activity']) == result['activity']
    assert data['source_device'] == result['device_id'] and result['sequence'] == 2
    print('Verified dashboard received native books, statistics and all 42 achievements without duplicate activity.')
else:
    offer = request('/api/v1/pairing', {})
    (folder/'live.json').write_text(json.dumps({'server': 'http://kindlevel-test.local:8082', 'code': offer['code']}))
    (folder/'live.json').chmod(0o600)
    print('Prepared one-time pairing fixture for the isolated local server.')
