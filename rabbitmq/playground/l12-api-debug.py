#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断：为什么 Python 调 Management API 返回 None"""
import subprocess

UI = 15681
Q = 'l12.min.q'


def show(label, url):
    r = subprocess.run(['curl', '-s', '-w', '\\nHTTP=%{http_code}',
                        '-u', 'learn:learn123', url],
                       capture_output=True, text=True, timeout=20)
    out = (r.stdout or '').strip()
    print("\n--- %s ---" % label)
    print("URL: %s" % url)
    print("返回: %s" % out[:200])


def main():
    print("=" * 66)
    print("诊断 Management API 路径")
    print("=" * 66)

    show("写法 A：%%2F（错误写法）",
         'http://localhost:%d/api/queues/%%2F/%s' % (UI, Q))
    show("写法 B：%2F",
         'http://localhost:%d/api/queues/%%2F/%s' % (UI, Q))
    show("写法 C：直接百分号（Python 里需写成 %%2F 才输出 %2F）",
         'http://localhost:%d/api/queues/' % UI + '%2F' + '/' + Q)
    show("写法 D：用 /api/queues 列表过滤",
         'http://localhost:%d/api/queues' % UI)

    # 用 python 自己确认
    url = 'http://localhost:%d/api/queues/' % UI + '%2F' + Q
    print("\n最终确认 URL = %s" % url)
    r = subprocess.run(['curl', '-s', '-u', 'learn:learn123', url],
                       capture_output=True, text=True, timeout=20)
    print("返回前 150 字符: %s" % (r.stdout or '')[:150])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
