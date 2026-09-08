"""验证：POST 表单编码下，+ 号是否会被解码成空格？

假设：wget --post-data 默认用 application/x-www-form-urlencoded，
其中 + 号代表空格。所以 {__name__=~".+"} 会被服务端解析成 {__name__=~". "}，
导致匹配不到任何序列。

验证方法：对比 POST(原始) / POST(编码+) / GET(URL编码) 三种方式。
"""
import json
import subprocess
import urllib.parse

PROM = "l6-prom"

EXPRS = [
    '{__name__=~".+"}',
    '{__name__=~".*"}',
    'l6_card_metric{idx="000123"}',
]


def run(method, expr):
    """用指定方式查询，返回命中数。"""
    if method == "post_raw":
        cmd = ["docker", "exec", PROM, "wget", "-qO-",
               "http://localhost:9090/api/v1/query",
               "--post-data", f"query={expr}"]
    elif method == "post_encoded":
        cmd = ["docker", "exec", PROM, "wget", "-qO-",
               "http://localhost:9090/api/v1/query",
               "--post-data", f"query={urllib.parse.quote_plus(expr)}"]
    else:  # get_encoded
        url = ("http://localhost:9090/api/v1/query?query="
               + urllib.parse.quote(expr))
        cmd = ["docker", "exec", PROM, "wget", "-qO-", url]

    r = subprocess.run(cmd, capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
        return len(d["data"]["result"]), d.get("status")
    except Exception:
        return -1, r.stdout[:120]


print("== 三种传参方式对比 ==")
print(f'{"表达式":<30} | {"POST原样":>10} | {"POST编码":>10} | {"GET编码":>10}')
print("-" * 70)
for e in EXPRS:
    a, sa = run("post_raw", e)
    b, sb = run("post_encoded", e)
    c, sc = run("get_encoded", e)
    print(f"{e:<30} | {a:>10} | {b:>10} | {c:>10}")

print()
print("== 结论验证：服务端实际收到什么？ ==")
# 用一个能回显的表达式验证：构造 "a+b" 看是否被当空格
for expr in ['{__name__=~".+"}', 'vector(1) + vector(2)']:
    n1, _ = run("post_raw", expr)
    n2, _ = run("post_encoded", expr)
    print(f"   {expr!r:<34} POST原样={n1:<6} POST编码={n2}")
