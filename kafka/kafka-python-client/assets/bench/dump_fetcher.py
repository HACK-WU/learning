"""课 5：Fetcher 与位移提交路径。

两个核心：
  1. fetch_records —— 数据从哪来（completed_fetches vs 网络）
  2. 位移提交链路：poll -> _message_generator -> subscription -> coordinator
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


from kafka.consumer.fetcher import Fetcher
from kafka.consumer.subscription_state import SubscriptionState

print("=" * 72)
print("1. Fetcher.fetch_records（数据从哪来）")
print("=" * 72)
print(nd(Fetcher.fetch_records)[:3200])

print("\n" + "=" * 72)
print("2. 一条记录消费完，位移记在哪？—— 找 position 更新点")
print("=" * 72)
src = inspect.getsource(Fetcher)
for i, l in enumerate(src.split("\n"), 1):
    ll = l.lower()
    if ("position" in ll and ("advance" in ll or "update" in ll
                              or "=" in ll)) or "seen(" in ll:
        print(f"  L{i}: {l.rstrip()[:120]}")
