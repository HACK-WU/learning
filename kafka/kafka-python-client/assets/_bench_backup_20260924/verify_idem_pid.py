"""课 6：幂等核心 —— producer_id / epoch / sequence 三元组。

要验证：
  1. 幂等 producer 确实拿到了 producer_id + epoch（不是 -1）
  2. 非幂等 producer 的 producer_id 是 -1
  3. 批次里的 base_sequence 从 0 开始递增
  4. B 组（acks=0）到底有没有发 warning（上一版没捕获到，需确认）
"""
import ast
import inspect
import logging
import socket
import textwrap

from kafka import KafkaProducer


def nd(obj):
    s = textwrap.dedent(inspect.getsource(obj))
    t = ast.parse(s)
    fn = t.body[0]
    if (isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) and fn.body
            and isinstance(fn.body[0], ast.Expr)
            and isinstance(fn.body[0].value, ast.Constant)
            and isinstance(fn.body[0].value.value, str)):
        lines = s.split("\n")
        return "\n".join(lines[:1] + lines[fn.body[0].end_lineno:])
    return s


HOSTS = ["kafka-1", "kafka-2", "kafka-3"]
BS_LIST = []
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        s = socket.socket()
        s.settimeout(3)
        s.connect((ip, 9092))
        BS_LIST.append(f"{h}:9092")
        s.close()
    except OSError:
        pass
BS = ",".join(BS_LIST)
T = "l6-idem"

print("=" * 74)
print("1. TransactionManager 里 producer_id/epoch 从哪来")
print("=" * 74)
from kafka.producer import transaction_manager as tm
src = inspect.getsource(tm)
for i, l in enumerate(src.split("\n"), 1):
    if any(k in l for k in ("producer_id =", "producer_epoch =",
                            "def set_producer_id_and_epoch",
                            "class ProducerIdAndEpoch")):
        print(f"  L{i}: {l.strip()[:120]}")

print("\n" + "=" * 74)
print("2. 幂等 producer 的 InitProducerId 请求")
print("=" * 74)
try:
    print(nd(tm.TransactionManager.initialize_transactions)[:1200])
except Exception as e:
    print(f"  {type(e).__name__}: {e}")

print("\n" + "=" * 74)
print("3. B 组复查：acks=0 到底有没有 warning")
print("=" * 74)


class Cap(logging.Handler):
    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.msgs = []

    def emit(self, r):
        self.msgs.append(f"[{r.levelname}] {r.getMessage()[:180]}")


root = logging.getLogger()
root.setLevel(logging.DEBUG)
cap = Cap()
root.addHandler(cap)

p0 = KafkaProducer(bootstrap_servers=BS, max_block_ms=8000, acks=0)
idem = p0.config.get("enable_idempotence")
print(f"  acks=0 后 enable_idempotence = {idem}")
rel = [m for m in cap.msgs if "idempot" in m.lower() or "Idempotence" in m]
print(f"  捕获日志 {len(cap.msgs)} 条，其中幂等相关 {len(rel)} 条：")
for m in rel:
    print(f"    {m}")
if not rel:
    print("    → 确认：acks=0 静默关闭幂等，【没有任何 warning 输出】")
p0.close()

print("\n" + "=" * 74)
print("4. 对比：显式 True + acks=1（也冲突）→ 是否抛异常")
print("=" * 74)
from kafka.errors import KafkaConfigurationError
try:
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=8000,
                      acks=1, enable_idempotence=True)
    print(f"  未抛异常，enable_idempotence={p.config.get('enable_idempotence')}")
    p.close()
except KafkaConfigurationError as e:
    print(f"  ✗ 抛异常: {str(e)[:170]}")

print("\n" + "=" * 74)
print("5. 幂等 producer 实际拿到的 producer_id / epoch")
print("=" * 74)
pi = KafkaProducer(bootstrap_servers=BS, max_block_ms=8000)   # 全默认，幂等开
m = pi._transaction_manager
print(f"  enable_idempotence = {pi.config.get('enable_idempotence')}")
for attr in ("producer_id", "epoch", "producer_id_and_epoch",
             "_producer_id_and_epoch", "sequence_numbers"):
    v = getattr(m, attr, "【无此属性】")
    print(f"  tm.{attr:<26} = {v}")
pi.close()

pn = KafkaProducer(bootstrap_servers=BS, max_block_ms=8000,
                   enable_idempotence=False)
mn = pn._transaction_manager
print(f"\n  非幂等（显式False）:")
for attr in ("producer_id", "epoch", "_producer_id_and_epoch"):
    v = getattr(mn, attr, "【无此属性】")
    print(f"  tm.{attr:<26} = {v}")
pn.close()
