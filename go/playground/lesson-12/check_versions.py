#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""回查 $GOROOT/api/*.txt，给出每个符号最早出现的版本。不凭记忆。"""
import os
import re
import subprocess
import sys

GOROOT = subprocess.check_output(
    ["/usr/local/bin/go", "env", "GOROOT"], text=True
).strip()
API = os.path.join(GOROOT, "api")

# 版本排序键
def vkey(fn):
    m = re.match(r"^go(1(?:\.(\d+))?)\.txt$", fn)
    if not m:
        return (999, 999)
    return (1, int(m.group(2)) if m.group(2) else 0)

files = sorted(
    [f for f in os.listdir(API) if re.match(r"^go1(\.\d+)?\.txt$", f)],
    key=vkey,
)

# 读入
content = {}
for f in files:
    with open(os.path.join(API, f), encoding="utf-8", errors="replace") as fh:
        content[f] = fh.read()


def first_version(pattern):
    """pattern 是正则，匹配 api 行；返回最早的版本文件名"""
    rx = re.compile(pattern)
    for f in files:
        for line in content[f].split("\n"):
            if rx.search(line):
                return f.replace(".txt", ""), line.strip()
    return None, None


# 坑位记录（Go 课 12 踩过）：
#   ① api 文件里 **方法** 写作 `method (*DB) Foo(...)`，**不是** `func`。
#      早期版本正则只写 `func`，导致 4 个符号返回 "?! 未找到"，
#      被误读成 "该 API 不存在"。这里统一用 `(?:func|method)`。
#   ② `go1.1.txt` 有 5 万多行（比 go1.txt 的 3 万行还多），因为它**重新记录了所有常量的值**。
#      "在某文件里出现过" ≠ "在该版本新增"。判"引入版本"必须**从 go1.txt 起按序号找最早出现的那份**。
#   ③ 版本排序必须显式做数字排序（字典序会让 go1.10 < go1.2）。见 vkey()。
METHOD = r"(?:func|method)"

CHECKS = [
    # (标签, 正则)
    ("(*DB).SetMaxIdleConns", rf"pkg database/sql, {METHOD} \(\*DB\) SetMaxIdleConns\b"),
    ("(*DB).SetMaxOpenConns", rf"pkg database/sql, {METHOD} \(\*DB\) SetMaxOpenConns\b"),
    ("(*DB).Stats", rf"pkg database/sql, {METHOD} \(\*DB\) Stats\b"),
    ("(*DB).SetConnMaxLifetime", rf"pkg database/sql, {METHOD} \(\*DB\) SetConnMaxLifetime\b"),
    ("(*DB).QueryContext", rf"pkg database/sql, {METHOD} \(\*DB\) QueryContext\b"),
    ("(*DB).ExecContext", rf"pkg database/sql, {METHOD} \(\*DB\) ExecContext\b"),
    ("(*DB).QueryRowContext", rf"pkg database/sql, {METHOD} \(\*DB\) QueryRowContext\b"),
    ("(*DB).PingContext", rf"pkg database/sql, {METHOD} \(\*DB\) PingContext\b"),
    ("(*DB).BeginTx", rf"pkg database/sql, {METHOD} \(\*DB\) BeginTx\b"),
    ("(*DB).SetConnMaxIdleTime", rf"pkg database/sql, {METHOD} \(\*DB\) SetConnMaxIdleTime\b"),
    ("DefaultMaxIdleConnsPerHost", r"pkg net/http, const DefaultMaxIdleConnsPerHost\b"),
    ("Transport.MaxIdleConnsPerHost", r"pkg net/http, type Transport struct, MaxIdleConnsPerHost\b"),
    ("Client", r"pkg net/http, type Client struct"),
    ("Client.Timeout", r"pkg net/http, type Client struct, Timeout\b"),
    ("Transport.TLSHandshakeTimeout", r"pkg net/http, type Transport struct, TLSHandshakeTimeout\b"),
    ("Transport.MaxIdleConns", r"pkg net/http, type Transport struct, MaxIdleConns\b"),
    ("Transport.IdleConnTimeout", r"pkg net/http, type Transport struct, IdleConnTimeout\b"),
    ("(*Client).CloseIdleConnections", rf"pkg net/http, {METHOD} \(\*Client\) CloseIdleConnections\b"),
    ("Transport.ForceAttemptHTTP2", r"pkg net/http, type Transport struct, ForceAttemptHTTP2\b"),
    ("NewRequestWithContext", r"pkg net/http, func NewRequestWithContext\b"),
    ("time.Round", rf"pkg time, {METHOD} \(Time\) Round\b"),
    ("time.Truncate", rf"pkg time, {METHOD} \(Time\) Truncate\b"),
    ("time.ParseInLocation", r"pkg time, func ParseInLocation\b"),
    ("Timer.Reset", rf"pkg time, {METHOD} \(\*Timer\) Reset\b"),
    ("RFC3339", r"pkg time, const RFC3339\b"),
    ("time.Until", r"pkg time, func Until\b"),
    ("Ticker.Reset", rf"pkg time, {METHOD} \(\*Ticker\) Reset\b"),
    ("time.DateTime", r"pkg time, const DateTime\b"),
    ("time.DateOnly", r"pkg time, const DateOnly\b"),
    ("time.TimeOnly", r"pkg time, const TimeOnly\b"),
    ("Time.Compare", rf"pkg time, {METHOD} \(Time\) Compare\b"),
    ("time.AfterFunc", r"pkg time, func AfterFunc\b"),
    # 坑 ②：同名不同包 —— time.AfterFunc(1.0) vs context.AfterFunc(1.21)，必须分开查
    ("context.AfterFunc", r"pkg context, func AfterFunc\b"),
]

print(f"GOROOT = {GOROOT}")
print(f"api 文件 = {files[0]} .. {files[-1]}（{len(files)} 个）")
print()
print(f"{'符号':<34} {'最早版本':<10} api 行")
print("-" * 110)
for label, pat in CHECKS:
    v, raw = first_version(pat)
    print(f"{label:<34} {v or '?! 未找到':<10} {raw or ''}")

print()
print("=== Go 1.27 是否给 net/http 客户端 / time 加过 API ===")
for f in ["go1.27.txt"]:
    hits = [
        l for l in content[f].split("\n")
        if re.search(r"pkg (net/http|time),", l)
    ]
    print(f"{f}: net/http 或 time 的条目 {len(hits)} 条")
    for h in hits:
        print("   ", h)
