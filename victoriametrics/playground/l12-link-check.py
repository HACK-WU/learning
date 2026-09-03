#!/usr/bin/env python3
# 课 12 交付检查：全仓 Markdown 链接可达性
import os, re, sys

ROOT = "/mnt/d/projects/learning/victoriametrics"
MDFILES = []
for dp, dn, fn in os.walk(ROOT):
    if any(x in dp for x in (".git", "node_modules", "playground/data")):
        continue
    for f in fn:
        if f.endswith(".md"):
            MDFILES.append(os.path.join(dp, f))

LINK = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
bad, total, byfile = [], 0, {}

for fp in sorted(MDFILES):
    try:
        src = open(fp, encoding="utf-8").read()
    except Exception:
        continue
    errs = []
    for m in LINK.finditer(src):
        text, target = m.group(1), m.group(2).strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        total += 1
        t = target.split("#")[0]
        if not t:
            continue
        resolved = os.path.normpath(os.path.join(os.path.dirname(fp), t))
        if not os.path.exists(resolved):
            line = src[:m.start()].count("\n") + 1
            errs.append((line, text, target, resolved))
    if errs:
        byfile[os.path.relpath(fp, ROOT)] = errs
        bad.extend([(os.path.relpath(fp, ROOT),) + e for e in errs])

print("=" * 70)
print("VictoriaMetrics 全仓链接可达性检查")
print("=" * 70)
print(f"扫描 Markdown 文件：{len(MDFILES)} 个")
print(f"检查本地链接：{total} 条")
print(f"失效链接：{len(bad)} 条")
print()

# 课 12 专项
print("[课 12 专项]")
L12 = "stages/5-生产落地/12-备份恢复迁移与选型决策.md"
l12p = os.path.join(ROOT, L12)
if os.path.exists(l12p):
    src = open(l12p, encoding="utf-8").read()
    l12err = [b for b in bad if b[0] == L12]
    print(f"  文件存在：✅  ({len(src)} 字符 / {len(src.splitlines())} 行)")
    print(f"  自身失效链接：{len(l12err)} 条")
    for _, ln, text, tgt, res in l12err:
        print(f"     L{ln}: [{text}] -> {tgt}")
    # 反向：谁引用了课 12
    refs = []
    for fp in MDFILES:
        if fp == l12p:
            continue
        s = open(fp, encoding="utf-8").read()
        if "12-备份恢复迁移与选型决策" in s:
            refs.append(os.path.relpath(fp, ROOT))
    print(f"  被引用：{len(refs)} 个文件")
    for r in sorted(refs):
        print(f"     - {r}")
    # 课 11 是否指到课 12
    l11 = os.path.join(ROOT, "stages/5-生产落地/11-vmagent与vmalert.md")
    if os.path.exists(l11):
        s = open(l11, encoding="utf-8").read()
        has = "12-备份恢复迁移与选型决策.md" in s
        print(f"  课 11 已指向课 12：{'✅' if has else '❌ 未更新'}")
else:
    print("  ❌ 课 12 文件不存在")

print()
if bad:
    print("=" * 70)
    print("失效链接明细")
    print("=" * 70)
    for f, ln, text, tgt, res in bad:
        print(f"  {f}:L{ln}")
        print(f"     文本：{text}")
        print(f"     链接：{tgt}")
        print(f"     解析：{res}")
else:
    print("✅ 全部本地链接可达，0 处失效")

print()
print("=" * 70)
print(f"检查文件数 {len(MDFILES)} / 链接数 {total} / 失效 {len(bad)}")
print("=" * 70)
