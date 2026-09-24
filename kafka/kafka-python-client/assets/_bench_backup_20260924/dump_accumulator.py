"""课 4：批次累加 + 背压 + 就绪条件（核心）。

上一版 send() 的 docstring 没切干净，这版用 ast 精确剥离 docstring。
"""
import ast
import inspect
import textwrap


def src_no_docstring(obj):
    """用 ast 精确剥离 docstring，比字符串匹配可靠。"""
    s = textwrap.dedent(inspect.getsource(obj))
    tree = ast.parse(s)
    fn = tree.body[0]
    if (isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef))
            and fn.body
            and isinstance(fn.body[0], ast.Expr)
            and isinstance(fn.body[0].value, ast.Constant)
            and isinstance(fn.body[0].value.value, str)):
        lines = s.split("\n")
        # docstring 结束行（1-based → 0-based 索引）
        dl = fn.body[0].end_lineno
        head = lines[:1]
        body = lines[dl:]
        return "\n".join(head + ["     ...(docstring 已剥离)..."] + body)
    return s


from kafka.producer.record_accumulator import RecordAccumulator

print("=" * 70)
print("1. RecordAccumulator.append —— 批次累加")
print("=" * 70)
print(src_no_docstring(RecordAccumulator.append)[:3500])
