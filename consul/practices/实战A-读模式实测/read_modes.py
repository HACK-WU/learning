"""实战篇 A：三种读模式（default / consistent / stale）实测。

测什么：
1. 正常情况下三者返回值是否一致
2. leader 切换瞬间，stale 是否会读到旧值
3. stale 读到底会旧多久（量化）

用法：先起三节点集群，再跑本脚本。
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

NODES = {
    'node1': 8500,
    'node2': 8510,
    'node3': 8520,
}
BASE = 'http://127.0.0.1:8500'
KEY = 'demo/counter'


def call(method, path, body=None, params=None, timeout=10):
    url = BASE + path
    if params:
        url += '?' + params
    data = body.encode('utf-8') if isinstance(body, str) else body
    headers = {'Content-Type': 'application/json'} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            txt = r.read().decode('utf-8')
            return r.status, txt, r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8').strip(), e.headers


def kv_put(val):
    return call('PUT', '/v1/kv/' + KEY, val)


def kv_read(mode):
    """mode: default / consistent / stale"""
    if mode == 'default':
        params = None
    else:
        params = mode
    st, body, headers = call('GET', '/v1/kv/' + KEY, params=params)
    if st == 200:
        arr = json.loads(body)
        v = arr[0]['Value']
        import base64
        return st, base64.b64decode(v).decode('utf-8'), arr[0].get('ModifyIndex')
    return st, body, None


def leader():
    st, body, _ = call('GET', '/v1/status/leader')
    return json.loads(body).strip('"') if st == 200 else f'ERR{st}'


print('=' * 66)
print('实战篇 A：三种读模式实测')
print('=' * 66)
print(f'当前 leader: {leader()}')
print(f'peers      : {call("GET", "/v1/status/peers")[1]}')

print()
print('=== 验证 1：正常情况下三者是否一致 ===')
kv_put('v0')
time.sleep(0.5)
for mode in ['default', 'consistent', 'stale']:
    st, val, idx = kv_read(mode)
    print(f'  {mode:12s} -> {st} value={val} modify_index={idx}')

print()
print('=== 验证 2：写入后立即用三种模式读（无延迟）===')
for i in range(1, 4):
    kv_put(f'v{i}')
    row = []
    for mode in ['default', 'consistent', 'stale']:
        st, val, idx = kv_read(mode)
        row.append(f'{mode}={val}')
    print(f'  写入 v{i} 后立刻读: ' + '  '.join(row))

print()
print('=== 验证 3：stale 读的延迟有多大（连续写入+立即 stale 读）===')
print('  （每次写入后不等，立即用 stale 读，看落后几个版本）')
lag_count = 0
for i in range(10, 20):
    kv_put(f'v{i}')
    _, val_s, _ = kv_read('stale')
    _, val_c, _ = kv_read('consistent')
    flag = '  ← stale 落后' if val_s != val_c else ''
    if val_s != val_c:
        lag_count += 1
    print(f'  写 v{i}: stale={val_s} consistent={val_c}{flag}')
print(f'  10 次里 stale 与 consistent 不一致 {lag_count} 次')

print()
print('=== 验证 4：X-Consul-Index 在三种模式下是否不同 ===')
kv_put('v-final')
time.sleep(0.3)
for mode in ['default', 'consistent', 'stale']:
    st, body, headers = call('GET', '/v1/kv/' + KEY, params=(None if mode == 'default' else mode))
    print(f'  {mode:12s} X-Consul-Index={headers.get("X-Consul-Index")} '
          f'X-Consul-KnownLeader={headers.get("X-Consul-KnownLeader")} '
          f'X-Consul-LastContact={headers.get("X-Consul-LastContact")}')

print()
print('=== 验证 5：三种模式的响应头差异（关键）===')
print('  LastContact 是 stale 读的核心指标：表示"这份数据落后 leader 多久"')
print('  单位毫秒，0 表示数据就是 leader 上的最新值')
for mode in ['default', 'consistent', 'stale']:
    samples = []
    for _ in range(3):
        st, body, headers = call('GET', '/v1/kv/' + KEY, params=(None if mode == 'default' else mode))
        samples.append(headers.get('X-Consul-LastContact', 'n/a'))
    print(f'  {mode:12s} LastContact 三次采样: {samples}')
