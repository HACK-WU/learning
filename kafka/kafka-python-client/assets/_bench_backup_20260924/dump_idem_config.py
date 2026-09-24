"""课 6：幂等配置校验逻辑 —— 什么时候会被【静默关闭】。

关键线索（producer/kafka.py:588）：
  "Idempotence will be disabled because user-provided config conflicts with..."
"""
import ast
import inspect
import textwrap


def nd(obj):
    s = textwrap.dedent(inspect.getsource(obj))
    t = ast.parse(s)
    fn = t.body[0]
    if (isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)) and fn.body
            and isinstance(fn.body[0], ast.Expr)
            and isinstance(fn.body[0].value, ast.Constant)
            and isinstance(fn.body[0].value.value, str)):
        lines = s.split("\n")
        return "\n".join(lines[:1] + ["     ...(docstring 剥离)..."]
                         + lines[fn.body[0].end_lineno:])
    return s


from kafka.producer.kafka import KafkaProducer

print("=" * 74)
print("1. 配置校验入口")
print("=" * 74)
for name in ("_validate_config", "_bootstrap", "__init__"):
    fn = getattr(KafkaProducer, name, None)
    if fn is None:
        continue
    src = nd(fn)
    # 只打印含幂等判断的片段
    lines = src.split("\n")
    hit = [(i, l) for i, l in enumerate(lines)
           if "idempot" in l.lower() or "Idempot" in l]
    if hit:
        print(f"\n--- {name} 中幂等相关行 ---")
        for i, l in hit:
            lo = max(0, i - 3)
            hi = min(len(lines), i + 14)
            print("\n".join(f"  {x}" for x in lines[lo:hi]))
            print("  " + "-" * 60)
            break          # 只取第一处最相关的上下文

print("\n" + "=" * 74)
print("2. 幂等的三条硬约束（读 docstring 原文）")
print("=" * 74)
doc = inspect.getdoc(KafkaProducer) or ""
started = False
for ln in doc.split("\n"):
    if "idempot" in ln.lower():
        started = True
    if started:
        print(f"  {ln}")
    if started and ln.strip() == "" and "idempot" not in ln.lower():
        pass
