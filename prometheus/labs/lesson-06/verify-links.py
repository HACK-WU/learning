"""课 6 交付后的链接可达性校验（课 5 起的强制项）。

课 5 时该校验曾一次性抓出六个阶段 overview 的返回链接层级错误（18 处）。
本课校验范围：
1. 课 6 讲义内所有本地链接
2. 档案 / 目录 / 总览 / 阶段 overview 中新增或修改的链接
3. 各阶段 overview 的返回链接层级
"""
import os
import re
import sys

ROOT = "/mnt/d/projects/learning/prometheus"

TARGETS = [
    f"{ROOT}/stages/2-规则与告警/lessons/lesson-06-查询引擎与查询成本.md",
    f"{ROOT}/00-学习档案.md",
    f"{ROOT}/00-评审清单.md",
    f"{ROOT}/01-学习路径总览.md",
    f"{ROOT}/02-课程目录.md",
    f"{ROOT}/stages/2-规则与告警/overview.md",
]

LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

bad = []
total = 0

print("=" * 66)
print("链接可达性校验")
print("=" * 66)

for path in TARGETS:
    if not os.path.exists(path):
        print(f"  !! 文件不存在: {path}")
        bad.append((path, "文件不存在"))
        continue
    with open(path, encoding="utf-8") as f:
        text = f.read()

    base = os.path.dirname(path)
    name = os.path.basename(path)
    links = LINK_RE.findall(text)

    # 只取本地链接（排除 http/https 与纯锚点）
    local = [(t, u) for t, u in links
             if not u.startswith(("http://", "https://", "#", "mailto:"))]

    print(f"\n{name}: 本地链接 {len(local)} 个")
    for title, url in local:
        total += 1
        clean = url.split("#")[0].strip()
        if not clean:
            continue
        full = os.path.normpath(os.path.join(base, clean))
        if os.path.exists(full):
            print(f"  OK   {title}  ->  {clean}")
        else:
            print(f"  ✗✗   {title}  ->  {clean}   (解析为 {full})")
            bad.append((name, f"{title} -> {clean}"))

print()
print("=" * 66)
print(f"合计本地链接 {total} 个，失效 {len(bad)} 个")
if bad:
    print()
    for f, msg in bad:
        print(f"  [{f}] {msg}")
print("=" * 66)

sys.exit(1 if bad else 0)
