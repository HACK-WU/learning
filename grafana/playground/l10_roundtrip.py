#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 实验 5：UI 导出 vs 源文件——Grafana 回填了多少字段"""
import json, urllib.request, base64, os

AUTH = base64.b64encode(b'admin:admin').decode()


def get(base, path):
    op = urllib.request.build_opener()
    op.addheaders = [('Authorization', 'Basic ' + AUTH)]
    with op.open(base + path, timeout=30) as r:
        return json.loads(r.read().decode())


SRC = '/mnt/d/projects/learning/grafana/playground/provisioning/dashboards-json/prov-dash.json'
src = json.load(open(SRC))
live = get('http://localhost:3002', '/api/dashboards/uid/prov-dash-001')['dashboard']

print('=' * 70)
print('实验 5：源文件 vs 库中对象，字段数变化')
print('=' * 70)
ks, kl = set(src.keys()), set(live.keys())
print('源文件字段数  =', len(ks))
print('库中对象字段数=', len(kl))
print()
print('库中新增（Grafana 回填）:', sorted(kl - ks))
print('库中缺失（被丢弃）    :', sorted(ks - kl))
print()

print('--- 逐字段是否一致（源文件有的字段） ---')
for k in sorted(ks):
    a, b = src.get(k), live.get(k)
    same = json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)
    flag = 'OK ' if same else 'DIFF'
    if not same:
        print('  %s %-14s src=%r' % (flag, k, a))
        print('       %-14s lib=%r' % ('', b))
print('  (未列出的字段均一致)')
print()

print('--- panel 级：源文件 vs 库中 ---')
ps, pl = src['panels'][0], live['panels'][0]
print('src panel keys =', len(ps), ' lib panel keys =', len(pl))
print('lib 新增:', sorted(set(pl) - set(ps)))
print('lib 缺失:', sorted(set(ps) - set(pl)))
print('src panel.id  =', ps.get('id'))
print('lib panel.id  =', pl.get('id'))
