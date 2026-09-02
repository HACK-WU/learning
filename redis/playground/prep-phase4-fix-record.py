#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复评审清单：上一轮追加的记录行被拼到了前一行末尾，此处拆开并统一换行符。"""
from pathlib import Path

P = Path("/mnt/d/projects/learning/redis/00-评审清单.md")
MARKER = "转 Apache 2.0） || 2026-09-02 | 卫生检查与环境清理"

raw = P.read_bytes()
crlf = b"\r\n" in raw
text = raw.decode("utf-8")

if MARKER not in text:
    print("未发现拼接问题，跳过")
else:
    nl = "\r\n" if crlf else "\n"
    text = text.replace(MARKER, "转 Apache 2.0） |" + nl + "| 2026-09-02 | 卫生检查与环境清理")
    P.write_bytes(text.encode("utf-8"))
    print(f"已拆分拼接行（换行符风格: {'CRLF' if crlf else 'LF'}）")

# 复核
lines = P.read_text(encoding="utf-8").splitlines()
hits = [i + 1 for i, ln in enumerate(lines) if "卫生检查与环境清理" in ln and ln.startswith("|")]
print(f"卫生检查记录所在行: {hits}")
for i in hits:
    print(f"  第 {i} 行开头: {lines[i-1][:60]}")
print(f"文件末行是否为空行结尾: {P.read_bytes().endswith(b'\\n') or P.read_bytes().endswith(b'\\r\\n')}")
