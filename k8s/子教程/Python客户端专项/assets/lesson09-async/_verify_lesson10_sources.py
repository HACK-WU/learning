"""核验：讲义中每个实测数字块，是否都标了真实来源脚本

上一轮抓到：41 vs 48 混用、2.00x 标错来源（标 B3 实为 V2）。
本脚本逐块比对讲义文本与两个套件的真实输出，杜绝张冠李戴。
"""
import os
import re
import subprocess
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LESSON = os.path.join(SUBROOT, "lessons", "lesson-10-重试中间件工程化.md")
HERE = os.path.join(SUBROOT, "assets", "lesson09-async")
PY = os.path.join(SUBROOT, ".venv", "bin", "python")


def run(fn):
    r = subprocess.run([PY, fn], cwd=HERE, capture_output=True,
                       text=True, timeout=300)
    return r.stdout


def main():
    with open(LESSON, encoding="utf-8") as f:
        text = f.read()

    out_main = run("test_retry_middleware.py")
    out_fix = run("_verify_budget_fix.py")
    out_v = run("_verify_budget.py")

    m1 = re.search(r"通过\s+(\d+)\s*/\s*失败\s+(\d+)", out_main)
    m2 = re.search(r"通过\s+(\d+)\s*/\s*失败\s+(\d+)", out_fix)
    p1, f1 = (int(m1.group(1)), int(m1.group(2))) if m1 else (0, 0)
    p2, f2 = (int(m2.group(1)), int(m2.group(2))) if m2 else (0, 0)

    print("=== 测试项数 ===")
    print(f"  主套件 test_retry_middleware.py : 通过 {p1} 失败 {f1}")
    print(f"  修复套件 _verify_budget_fix.py  : 通过 {p2} 失败 {f2}")
    print(f"  合计 {p1+p2}")
    print(f"  讲义表述 '48 项断言' : "
          f"{'✓ 一致' if (p1+p2) == 48 and f1+f2 == 0 else '✗ 不一致'}")
    print(f"  讲义表述 '主套件 41' : "
          f"{'✓ 一致' if p1 == 41 else f'✗ 实为 {p1}'}")
    print(f"  讲义表述 '修复验证 7': "
          f"{'✓ 一致' if p2 == 7 else f'✗ 实为 {p2}'}")

    print()
    print("=== 关键数字归属核验 ===")
    checks = [
        ("1.50x", out_v, "V2 ratio 扫描"),
        ("2.00x", out_v, "V2 ratio 扫描"),
        ("0.0300s", out_main, "B2 cap"),
        ("peak=5", out_main, "B4 闸门"),
        ("50 > 5", out_main, "B4 闸门"),
    ]
    for val, out, desc in checks:
        print(f"  {val:10s} 在[{desc}]输出中: {'✓' if val in out else '✗'}")

    # 讲义里 2.00x 是否已标明 V2 来源
    idx = text.find("2.00x")
    ctx = text[max(0, idx - 200):idx]
    print()
    print("=== 讲义 2.00x 处来源标注 ===")
    print("  前文:", ctx[-90:].replace("\n", " | "))
    print(f"  已标 _verify_budget.py: "
          f"{'✓' if '_verify_budget.py' in ctx else '✗ 未标'}")


if __name__ == "__main__":
    main()
