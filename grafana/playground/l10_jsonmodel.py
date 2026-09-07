#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 实验 3：JSON Model 结构与可 diff 化"""
import json, urllib.request, base64, difflib, re

BASE = 'http://localhost:3002'
AUTH = base64.b64encode(b'admin:admin').decode()
opener = urllib.request.build_opener()
opener.addheaders = [('Authorization', 'Basic ' + AUTH)]


def get(path):
    with opener.open(BASE + path, timeout=30) as r:
        return json.loads(r.read().decode())


print('=' * 70)
print('实验 3-1：dashboard JSON 的顶层字段')
print('=' * 70)
d = get('/api/dashboards/uid/prov-dash-001')['dashboard']
top = sorted(d.keys())
print('顶层字段 (%d 个):' % len(top))
for k in top:
    v = d[k]
    t = type(v).__name__
    n = len(v) if isinstance(v, (list, dict, str)) else ''
    print('  %-16s %-8s %s' % (k, t, n))

print()
print('=' * 70)
print('实验 3-2：哪些字段是"噪音"（每次保存都变）')
print('=' * 70)
NOISE_HINT = ['version', 'id', 'updated', 'created', 'updatedBy', 'createdBy', 'uid']
for k in top:
    if k in NOISE_HINT:
        print('  噪音候选: %-14s = %r' % (k, d.get(k)))

print()
print('=' * 70)
print('实验 3-3：panel 结构')
print('=' * 70)
p = d['panels'][0]
print('panel 字段 (%d 个):' % len(p))
for k in sorted(p.keys()):
    print('  %-16s %s' % (k, type(p[k]).__name__))

print()
print('=' * 70)
print('实验 3-4：templating (变量) 结构')
print('=' * 70)
print(json.dumps(d.get('templating'), ensure_ascii=False, indent=2)[:1200])
