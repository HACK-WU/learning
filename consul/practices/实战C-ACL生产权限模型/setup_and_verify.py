"""实战篇 C 一键复现脚本：建策略 → 建 token → 跑权限矩阵。

前置：已启动带 ACL 的 agent
    consul agent -dev -config-file=acl-lab.hcl

用法：
    # 1) 引导管理 token（每个集群只能做一次）
    curl -X PUT http://127.0.0.1:8500/v1/acl/bootstrap

    # 2) 跑本脚本
    set MGMT_TOKEN=<上一步的 SecretID>
    python setup_and_verify.py
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

BASE = 'http://127.0.0.1:8500'
HERE = os.path.dirname(os.path.abspath(__file__))
POL_DIR = os.path.join(HERE, 'policies')
MGMT = os.environ.get('MGMT_TOKEN', '')

if not MGMT:
    print('错误：请先设置环境变量 MGMT_TOKEN（acl bootstrap 得到的 SecretID）')
    sys.exit(1)


def call(method, path, body=None, token=None):
    data = None
    headers = {}
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    if token:
        headers['X-Consul-Token'] = token
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode('utf-8')
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8').strip()


def upsert_policy(name, rules):
    """按名字幂等写入策略：已存在则更新，不存在则创建。"""
    st, body = call('PUT', '/v1/acl/policy', {'Name': name, 'Rules': rules}, MGMT)
    if st == 200:
        return json.loads(body)['ID']
    st0, r0 = call('GET', '/v1/acl/policies', None, MGMT)
    for p in json.loads(r0):
        if p['Name'] == name:
            call('PUT', '/v1/acl/policy/' + p['ID'], {'Name': name, 'Rules': rules}, MGMT)
            return p['ID']
    raise RuntimeError(f'写入策略失败 {st}: {body[:200]}')


def mk_token(desc, policy_id):
    st, body = call('PUT', '/v1/acl/token', {
        'Description': desc,
        'Policies': [{'ID': policy_id}],
        'Local': True,
    }, MGMT)
    if st != 200:
        raise RuntimeError(f'创建 token 失败 {st}: {body[:200]}')
    return json.loads(body)['SecretID']


# ---------------------------------------------------------------- 建策略
print('=' * 70)
print('步骤 1：写入三条策略')
print('=' * 70)
ids = {}
for name in ['pol-team-web', 'pol-team-api', 'pol-ops-readonly']:
    with open(os.path.join(POL_DIR, name + '.hcl'), encoding='utf-8') as f:
        rules = f.read()
    ids[name] = upsert_policy(name, rules)
    print(f'  {name:20s} -> {ids[name]}')

# ---------------------------------------------------------------- 建 token
print()
print('=' * 70)
print('步骤 2：为三个角色创建 token')
print('=' * 70)
tokens = {}
for role, pol in [('web', 'pol-team-web'), ('api', 'pol-team-api'), ('ops', 'pol-ops-readonly')]:
    tokens[role] = mk_token(f'{role} 团队 token', ids[pol])
    print(f'  {role:4s} -> {tokens[role]}')

WEB, API, OPS = tokens['web'], tokens['api'], tokens['ops']


def kv_put(k, v, t):
    return call('PUT', '/v1/kv/' + k, v.encode('utf-8'), t)


def kv_get(k, t):
    return call('GET', '/v1/kv/' + k, None, t)


def get(path, t):
    return call('GET', path, None, t)


def reg(name, sid, t):
    return call('PUT', '/v1/agent/service/register', {'Name': name, 'ID': sid, 'Port': 8080}, t)


# ---------------------------------------------------------------- 权限矩阵
print()
print('=' * 70)
print('步骤 3：权限矩阵（每项真发一次请求，记录 HTTP 码）')
print('=' * 70)

cases = [
    ('web 写 web/db_host（自己）', lambda: kv_put('web/db_host', '10.0.0.1', WEB)),
    ('web 写 api/db_host（别人）', lambda: kv_put('api/db_host', 'hacked', WEB)),
    ('api 写 api/db_host（自己）', lambda: kv_put('api/db_host', '10.0.0.2', API)),
    ('api 写 web/db_host（别人）', lambda: kv_put('web/db_host', 'hacked', API)),
    ('web 读 api/db_host（越权读）', lambda: kv_get('api/db_host', WEB)),
    ('web 递归读 web/（自己）', lambda: get('/v1/kv/web/?recurse=true', WEB)),
    ('web 递归读 api/（别人）', lambda: get('/v1/kv/api/?recurse=true', WEB)),
    ('ops 读 web/db_host（值班读）', lambda: kv_get('web/db_host', OPS)),
    ('ops 写 web/db_host（值班不该能改）', lambda: kv_put('web/db_host', 'ops-change', OPS)),
    ('web 列 keys', lambda: get('/v1/kv/?keys=true', WEB)),
    ('ops 列 keys', lambda: get('/v1/kv/?keys=true', OPS)),
    ('匿名列 keys', lambda: get('/v1/kv/?keys=true', None)),
    ('匿名列服务目录', lambda: get('/v1/catalog/services', None)),
    ('匿名查健康实例 web', lambda: get('/v1/health/service/web', None)),
    ('匿名注册服务', lambda: reg('rogue', 'rogue-1', None)),
    ('web 注册 web-1（自己）', lambda: reg('web', 'web-1', WEB)),
    ('web 注册 api 服务（顶别人的名）', lambda: reg('api', 'api-fake', WEB)),
    ('ops 读 raft 配置（operator=read）', lambda: get('/v1/operator/raft/configuration', OPS)),
    ('web 读 raft 配置', lambda: get('/v1/operator/raft/configuration', WEB)),
    ('ops 列 token（要 acl=read）', lambda: get('/v1/acl/tokens', OPS)),
]

for desc, fn in cases:
    st, body = fn()
    short = body.replace('\n', ' ')
    if len(short) > 72:
        short = short[:72] + '...'
    print(f'  [{st}] {desc}')
    if st not in (200,):
        print(f'        {short}')

print()
print('=' * 70)
print('三个值得注意的格子（详见 README 4.3 / 4.4 节）')
print('=' * 70)
print('  1. 递归读越权 -> 404（不是 403），客户端会误判为"配置不存在"')
print('  2. 匿名列目录/keys -> 200 空结果，看起来像"没数据"实为"没权限"')
print('  3. ops 读 raft 配置 -> 200，前提是 operator 写成 operator = "read"')
