import kafka, importlib.metadata as md
try:
    v = md.version("kafka-python-ng")
except Exception:
    v = "?"
print("=" * 60)
print(f"kafka-python-ng  {v}")
print("=" * 60)
P = kafka.KafkaProducer
C = kafka.KafkaConsumer
for m in ("init_transactions", "begin_transaction", "commit_transaction",
          "abort_transaction", "send_offsets_to_transaction"):
    print(f"  KafkaProducer.{m:<26} = {hasattr(P, m)}")
for m in ("init_transactions", "begin_transaction", "commit_transaction",
          "abort_transaction", "send_offsets_to_transaction"):
    print(f"  KafkaConsumer.{m:<26} = {hasattr(C, m)}")
print("\n  DEFAULT_CONFIG 中事务/幂等相关键:")
for k in sorted(P.DEFAULT_CONFIG):
    if any(w in k.lower() for w in ("transaction", "idempot", "isolation")):
        print(f"    {k:<40} = {P.DEFAULT_CONFIG[k]!r}")
