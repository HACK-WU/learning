#!/bin/bash
# 核验：AIOConsumer 到底存不存在？可能在子模块 confluent_kafka.aio
# 阶段4 overview 称「confluent 2.13.0 起 AIO* 正式 GA」，但顶层 hasattr 全 False
# 按「先核验再下结论」铁律，不能凭顶层查不到就判 overview 错
set -u
cat > /tmp/l11_aio.py <<'PYEOF'
import confluent_kafka as ck, pkgutil, importlib, inspect, os

print("=" * 74)
print("核验：AIOConsumer / AIOProducer 到底在哪")
print("=" * 74)
print(f"confluent_kafka 版本: {ck.version()}")
print(f"包路径: {os.path.dirname(ck.__file__)}\n")

print("────── 1. 全部子模块 ──────")
subs = [m.name for m in pkgutil.iter_modules([os.path.dirname(ck.__file__)])]
print(f"  {subs}\n")

print("────── 2. 尝试 import confluent_kafka.aio ──────")
try:
    aio = importlib.import_module("confluent_kafka.aio")
    print(f"  ✓ confluent_kafka.aio 存在")
    names = [n for n in dir(aio) if not n.startswith("_")]
    print(f"    导出: {names}")
except ImportError as e:
    print(f"  ✗ 不存在: {e}")

print("\n────── 3. 全包搜索 AIO* 符号（递归所有子模块）──────")
found = {}
for m in subs:
    try:
        mod = importlib.import_module(f"confluent_kafka.{m}")
    except Exception:
        continue
    for n in dir(mod):
        if n.startswith("AIO"):
            found.setdefault(m, []).append(n)
if found:
    for k, v in found.items():
        print(f"  confluent_kafka.{k}: {v}")
else:
    print(f"  ✗ 所有子模块均无 AIO* 开头的符号")

print("\n────── 4. 在包目录内 grep 源码文本 ──────")
print("  （防止符号未导出但源码存在）")
import subprocess
d = os.path.dirname(ck.__file__)
r = subprocess.run(["grep", "-rl", "AIOConsumer", d], capture_output=True, text=True)
print(f"  含 'AIOConsumer' 文本的文件: {r.stdout.strip().split() or '无'}")
r2 = subprocess.run(["grep", "-rl", "AIOProducer", d], capture_output=True, text=True)
print(f"  含 'AIOProducer' 文本的文件: {r2.stdout.strip().split() or '无'}")

print("\n────── 5. dist-info 里的 RECORD（看有没有 aio 相关文件）──────")
import glob
for p in glob.glob(os.path.dirname(d) + "/confluent_kafka-*.dist-info/RECORD"):
    lines = [l.split(",")[0] for l in open(p) if "aio" in l.lower()]
    print(f"  RECORD 中 aio 相关条目: {lines[:10] or '无'}")
    break

print("\n" + "=" * 74)
print("判定")
print("=" * 74)
print("  若 1-5 全无 -> 本版本 confluent-kafka 确实没有 AIO 支持")
print("  -> 阶段4 overview『2.13.0 起 AIO* GA』的记载需要修正")
print("=" * 74)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/l11_aio.py:/a.py \
  kafka-pybench:3.12 /app/.venv/bin/python /a.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
