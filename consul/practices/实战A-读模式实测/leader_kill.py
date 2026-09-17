"""实战篇 A 关键验证（硬杀版）：leader 进程被强制杀死期间的读行为。

与优雅退出的区别：consul leave 会先交卸 leader 再退出，集群几乎无感知；
硬杀（kill -9）才是真实故障——进程瞬间消失，集群要靠选举超时发现。
"""

import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

BASE = 'http://127.0.0.1:8500'
KEY = 'demo/counter'


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
        return e.code, e.read().decode('utf-8').strip()[:80], e.headers
    except Exception as e:
        return 'ERR', f'{type(e).__name__}', {}


def put(v):
    return call('PUT', '/v1/kv/' + KEY, v)


def read(mode):
    st, body, h = call('GET', '/v1/kv/' + KEY, params=(None if mode == 'default' else mode))
    if st == 200:
        arr = json.loads(body)
        return st, base64.b64decode(arr[0]['Value']).decode('utf-8'), h.get('X-Consul-LastContact')
    return st, body[:50], h.get('X-Consul-LastContact')


def leader():
    st, body, _ = call('GET', '/v1/status/leader')
    return json.loads(body).strip('"') if st == 200 else f'ERR{st}'


put('before-kill')
time.sleep(0.5)
cur = leader()
port_node = {'127.0.0.1:8300': ('node1', 8500), '127.0.0.1:8310': ('node2', 8510),
             '127.0.0.1:8320': ('node3', 8520)}
node, http_port = port_node.get(cur, ('?', 8500))
print(f'当前 leader: {cur} ({node})')

# 用 PowerShell 找到该节点的 consul 进程并强杀
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
print(f'强杀 leader 进程: {r.stdout.strip()}')

print()
print('  时间(ms)  consistent          default             stale               leader')
print('  ' + '-' * 78)
t0 = time.time()
for i in range(30):
    el = int((time.time() - t0) * 1000)
    rc = read('consistent')
    rd = read('default')
    rs = read('stale')
    ld = leader()

    def fmt(r):
        if r[0] == 200:
            return f'{r[1]:16s}'
        return f'FAIL({r[0]}){"":<10s}'

    print(f'  {el:7d}  {fmt(rc)}  {fmt(rd)}  {fmt(rs)}  {ld}')
    time.sleep(0.35)

print()
print(f'最终 leader: {leader()}')
