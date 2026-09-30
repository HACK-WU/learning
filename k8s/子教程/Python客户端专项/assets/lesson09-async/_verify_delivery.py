"""课 9 番外 交付前核验

四项：
1. 讲义中本地链接是否可达（相对路径）
2. 是否有外链（本课应 0 条）
3. 是否含敏感信息（token / 私钥 / 密码）
4. 测试 ns 是否残留
5. 全部脚本 py_compile
"""
import os
import re
import subprocess
import sys

LESSON = "lessons/lesson-09-async-异步三个未实测项.md"
ASSETS = "assets/lesson09-async"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
# 本文件在 assets/lesson09-async/ 下，向上 2 级是子教程根
SUBROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def check_links():
    print("=== 1. 本地链接可达性 ===")
    path = os.path.join(SUBROOT, LESSON)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    # Markdown 链接
    links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", text)
    local = [(t, u) for t, u in links if not u.startswith(("http://", "https://"))]
    remote = [(t, u) for t, u in links if u.startswith(("http://", "https://"))]
    miss = []
    for t, u in local:
        clean = u.split("#")[0]
        if not clean:
            continue
        p = os.path.normpath(os.path.join(SUBROOT, "lessons", clean))
        if not os.path.exists(p):
            miss.append((t, u, p))
    print(f"  本地链接 {len(local)} 条, 缺失 {len(miss)} 条")
    for t, u, p in miss:
        print(f"    MISS: [{t}]({u}) -> {p}")
    print(f"  外链 {len(remote)} 条")
    for t, u in remote:
        print(f"    {u}")


def check_sensitive():
    print()
    print("=== 2. 敏感信息扫描 ===")
    path = os.path.join(SUBROOT, LESSON)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    pats = {
        "Bearer token": r"Bearer\s+[A-Za-z0-9._-]{20,}",
        "私钥": r"BEGIN (RSA |EC )?PRIVATE KEY",
        "密码": r"(password|passwd)\s*[=:]\s*\S{6,}",
        "aws key": r"AKIA[0-9A-Z]{16}",
    }
    hits = 0
    for name, p in pats.items():
        m = re.findall(p, text, re.IGNORECASE)
        if m:
            print(f"  命中 {name}: {len(m)} 处")
            hits += len(m)
    print(f"  合计 {hits} 处")


def check_ns():
    print()
    print("=== 3. 测试 ns 残留 ===")
    try:
        out = subprocess.run(
            ["kubectl", "--context", "kind-k8s-c1", "get", "ns", "-o", "name"],
            capture_output=True, text=True, timeout=30)
        names = [l.strip() for l in out.stdout.splitlines()
                 if "lesson09" in l or "lesson09-async" in l]
        if names:
            print("  残留:", names)
        else:
            print("  lesson09 相关 ns 残留 0")
    except Exception as e:
        print("  检查失败:", type(e).__name__, str(e)[:100])


def check_compile():
    print()
    print("=== 4. 脚本编译检查 ===")
    d = os.path.join(SUBROOT, ASSETS)
    files = sorted(f for f in os.listdir(d) if f.endswith(".py"))
    bad = []
    for f in files:
        r = subprocess.run(
            [sys.executable, "-m", "py_compile", os.path.join(d, f)],
            capture_output=True, text=True)
        if r.returncode != 0:
            bad.append((f, r.stderr.strip()[:120]))
    print(f"  脚本 {len(files)} 个, 编译失败 {len(bad)} 个")
    for f, e in bad:
        print(f"    FAIL {f}: {e}")


def check_lesson_stats():
    print()
    print("=== 5. 讲义规模 ===")
    path = os.path.join(SUBROOT, LESSON)
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    print(f"  行数: {len(lines)}")
    heads = [l.strip() for l in lines if l.startswith("## ")]
    print("  二级标题:", heads)


if __name__ == "__main__":
    check_links()
    check_sensitive()
    check_ns()
    check_compile()
    check_lesson_stats()
