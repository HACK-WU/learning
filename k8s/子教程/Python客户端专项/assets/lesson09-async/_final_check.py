"""最终交付核验：overview 三处回写 + 残留 + 索引一致性"""
import io
import os
import subprocess
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OV = os.path.join(SUBROOT, "overview.md")


def main():
    with io.open(OV, encoding="utf-8") as f:
        lines = f.readlines()
    t = "".join(lines)

    print("=== overview 三处回写 ===")
    print("  课程表含课 10 :", "✓" if "课 10：重试中间件工程化" in t else "✗")
    print("  交付记录含课10:", "✓" if "**课 10 交付**" in t else "✗")
    print("  进度含课 10   :", "✓" if "- [x] 课 10" in t else "✗")

    print()
    print("=== 备份残留 ===")
    baks = [f for f in os.listdir(SUBROOT) if f.startswith("overview.md.bak")]
    print("  overview 备份:", baks if baks else "无")

    print()
    print("=== 全子教程链接可达性（课 9 番外 + 课 10）===")
    lessons = os.path.join(SUBROOT, "lessons")
    miss = []
    for fn in os.listdir(lessons):
        if not fn.endswith(".md"):
            continue
        p = os.path.join(lessons, fn)
        with io.open(p, encoding="utf-8") as f:
            txt = f.read()
        import re
        for name, u in re.findall(r"\[([^\]]+)\]\(([^)]+)\)", txt):
            if u.startswith(("http://", "https://")):
                continue
            c = u.split("#")[0]
            if not c:
                continue
            tp = os.path.normpath(os.path.join(lessons, c))
            if not os.path.exists(tp):
                miss.append((fn, name, u))
    print(f"  讲义 {len(os.listdir(lessons))} 篇, 坏链 {len(miss)} 条")
    for fn, n, u in miss[:8]:
        print(f"    MISS {fn}: [{n}]({u})")

    print()
    print("=== 脚本编译 ===")
    d = os.path.join(SUBROOT, "assets", "lesson09-async")
    pys = sorted(f for f in os.listdir(d) if f.endswith(".py"))
    bad = []
    for fn in pys:
        r = subprocess.run([sys.executable, "-m", "py_compile",
                            os.path.join(d, fn)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            bad.append(fn)
    print(f"  {len(pys)} 个脚本, 失败 {len(bad)} {bad if bad else ''}")


if __name__ == "__main__":
    main()
