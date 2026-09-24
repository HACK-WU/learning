"""课 5：_poll_once —— poll 的真正核心（四步）。"""
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


from kafka import KafkaConsumer

print("=" * 72)
print("KafkaConsumer._poll_once（poll 的四步核心）")
print("=" * 72)
print(nd(KafkaConsumer._poll_once)[:3500])
