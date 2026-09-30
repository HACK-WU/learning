"""课 9 交付前核验：链接可达性 + 内容自检"""
import os
import re
import subprocess

BASE = "/mnt/d/projects/learning/k8s/子教程/Python客户端专项"
DOC = os.path.join(BASE, "lessons", "lesson-09-异步客户端与并发.md")

with open(DOC, encoding="utf-8") as f:
    content = f.read()

print("=" * 70)
print("1. 本地链接核验")
print("=" * 70)
# 形如 [xxx](相对路径.md)
local_links = re.findall(r"\[([^\]]+)\]\((?!https?://)([^)]+\.md)(?:#[^)]*)?\)", content)
print(f"共 {len(local_links)} 条本地链接：")
ok = bad = 0
for name, link in local_links:
    target = os.path.normpath(os.path.join(os.path.dirname(DOC), link))
    exists = os.path.exists(target)
    status = "OK  " if exists else "MISS"
    ok += exists
    bad += (not exists)
    print(f"  [{status}] {link}")
    if not exists:
        print(f"          -> 解析为 {target}")
print(f"\n  存在 {ok} / 缺失 {bad}")

print()
print("=" * 70)
print("2. 外部链接核验")
print("=" * 70)
ext = re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", content)
print(f"共 {len(ext)} 条外链")
for name, url in ext:
    r = subprocess.run(["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
                        "-L", "--max-time", "15", url],
                       capture_output=True, text=True)
    code = r.stdout.strip()
    flag = "OK" if code == "200" else f"!! {code}"
    print(f"  [{flag}] {url}")

print()
print("=" * 70)
print("3. 敏感信息扫描")
print("=" * 70)
patterns = {
    "Bearer token": r"Bearer\s+[A-Za-z0-9_\-\.]{20,}",
    "私钥": r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "密码": r"password\s*[:=]\s*\S+",
}
hits = 0
for label, pat in patterns.items():
    m = re.findall(pat, content)
    if m:
        print(f"  !! {label}: {len(m)} 处 -> {m[:2]}")
        hits += len(m)
    else:
        print(f"  OK {label}: 0")
print(f"  合计命中: {hits}")

print()
print("=" * 70)
print("4. 结构自检")
print("=" * 70)
print(f"  总行数: {len(content.splitlines())}")
print(f"  总字符: {len(content)}")
for kw in ("小测", "速览", "课程导航", "评审结论", "前置"):
    print(f"  含「{kw}」: {'是' if kw in content else '否 ← 缺失!'}")

print()
print("=" * 70)
print("5. 测试命名空间残留检查")
print("=" * 70)
r = subprocess.run(["kubectl", "get", "ns", "--no-headers"],
                   capture_output=True, text=True)
for line in r.stdout.splitlines():
    ns = line.split()[0]
    if "lesson09" in ns:
        print(f"  !! 残留: {ns}")
        hits += 1
else:
    print("  OK 无 lesson09 残留")
print("\n当前 ns 列表：")
print("  " + "\n  ".join(l.split()[0] for l in r.stdout.splitlines()))
