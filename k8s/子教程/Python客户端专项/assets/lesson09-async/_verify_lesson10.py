"""课 10 交付前核验

1. 本地链接可达 / 外链数 / 敏感信息
2. 讲义中引用的数字与实测输出是否一致
3. 脚本 py_compile
4. 代码行规模
"""
import os
import re
import subprocess
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LESSON = os.path.join(SUBROOT, "lessons", "lesson-10-重试中间件工程化.md")
HERE = os.path.join(SUBROOT, "assets", "lesson09-async")


def check_links():
    print("=== 1. 链接与敏感 ===")
    with open(LESSON, encoding="utf-8") as f:
        text = f.read()
    links = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", text)
    local = [(t, u) for t, u in links if not u.startswith(("http://", "https://"))]
    remote = [u for _, u in links if u.startswith(("http://", "https://"))]
    miss = []
    for t, u in local:
        c = u.split("#")[0]
        if not c:
            continue
        # 讲义在 lessons/ 下，相对路径基准是 lessons/
        p = os.path.normpath(os.path.join(SUBROOT, "lessons", c))
        if not os.path.exists(p):
            miss.append((t, u))
    print(f"  本地 {len(local)} 条, 缺失 {len(miss)} 条")
    for t, u in miss:
        print(f"    MISS [{t}]({u})")
    print(f"  外链 {len(remote)} 条: {remote}")

    pats = {
        "token": r"Bearer\s+[A-Za-z0-9._-]{20,}",
        "私钥": r"BEGIN (RSA |EC )?PRIVATE KEY",
        "密码": r"(password|passwd)\s*[=:]\s*\S{6,}",
    }
    hits = sum(len(re.findall(p, text, re.I)) for p in pats.values())
    print(f"  敏感信息 {hits} 处")


def check_numbers():
    print()
    print("=== 2. 讲义数字 vs 实测 ===")
    with open(LESSON, encoding="utf-8") as f:
        text = f.read()

    # 重跑测试拿真值
    r = subprocess.run([sys.executable, "test_retry_middleware.py"],
                       cwd=HERE, capture_output=True, text=True, timeout=300)
    out = r.stdout
    m = re.search(r"通过\s+(\d+)\s*/\s*失败\s+(\d+)", out)
    if m:
        p, f = int(m.group(1)), int(m.group(2))
        claim = "48" in text
        print(f"  实测 通过 {p} / 失败 {f}")
        print(f"  讲义称 48 项: {'✓' if claim else '✗ 未提及'}")
        if f == 0 and claim:
            print("  ✓ 讲义与实测一致（0 失败）")
        elif f != 0:
            print("  ✗ 实测有失败，讲义数字不实")

    # 关键数字是否在实测输出中
    keys = ["1.50x", "2.00x", "0.0300s", "peak=5", "50 > 5"]
    for k in keys:
        in_out = k in out
        in_doc = k in text
        print(f"  {k:12s} 实测{'✓' if in_out else '✗'} 讲义{'✓' if in_doc else '✗'}")


def check_compile():
    print()
    print("=== 3. 脚本编译 ===")
    files = sorted(f for f in os.listdir(HERE) if f.endswith(".py"))
    bad = []
    for fn in files:
        rr = subprocess.run([sys.executable, "-m", "py_compile",
                             os.path.join(HERE, fn)],
                            capture_output=True, text=True)
        if rr.returncode != 0:
            bad.append((fn, rr.stderr.strip()[:120]))
    print(f"  {len(files)} 个脚本, 失败 {len(bad)}")
    for fn, e in bad:
        print(f"    FAIL {fn}: {e}")


def check_size():
    print()
    print("=== 4. 规模 ===")
    with open(LESSON, encoding="utf-8") as f:
        lines = f.readlines()
    print(f"  讲义 {len(lines)} 行")
    mw = os.path.join(HERE, "retry_middleware.py")
    with open(mw, encoding="utf-8") as f:
        print(f"  中间件 {len(f.readlines())} 行")
    heads = [l.strip() for l in lines if l.startswith("## ")]
    print(f"  二级标题 {len(heads)}: {heads}")


if __name__ == "__main__":
    check_links()
    check_numbers()
    check_compile()
    check_size()
