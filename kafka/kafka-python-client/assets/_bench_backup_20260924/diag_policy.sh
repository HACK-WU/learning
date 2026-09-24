#!/bin/bash
# 诊断：策略矩阵全部"放行"是否可信
# 怀疑点：try_reg 里注册 v1 失败被 pass 吞掉，v2 变成首版 → 首版无条件放行
set -u
cat > /tmp/diagpolicy.py <<'PYEOF'
import json
from confluent_kafka.schema_registry import (
    SchemaRegistryClient, Schema, ServerConfig, ConfigCompatibilityLevel)
c = SchemaRegistryClient({"url":"http://l9-sr:8081"})

V1 = json.dumps({"type":"record","name":"P","fields":[
    {"name":"a","type":"string"},{"name":"b","type":"int"}]})
V2_DROP = json.dumps({"type":"record","name":"P","fields":[
    {"name":"b","type":"int"}]})

subj = "DIAG-full"
print("=== 步骤1: 设 full 策略 ===")
r = c.set_config(subj, ServerConfig(compatibility_level=ConfigCompatibilityLevel.FULL))
print(f"  set_config 返回: {r}")

print("\n=== 步骤2: 注册 v1（不吞异常）===")
try:
    i1 = c.register_schema(subj, Schema(V1,"AVRO")); print(f"  v1 注册成功 id={i1}")
except Exception as e:
    print(f"  v1 注册失败: {type(e).__name__}: {str(e)[:160]}")

print("\n=== 步骤3: 查当前版本（确认 v1 真在）===")
try: print(f"  versions = {c.get_versions(subj)}")
except Exception as e: print(f"  {e}")

print("\n=== 步骤4: 注册 v2（删掉字段 a）===")
try:
    i2 = c.register_schema(subj, Schema(V2_DROP,"AVRO"))
    print(f"  v2 注册成功 id={i2}  <- full 策略下删字段被放行？")
except Exception as e:
    print(f"  v2 被拒: {type(e).__name__}")
    print(f"  {str(e)[:250]}")

print("\n=== 步骤5: 用 test_compatibility 交叉验证 ===")
try:
    ok = c.test_compatibility(subj, Schema(V2_DROP,"AVRO"))
    print(f"  test_compatibility(v2) = {ok}")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/diagpolicy.py:/d.py \
  kafka-pybench:3.12 /app/.venv/bin/python /d.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' -e 'Authlib' -e 'from ._compat' | head -30
