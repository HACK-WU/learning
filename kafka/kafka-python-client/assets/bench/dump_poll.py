"""课 5：poll 一次到底做了什么 —— 源码级拆解。

沿用课 4 的 ast 剥离 docstring 手法（字符串匹配不靠谱）。
"""
import ast
import inspect
import textwrap


def nd(obj):
    """精确剥离 docstring"""
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


from kafka import KafkaConsumer

print("=" * 72)
print("1. KafkaConsumer.poll（外层）")
print("=" * 72)
print(nd(KafkaConsumer.poll)[:2600])
