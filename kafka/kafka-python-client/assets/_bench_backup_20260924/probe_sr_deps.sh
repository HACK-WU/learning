#!/bin/bash
# 课 9 探路③：schema_registry 子包存在但 import 失败，缺哪些依赖？
# 逐个剥离 ImportError，摸清完整依赖链（只读检测，不安装）
set -u
cat > /tmp/dep.py <<'PYEOF'
import importlib, sys
seen = []
for _ in range(12):
    try:
        from confluent_kafka.schema_registry import SchemaRegistryClient
        print("  ✓ 全部依赖就位，SchemaRegistryClient 可导入")
        break
    except ImportError as e:
        mod = str(e).replace("No module named ", "").strip("'\"")
        if mod in seen:
            print(f"  ✗ 循环缺失，仍缺: {mod}")
            break
        seen.append(mod)
        print(f"  缺依赖 #{len(seen)}: {mod}")
        # 打桩跳过，继续探测下一个
        sys.modules[mod] = type(sys)(mod)
        if "." in mod:
            parent, child = mod.rsplit(".", 1)
            if parent in sys.modules and hasattr(sys.modules[parent], "__path__"):
                setattr(sys.modules[parent], child, sys.modules[mod])

print(f"\n  >>> 完整依赖缺口清单（{len(seen)} 个）: {seen}")

print("\n=== 逐个尝试 avro / json_schema / protobuf 子模块 ===")
for sub in ("avro", "json_schema", "protobuf"):
    try:
        importlib.import_module(f"confluent_kafka.schema_registry.{sub}")
        print(f"  ✓ schema_registry.{sub}")
    except ImportError as e:
        print(f"  ✗ schema_registry.{sub}: {e}")
    except Exception as e:
        print(f"  ? schema_registry.{sub}: {type(e).__name__}: {str(e)[:70]}")

print("\n=== serialization / serializing_producer 是否可用 ===")
for m in ("confluent_kafka.serialization",
          "confluent_kafka.serializing_producer",
          "confluent_kafka.deserializing_consumer"):
    try:
        importlib.import_module(m)
        print(f"  ✓ {m}")
    except ImportError as e:
        print(f"  ✗ {m}: {e}")
PYEOF
docker run --rm -v /tmp/dep.py:/d.py kafka-pybench:3.12 \
  /app/.venv/bin/python /d.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -30
