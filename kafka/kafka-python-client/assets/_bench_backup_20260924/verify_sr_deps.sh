#!/bin/bash
# 课 9 验证①：依赖补齐后，Schema Registry 客户端与序列化库是否真可用
set -u
cat > /tmp/vdep.py <<'PYEOF'
import importlib.metadata as md, importlib
print("=== 1. Schema Registry 客户端 ===")
try:
    from confluent_kafka.schema_registry import SchemaRegistryClient, Schema
    print(f"  ✓ SchemaRegistryClient / Schema 可导入")
    import inspect
    print(f"    SchemaRegistryClient.__init__{inspect.signature(SchemaRegistryClient.__init__)}")
    print(f"    Schema.__init__{(inspect.signature(Schema.__init__))}")
except Exception as e:
    print(f"  ✗ {type(e).__name__}: {e}")

print("\n=== 2. 各格式 serializer ===")
for mod, cls in [
    ("confluent_kafka.schema_registry.avro", "AvroSerializer"),
    ("confluent_kafka.schema_registry.avro", "AvroDeserializer"),
    ("confluent_kafka.schema_registry.json_schema", "JSONSerializer"),
    ("confluent_kafka.schema_registry.protobuf", "ProtobufSerializer"),
]:
    try:
        m = importlib.import_module(mod)
        c = getattr(m, cls, None)
        print(f"  ✓ {mod}.{cls} = {'存在' if c else '✗不存在'}")
        if c and cls.endswith("Serializer"):
            import inspect
            print(f"      init{inspect.signature(c.__init__)}")
    except Exception as e:
        print(f"  ✗ {mod}.{cls}: {type(e).__name__}: {str(e)[:80]}")

print("\n=== 3. SerializingProducer / DeserializingConsumer ===")
try:
    from confluent_kafka import SerializingProducer, DeserializingConsumer
    print("  ✓ 两者均可导入（课 9 主力 API）")
except Exception as e:
    print(f"  ✗ {e}")

print("\n=== 4. 序列化库版本 ===")
for p in ("fastavro", "jsonschema", "protobuf", "authlib", "httpx", "certifi"):
    try: print(f"  ✓ {p:<14} {md.version(p)}")
    except Exception: print(f"  ✗ {p} 未装")
PYEOF
docker run --rm -v /tmp/vdep.py:/v.py kafka-pybench:3.12 \
  /app/.venv/bin/python /v.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -35
