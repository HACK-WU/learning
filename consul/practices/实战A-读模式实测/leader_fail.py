"""实战篇 A 关键验证：leader 失效期间三种读模式的表现。

这是"决策参考"的核心输入： leader 挂了的时候，
你的服务是"读失败"还是"读到旧值"？前者影响可用性，后者影响正确性。
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


def call(method, path, body=None, params=None, timeout=6):
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
        return e.code, e.read().decode('utf-8').strip(), e.headers
    except Exception as e:
        return 'ERR', f'{type(e).__name__}: {str(e)[:80]}', {}


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
    return json.loads(body).strip('"') if st == 200 else f'ERR{st}'


print('=' * 66)
print('leader 失效期间：三种读模式表现')
print('=' * 66)

put('before-fail')
time.sleep(0.5)
print(f'失效前 leader: {leader()}')
print(f'失效前值     : {read("consistent")}')

# 找出 leader 是哪个进程（按 server 端口）
cur = leader()
print(f'\n当前 leader 地址: {cur}')
port_to_node = {'127.0.0.1:8300': 'node1', '127.0.0.1:8310': 'node2', '127.0.0.1:8320': 'node3'}
leader_node = port_to_node.get(cur, '?')
print(f'对应节点: {leader_node}')

print()
print('=== 关键实验：杀掉 leader 后立刻连续读 ===')
print('（预期：consistent 与 default 会失败或阻塞，stale 仍能返回旧值）')
print()
input('按 Enter 开始（脚本会杀掉 leader 进程，需要你确认集群可重建）...') if False else None

# 用 consul leave 优雅退出 leader
print('正在让 leader 离开集群...')
if leader_node == 'node1':
    http_port = 8500
elif leader_node == 'node2':
    http_port = 8510
else:
    http_port = 8520
r = subprocess.run(['consul', 'leave', f'-http-addr=127.0.0.1:{http_port}'],
                   capture_output=True, text=True, timeout=15)
print(f'  consul leave 返回码={r.returncode} out={r.stdout.strip()[:60]} err={r.stderr.strip()[:60]}')

print()
print('  时间(ms)  模式         结果                    LastContact')
print('  ' + '-' * 62)
t0 = time.time()
for i in range(25):
    el = int((time.time() - t0) * 1000)
    for mode in ['consistent', 'default', 'stale']:
        st, val, lc = read(mode)
        result = f'{val}' if st == 200 else f'FAIL({st})'
        print(f'  {el:7d}   {mode:11s}  {result:22s}  {lc}')
    time.sleep(0.4)

print()
print(f'最终 leader: {leader()}')
print('说明：consul leave 是优雅退出，集群会快速选出新 leader。')
print('      若要观察"无 leader 期间"的行为，需要直接 kill 进程（见正文说明）。')
