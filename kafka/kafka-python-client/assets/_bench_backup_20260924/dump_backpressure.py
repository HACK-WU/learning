"""课 4：背压 + 批次就绪条件（本课最难的两块）。

背压：buffer_memory 耗尽 → send() 阻塞（不是抛异常）
就绪：什么条件下批次才会被 Sender 拿走
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
        return "\n".join(lines[:1] + ["     ...(docstring 剥离)..."] + lines[fn.body[0].end_lineno:])
    return s


from kafka.producer.record_accumulator import RecordAccumulator
from kafka.producer.sender import Sender

print("=" * 70)
print("1. 背压：RecordAccumulator._allocate")
print("=" * 70)
try:
    print(nd(RecordAccumulator._allocate)[:2500])
except Exception as e:
    print(f"{type(e).__name__}: {e}")

print("\n" + "=" * 70)
print("2. 就绪条件：RecordAccumulator.ready")
print("=" * 70)
try:
    print(nd(RecordAccumulator.ready)[:3000])
except Exception as e:
    print(f"{type(e).__name__}: {e}")

print("\n" + "=" * 70)
print("3. Sender.run_once —— 真正的发送循环")
print("=" * 70)
try:
    print(nd(Sender.run_once)[:2500])
except Exception as e:
    print(f"{type(e).__name__}: {e}")
