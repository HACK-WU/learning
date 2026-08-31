#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验课 7 的 SVG 文件是否为合法 XML"""
import os
import sys
import xml.dom.minidom

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
targets = [
    "stages/3-可靠性与投递语义/assets/lesson-07-persistence-deadletter.svg",
    "stages/3-可靠性与投递语义/assets/lesson-06-ack-confirm-prefetch.svg",
]

ok = True
for rel in targets:
    path = os.path.join(BASE, rel)
    if not os.path.exists(path):
        print(f"  ❌ 文件不存在: {rel}")
        ok = False
        continue
    try:
        xml.dom.minidom.parse(path)
        size = os.path.getsize(path)
        print(f"  ✅ XML 合法: {rel}  ({size:,} bytes)")
    except Exception as exc:  # noqa: BLE001
        print(f"  ❌ XML 解析失败: {rel} -> {exc}")
        ok = False

sys.exit(0 if ok else 1)
