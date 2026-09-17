"""实战篇 A 补充验证：多数派丢失（quorum 丢失）时的读写行为。

三节点杀掉两个，只剩一个——此时没有 quorum。
这是"stale 读"最有价值的场景：其它模式全挂，只有它还能返回数据。
"""

import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

BASE = 'http://127.0.0.1:8520'
KEY = 'demo/counter'
PORT_NODE = {'127.0.0.1:8300': 'node1', '127.0.0.1:8310': 'node2', '127.0.0.1:8320': 'node3'}


def call(method, path, body=None, params=None, timeout=4):
    url = BASE + path
    if params:
        url += '?' + params
    data = body.encode('utf-8') if isinstance(body, str) else body
    headers = {'Content-Type': 'application/json'} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode('utf-8'), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8').strip()[:100], e.headers
    except Exception as e:
        return 'ERR', f'{type(e).__name__}', {}


def read(mode):
    st, body, h = call('GET', '/v1/kv/' + KEY, params=(None if mode == 'default' else mode))
    if st == 200:
        arr = json.loads(body)
        return st, base64.b64decode(arr[0]['Value']).decode('utf-8')
    return st, body[:70]


def write(v):
    st, body, h = call('PUT', '/v1/kv/' + KEY, v)
    return st, body[:70]


def leader():
    st, body, _ = call('GET', '/v1/status/leader')
    return json.loads(body).strip('"') if st == 200 else f'ERR({st})'


def kill(node):
    ps = f'''
$target = $null
Get-CimInstance Win32_Process -Filter "Name='consul.exe'" | ForEach-Object {{
  if ($_.CommandLine -like '*{node}*') {{ $target = $_.ProcessId }}
}}
if ($target) {{ Stop-Process -Id $target -Force; Write-Output "killed $target" }}
else {{ Write-Output "not found" }}
'''
    r = subprocess.run(['powershell', '-NoProfile', '-Command', ps],
                       capture_output=True, text=True, timeout=30)
    return r.stdout.strip()


print('=' * 70)
print('quorum 丢失场景：三节点杀两个，只剩 node3')
print('=' * 70)
print(f'读取节点: {BASE} (node3)')
print(f'当前 leader: {leader()}')

print('\n杀掉 node1 与 node2 ...')
print('  node1:', kill('node1'))
print('  node2:', kill('node2'))
time.sleep(3)

print()
print('=== 只剩一个节点时的读写 ===')
for label, fn in [
    ('写（PUT）', lambda: write('after-quorum-loss')),
    ('consistent 读', lambda: read('consistent')),
    ('default 读', lambda: read('default')),
    ('stale 读', lambda: read('stale')),
]:
    st, val = fn()
    mark = 'OK' if st == 200 else '不可用'
    print(f'  {label:16s} -> {st}  {mark}  {val}')

print()
print('=== 健康端点（/v1/health/service/consul）===')
st, body, _ = call('GET', '/v1/health/service/consul')
print(f'  -> {st} {body[:100]}')

print()
print('=== 连 catalog 都还能查吗 ===')
for ep in ['/v1/catalog/nodes', '/v1/status/leader', '/v1/status/peers']:
    st, body, _ = call('GET', ep)
    print(f'  {ep:22s} -> {st} {body[:70]}')
