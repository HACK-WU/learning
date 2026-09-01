#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取 RabbitMQ 官方文档，提取 quorum 队列优先级相关段落。"""
import html
import re
import subprocess
import sys

URL = 'https://www.rabbitmq.com/docs/quorum-queues'


def fetch():
    r = subprocess.run(['curl', '-sL', URL], capture_output=True, timeout=90)
    return r.stdout.decode('utf-8', errors='ignore')


def strip_html(raw):
    t = re.sub(r'<script.*?</script>', ' ', raw, flags=re.S | re.I)
    t = re.sub(r'<style.*?</style>', ' ', t, flags=re.S | re.I)
    t = re.sub(r'<[^>]+>', ' ', t)
    t = html.unescape(t)
    return re.sub(r'\s+', ' ', t)


def main():
    raw = fetch()
    if len(raw) < 500:
        print("抓取失败，长度 %d" % len(raw))
        return 1
    text = strip_html(raw)
    print("文档长度：%d 字符\n" % len(text))

    for kw in ['priorit', 'x-max-priority', 'delayed-retry', 'delayed_retry']:
        idxs = [m.start() for m in re.finditer(kw, text, re.I)]
        print("=" * 70)
        print("关键词 '%s' 命中 %d 处" % (kw, len(idxs)))
        print("=" * 70)
        for i in idxs[:3]:
            print("\n--- 上下文 ---")
            print(text[max(0, i - 700): i + 1200])
            print()
        if idxs:
            break
    return 0


if __name__ == '__main__':
    sys.exit(main())
