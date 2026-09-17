"""实战篇 A 关键验证（修正版）：leader 被强杀期间，从【存活节点】读。

上一版脚本的错误：一直访问 8500，而被杀的正是 node1（8500）——
所以三种模式全失败，那是"连不上 agent"，不是"读模式"的差异。

这一版固定从存活节点（node2=8510）读，才能看出三种模式的真实区别。

附带的重要发现：应用只连一个 agent 时，那个 agent 挂了，
三种读模式全都救不了——这是"读模式"之外的可用性问题。
"""

import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

# 从存活节点读
BASE = 'http://127.0.0.1:8510'
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
        return e.code, e.read().decode('utf-8').strip()[:90], e.headers
    except Exception as e:
        return 'ERR', f'{type(e).__name__}', {}


def put(v):
    return call('PUT', '/v1/kv/' + KEY, v)


def read(mode):
    st, body, h = call('GET', '/v1/kv/' + KEY, params=(None if mode == 'default' else mode))
    if st == 200:
        arr = json.loads(body)
        return st, base64.b64decode(arr[0]['Value']).decode('utf-8'), h.get('X-Consul-LastContact')
    return st, body[:60], h.get('X-Consul-LastContact')


def leader():
    st, body, _ = call('GET', '/v1/status/leader')
    return json.loads(body).strip('"') if st == 200 else f'ERR({st})'


print('=' * 74)
print('leader 被强杀期间，从存活节点(8510)读——三种模式对比')
print('=' * 74)

put('before-kill')
time.sleep(0.5)
cur = leader()
node = PORT_NODE.get(cur, '?')
print(f'当前 leader: {cur} ({node})')
print(f'读取节点   : 127.0.0.1:8510 (node2)')
print(f'失效前值   : {read("consistent")}')

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
print(f'\n强杀 leader 进程: {r.stdout.strip()}')

print()
print('  时间(ms)  consistent        default            stale              leader')
print('  ' + '-' * 76)
t0 = time.time()
for i in range(28):
    el = int((time.time() - t0) * 1000)
    rc, rd, rs = read('consistent'), read('default'), read('stale')
    ld = leader()

    def fmt(r):
        if r[0] == 200:
            return f'{r[1]:16s}'
        return f'FAIL({r[0]}){"":<9s}'

    print(f'  {el:7d}  {fmt(rc)}  {fmt(rd)}  {fmt(rs)}  {ld}')
    time.sleep(0.35)

print()
print(f'最终 leader: {leader()}')
