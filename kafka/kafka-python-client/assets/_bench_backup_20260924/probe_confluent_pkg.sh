#!/bin/bash
# 课 9 探路②：confluent-kafka 包结构 —— schema_registry 去哪了？
# 结论A: 子包不存在。是 wheel 裁剪？还是独立发行包？必须查清不猜
set -u
cat > /tmp/pk.py <<'PYEOF'
import confluent_kafka as ck, os, pkgutil
print("=== confluent_kafka 包内容 ===")
print(f"  路径: {ck.__path__[0]}")
print(f"  子包/模块: {sorted(m.name for m in pkgutil.iter_modules(ck.__path__))}")
print(f"  __version__ = {getattr(ck,'__version__','?')}")
print(f"  libversion  = {getattr(ck,'libversion','?')}")
print(f"  version     = {getattr(ck,'version','?')}")

print("\n=== 顶层导出中含 schema 的符号 ===")
print(f"  {[x for x in dir(ck) if 'schema' in x.lower()]}")

print("\n=== 已安装的 confluent 系发行包 ===")
import importlib.metadata as md
for d in md.distributions():
    n = (d.metadata["Name"] or "").lower()
    if "confluent" in n or "avro" in n or "schema" in n or "fast" in n:
        print(f"  {d.metadata['Name']} == {d.version}")

print("\n=== cimpl 是否内置 serializer ===")
from confluent_kafka import cimpl
names = [x for x in dir(cimpl) if "serial" in x.lower() or "deserial" in x.lower()]
print(f"  cimpl 中 serializer 相关: {names if names else '（无）'}")

print("\n=== 能否 import 独立 SR 客户端（未装时的报错原文）===")
try:
    from confluent_kafka.schema_registry import SchemaRegistryClient
    print("  ✓ 可导入")
except ImportError as e:
    print(f"  ✗ ImportError: {e}")
PYEOF
docker run --rm -v /tmp/pk.py:/pk.py kafka-pybench:3.12 \
  /app/.venv/bin/python /pk.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -35
