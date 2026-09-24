"""课 1 关键核验：kafka-python 与 kafka-python-ng 的 import name 冲突。

判据：若两库 import name 都是 `kafka`，则不能共存于同一环境——
      后装的会覆盖先装的，且 pip 不报错（静默）。这是选型的重要约束。
"""
import importlib.metadata as md
import subprocess
import sys

PIP = [sys.executable, "-m", "pip"]


def show_state(label):
    print(f"--- {label} ---")
    try:
        import kafka
        print(f"  import kafka 成功，__version__ = {kafka.__version__}")
        print(f"  包路径 = {kafka.__file__}")
    except Exception as e:
        print(f"  import kafka 失败: {type(e).__name__}")
    # 看 pip 实际认谁
    r = subprocess.run([*PIP, "list"], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if "kafka" in line.lower():
            print(f"  pip list: {line}")
    print()


print("=== 场景 1：只装 kafka-python ===")
subprocess.run([*PIP, "install", "-q", "kafka-python==3.0.11"],
               capture_output=True, text=True)
show_state("仅 kafka-python 3.0.11")

print("=== 场景 2：在 kafka-python 之上再装 kafka-python-ng ===")
r = subprocess.run([*PIP, "install", "-q", "kafka-python-ng==2.2.3"],
                   capture_output=True, text=True)
print(f"  pip install 退出码: {r.returncode}")
if r.returncode != 0:
    print(f"  stderr: {r.stderr[:300]}")
show_state("两库都装了")

print("=== 场景 3：反过来，先 ng 再 kafka-python ===")
subprocess.run([*PIP, "uninstall", "-y", "-q", "kafka-python", "kafka-python-ng"],
               capture_output=True, text=True)
subprocess.run([*PIP, "install", "-q", "kafka-python-ng==2.2.3"],
               capture_output=True, text=True)
show_state("先装 ng")
subprocess.run([*PIP, "install", "-q", "kafka-python==3.0.11"],
               capture_output=True, text=True)
show_state("再装 kafka-python（谁覆盖谁？）")

print("=== 结论用：检查 dist-info 名称 ===")
r = subprocess.run([*PIP, "list", "--format=json"], capture_output=True, text=True)
import json
try:
    pkgs = json.loads(r.stdout)
    for p in pkgs:
        if "kafka" in p["name"].lower():
            print(f"  {p['name']} == {p['version']}")
except Exception as e:
    print("  解析失败", e)
