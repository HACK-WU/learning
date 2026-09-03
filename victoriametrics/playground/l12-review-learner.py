#!/usr/bin/env python3
# 课 12 评审 Agent B：学习者视角（learner）
import re, sys

P = "/mnt/d/projects/learning/victoriametrics/stages/5-生产落地/12-备份恢复迁移与选型决策.md"
try:
    src = open(P, encoding="utf-8").read()
except Exception as e:
    print("READ FAIL:", e); sys.exit(1)

lines = src.split("\n")
print("=" * 70)
print("课 12 评审 · Agent B（学习者视角 / learner）")
print("判据：零上下文学员能否照着做、能否看懂、会不会被误导")
print("=" * 70)

issues = []

# 1. 命令可复制性
print("\n[1] 命令块可复制性")
blocks = re.findall(r"```bash\n(.*?)```", src, re.S)
print(f"   bash 代码块：{len(blocks)} 个")
bad = 0
for b in blocks:
    for l in b.split("\n"):
        s = l.strip()
        if s.startswith("#") or not s:
            continue
        if "$(" in s and "printf" not in s and "date" not in s:
            print(f"   ⚠️ 含 $() 需转义：{s[:70]}")
            bad += 1
print(f"   需转义行：{bad}")

# 2. 占位符检查
print("\n[2] 占位符是否可直接使用")
ph = ["<bucket>", "<path>", "YOUR_", "xxx", "TODO", "FIXME"]
for p in ph:
    c = src.count(p)
    if c:
        print(f"   「{p}」出现 {c} 次")
        issues.append(("P2", f"占位符「{p}」未替换为可执行值"))

# 3. 快照名等需替换的动态值
print("\n[3] 动态值（快照名等）是否有替换说明")
snap_refs = src.count("20260902121059-18D17DD6F49B1C97")
print(f"   硬编码快照名出现：{snap_refs} 次")
if snap_refs > 0:
    has_hint = "返回快照名" in src or "snapshot/create" in src
    print(f"   有获取方式说明：{'✅' if has_hint else '❌'}")
    if not has_hint:
        issues.append(("P1", "硬编码快照名但无获取说明"))

# 4. 前置依赖说明
print("\n[4] 前置依赖说明")
deps = ["docker volume create", "docker pull", "镜像"]
for d in deps:
    print(f"   「{d}」：{'✅ 提及' if d in src else '—'}")

# 5. 环境差异提示
print("\n[5] 环境差异提示（本环境特有坑）")
env_items = {
    "9p 挂载": "9p" in src,
    "fallocate 限制": "fallocate" in src,
    "WSL/Windows": "WSL" in src or "Windows" in src,
    "命名卷替代方案": "docker volume create" in src,
}
for k, v in env_items.items():
    print(f"   {k}：{'✅' if v else '❌ 未提及'}")
    if not v and k in ("9p 挂载", "fallocate 限制"):
        issues.append(("P1", f"环境坑「{k}」未说明，学员会踩"))

# 6. 结论与数据对应
print("\n[6] 关键结论是否有数据支撑")
claims = [
    ("硬链接", "links=3"),
    ("快照零成本", "184 KB"),
    ("增量备份", "136,362"),
    ("迁移规模", "10,580,035"),
    ("RTO", "2,548 ms"),
    ("删除不释放空间", "2,348 KB"),
    ("时间戳陷阱", "1970-01-22"),
]
for name, ev in claims:
    ok = ev in src
    print(f"   {name}（证据 {ev}）：{'✅' if ok else '❌ 缺证据'}")
    if not ok:
        issues.append(("P1", f"结论「{name}」缺少实测证据"))

# 7. 误导性检查
print("\n[7] 误导性检查")
# 删除 API 是否有足够警告
if "delete_series" in src:
    idx = src.find("delete_series")
    ctx = src[max(0, idx - 1500):idx + 2500]
    warn = ("⚠️" in ctx) or ("不可逆" in ctx) or ("高危" in ctx)
    print(f"   删除 API 附近有警告：{'✅' if warn else '❌ 缺少警告（易误导学员误用）'}")
    if not warn:
        issues.append(("P0", "删除 API 无安全警告，学员可能误操作"))

# 8. 常见误区是否有正解
print("\n[8] 误区是否给出正解")
mm = re.search(r"常见误区汇总\n\n(.*?)\n\n### 决策清单", src, re.S)
if mm:
    items = [l for l in mm.group(1).split("\n") if l.strip() and l.strip()[0].isdigit()]
    print(f"   误区条目：{len(items)}")
    nofix = [i for i in items if len(i) < 25]
    print(f"   疑似无正解的短条目：{len(nofix)}")
    for i in nofix:
        print(f"      ⚠️ {i}")

# 9. 前后课程衔接
print("\n[9] 前后课程衔接")
nav = src.count("课 11") + src.count("课 5") + src.count("课 6")
print(f"   前后课引用：{nav} 处")
conn = "与前后课程的连接" in src
print(f"   有连接表：{'✅' if conn else '❌'}")
if not conn:
    issues.append(("P2", "缺少前后课程连接表"))

# 10. 脚本引用与文件存在性
print("\n[10] 实验脚本引用")
scripts = set(re.findall(r"`(l12-[\w\-]+\.sh)`", src))
print(f"   引用脚本：{len(scripts)} 个")
import os
missing = []
for s in sorted(scripts):
    fp = "/mnt/d/projects/learning/victoriametrics/playground/" + s
    ok = os.path.exists(fp)
    if not ok:
        missing.append(s)
    print(f"   {s}：{'✅' if ok else '❌ 不存在'}")
if missing:
    issues.append(("P0", f"引用了不存在的脚本：{missing}"))

# 11. 安全提示覆盖
print("\n[11] 危险操作安全提示覆盖")
danger_lines = [(i + 1, l) for i, l in enumerate(lines) if "rm -rf" in l or "docker rm -f" in l]
for ln, l in danger_lines:
    near = "\n".join(lines[max(0, ln - 4):ln + 2])
    ok = ("⚠️" in near) or ("安全提示" in near) or ("#" in l.strip()[:2])
    print(f"   L{ln}: {'✅ 有提示' if ok else '❌ 无提示'} | {l.strip()[:60]}")
    if not ok:
        issues.append(("P1", f"L{ln} 危险操作无安全提示"))

print("\n" + "=" * 70)
print("问题汇总")
print("=" * 70)
if not issues:
    print("   无问题")
else:
    for lv, d in issues:
        print(f"   [{lv}] {d}")
p0 = [i for i in issues if i[0] == "P0"]
p1 = [i for i in issues if i[0] == "P1"]
p2 = [i for i in issues if i[0] == "P2"]
print(f"\n   P0={len(p0)}  P1={len(p1)}  P2={len(p2)}")
