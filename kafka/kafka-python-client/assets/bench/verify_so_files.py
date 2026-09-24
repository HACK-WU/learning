"""课 1：确认三个库到底有没有编译产物（.so），以及各自的内核。
判据：纯 Python 库不会有 .so；C 扩展库会有。
"""
import os
import subprocess

LIBS = [("kafka-python", "3.0.11", "kafka"),
        ("kafka-python-ng", "2.2.3", "kafka"),
        ("confluent-kafka", "2.15.1", "confluent_kafka"),
        ("aiokafka", "0.14.0", "aiokafka")]

for pipname, ver, modname in LIBS:
    print(f"=== {pipname}=={ver} ===")
    try:
        mod = __import__(modname)
        p = os.path.dirname(mod.__file__)
        print(f"  包路径: {p}")
        r = subprocess.run(["find", p, "-name", "*.so"],
                           capture_output=True, text=True)
        sos = [x for x in r.stdout.strip().splitlines() if x]
        print(f"  .so 数量: {len(sos)}")
        for s in sos[:6]:
            print(f"     - {os.path.basename(s)}")
        if not sos:
            print("     （无编译产物 → 纯 Python）")
        # 版本
        v = getattr(mod, "__version__", "?")
        print(f"  运行时版本: {v}")
    except Exception as e:
        print(f"  导入失败: {type(e).__name__}: {e}")
    print()
