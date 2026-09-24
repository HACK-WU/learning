#!/bin/bash
# MockProducer 到底在哪？探路时见过 confluent_kafka.kafkatest 子模块
# 铁律：不凭"应该有"下结论
set -u
cat > /tmp/l12_mock.py <<'PYEOF'
import confluent_kafka, importlib, inspect
print("="*74); print("MockProducer 存在性核验"); print("="*74)
print(f"  confluent-kafka {confluent_kafka.version()}")
print(f"  顶层含 Mock*: {[x for x in dir(confluent_kafka) if 'Mock' in x]}")
print(f"  子模块: {[x for x in dir(confluent_kafka) if not x.startswith('_') and inspect.ismodule(getattr(confluent_kafka,x,None))]}")

for mod in ["kafkatest","cimpl","_util"]:
    try:
        m=importlib.import_module(f"confluent_kafka.{mod}")
        names=[x for x in dir(m) if 'Mock' in x or 'mock' in x.lower()]
        print(f"  confluent_kafka.{mod}: Mock 相关 = {names}")
    except Exception as e:
        print(f"  confluent_kafka.{mod}: {type(e).__name__}")

# 直接搜包内所有符号
import pkgutil, os
base=os.path.dirname(confluent_kafka.__file__)
hits=[]
for root,dirs,files in os.walk(base):
    for f in files:
        if f.endswith(".py"):
            fp=os.path.join(root,f)
            try: src=open(fp,encoding="utf-8",errors="ignore").read()
            except: continue
            if "MockProducer" in src or "MockConsumer" in src:
                hits.append(os.path.relpath(fp,base))
print(f"\n  包内含 MockProducer/MockConsumer 字样的文件: {hits if hits else '无'}")

# 结论
print(f"\n{'─'*74}")
if not hits:
    print("  结论：本版本 confluent-kafka 不含 MockProducer/MockConsumer")
    print("        -> 单元测试需自行 fake，或用 aiokafka 的测试工具")
else:
    print(f"  结论：Mock 存在于 {hits}")
PYEOF
docker cp /tmp/l12_mock.py l11:/mk.py >/dev/null
docker exec l11 /app/.venv/bin/python /mk.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -25
