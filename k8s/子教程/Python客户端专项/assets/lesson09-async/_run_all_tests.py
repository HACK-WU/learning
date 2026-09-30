"""汇总：修复后两个测试套件的最终结果

用 Python 跑子进程并统计，避免 shell 解释中文导致命令错乱。
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
PY = HERE.parent.parent / ".venv" / "bin" / "python"

SUITES = [
    "test_retry_middleware.py",
    "_verify_budget_fix.py",
]

total_pass = total_fail = 0
for s in SUITES:
    r = subprocess.run([str(PY), s], capture_output=True, text=True,
                       cwd=str(HERE), timeout=300)
    out = r.stdout
    m = re.search(r"通过\s+(\d+)\s*/\s*失败\s+(\d+)", out)
    fails = [l for l in out.splitlines() if "✗" in l]
    if m:
        p, f = int(m.group(1)), int(m.group(2))
    else:
        p, f = 0, len(out.splitlines())
    total_pass += p
    total_fail += f + len(fails)
    print(f"{s:32s} 通过 {p:3d}  失败 {f:3d}  exit={r.returncode}")
    for l in fails:
        print("    失败项:", l.strip())

print()
print(f"合计: 通过 {total_pass}, 失败 {total_fail}")
sys.exit(1 if total_fail else 0)
