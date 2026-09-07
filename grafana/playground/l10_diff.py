#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 实验 4：可 diff 化——同一份 dashboard 在两个实例上差多少"""
import json, urllib.request, base64, difflib

AUTH = base64.b64encode(b'admin:admin').decode()


def get(base, path):
    op = urllib.request.build_opener()
    op.addheaders = [('Authorization', 'Basic ' + AUTH)]
    with op.open(base + path, timeout=30) as r:
        return json.loads(r.read().decode())


A = 'http://localhost:3002'  # grafana-prov  (restarted -> file re-asserted)
B = 'http://localhost:3003'  # grafana-prov2 (same after restart)

da = get(A, '/api/dashboards/uid/prov-dash-001')['dashboard']
db = get(B, '/api/dashboards/uid/prov-dash-001')['dashboard']

print('=' * 70)
print('实验 4：同一份文件 provision 到两个实例，JSON 是否逐字节相同？')
print('=' * 70)
print('A(3002) version=%s id=%s' % (da.get('version'), da.get('id')))
print('B(3003) version=%s id=%s' % (db.get('version'), db.get('id')))
print()

STRIP = ['id', 'version']
sa = {k: v for k, v in da.items() if k not in STRIP}
sb = {k: v for k, v in db.items() if k not in STRIP}

print('--- 1) 原始 JSON 是否相同 ---')
print('   identical (incl id/version):', json.dumps(da, sort_keys=True) == json.dumps(db, sort_keys=True))
print('   identical (strip id/version):', json.dumps(sa, sort_keys=True) == json.dumps(sb, sort_keys=True))
print()

print('--- 2) 逐字段比对（只看顶层） ---')
for k in sorted(set(da.keys()) | set(db.keys())):
    va, vb = da.get(k, '<MISSING>'), db.get(k, '<MISSING>')
    same = json.dumps(va, sort_keys=True) == json.dumps(vb, sort_keys=True)
    if not same:
        print('   DIFF %-16s A=%r' % (k, va))
        print('        %-16s B=%r' % ('', vb))
print()

print('--- 3) 真实 diff（strip id/version 后） ---')
la = json.dumps(sa, indent=2, sort_keys=True, ensure_ascii=False).splitlines()
lb = json.dumps(sb, indent=2, sort_keys=True, ensure_ascii=False).splitlines()
diff = [x for x in difflib.unified_diff(la, lb, 'A-3002', 'B-3003', lineterm='', n=1)]
print('   diff lines:', len(diff))
for x in diff[:40]:
    print('   ' + x)
