#!/usr/bin/env python3
# 课 1 第四幕：三种数据形态对照实验
# 为什么用 python 而不是 bash：实验要拼 JSON、解析嵌套响应，
# 在 bash 里内联 python 会陷入引号转义地狱（前两版已连续踩坑）。
import json
import time
import urllib.parse
import urllib.request
from http.cookiejar import CookieJar

GF = "http://localhost:3001"
PROM = "http://localhost:9201"

# 用 cookie jar 维持登录态
cj = CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))


def req(url, data=None, method=None, headers=None):
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers = {"Content-Type": "application/json", **(headers or {})}
    r = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with opener.open(r, timeout=60) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def get(url):
    with opener.open(url, timeout=60) as resp:
        return resp.status, resp.read().decode()


print("=== 0. 健康检查 ===")
code, body = get(f"{GF}/api/health")
print(f"  Grafana /api/health -> {code}  {body[:90]}")
code, body = get(f"{PROM}/api/v1/query?query=up")
d = json.loads(body)
print(f"  Prometheus up 查询 -> status={d['status']} 条数={len(d['data']['result'])}")

print("\n=== 1. 登录 ===")
code, body = req(f"{GF}/login", {"user": "admin", "password": "admin"})
print(f"  login -> {code}  {body[:60]}")

print("\n=== 2. 数据源 ===")
code, body = get(f"{GF}/api/datasources/name/PromLab")
ds = json.loads(body)
DS_UID = ds["uid"]
print(f"  PromLab uid={DS_UID}  url={ds.get('url')}  access={ds.get('access')}")


def run_query(label, expr, instant):
    print(f"\n=========== {label} ===========")
    print(f"  表达式：{expr}")
    payload = {
        "queries": [{
            "refId": "A",
            "datasource": {"type": "prometheus", "uid": DS_UID},
            "expr": expr,
            "instant": instant,
            "range": not instant,
            "intervalMs": 15000,
            "maxDataPoints": 50,
        }],
        "from": "now-15m",   # 必填！漏了会返回 400 bad request data
        "to": "now",
    }
    t0 = time.time()
    code, body = req(f"{GF}/api/ds/query", payload)
    cost = time.time() - t0
    print(f"  HTTP={code}  耗时={cost:.3f}s")
    r = json.loads(body).get("results", {}).get("A", {})
    if "error" in r:
        print(f"  错误：{r['error'][:200]}")
        return
    frames = r.get("frames", [])
    print(f"  frame 数量：{len(frames)}")
    for i, f in enumerate(frames[:3]):
        schema = f.get("schema", {})
        meta = schema.get("meta", {})
        fields = schema.get("fields", [])
        print(f"  frame[{i}] meta.type={meta.get('type')}  typeVersion={meta.get('typeVersion')}")
        custom = meta.get("custom", {})
        print(f"  frame[{i}] custom.resultType={custom.get('resultType')}  "
              f"calculatedMinStep={custom.get('calculatedMinStep')}")
        for fl in fields:
            vals = fl.get("values", [])
            shown = str(vals)[:70]
            print(f"      字段 {fl.get('name')!r} type={fl.get('type')} "
                  f"标签={fl.get('labels', {})} 值={shown}")
        print(f"      data.values 长度={len(f.get('data', {}).get('values', []))}")
        if i >= 2:
            print(f"      ...（共 {len(frames)} 个 frame，仅展示前 3 个）")
            break


run_query("形态 A：单值（instant=True → Stat 面板）", "node_load1", True)
run_query("形态 B：时间序列（instant=False → Time series）", "node_load1", False)
run_query("形态 C：多条时间序列（按 cpu 分组）",
          'rate(node_cpu_seconds_total{mode="idle"}[2m])', False)

print("\n=========== 对照：绕过 Grafana 直接问 Prometheus ===========")
q = urllib.parse.urlencode({"query": "node_load1"})
code, body = get(f"{PROM}/api/v1/query?{q}")
d = json.loads(body)
print(f"  instant: resultType={d['data']['resultType']} 条数={len(d['data']['result'])}")
for x in d["data"]["result"][:2]:
    print(f"    value={x['value']}  metric={x['metric']}")

now = int(time.time())
q = urllib.parse.urlencode({"query": "node_load1", "start": now - 900,
                            "end": now, "step": 60})
code, body = get(f"{PROM}/api/v1/query_range?{q}")
d = json.loads(body)
print(f"  range:   resultType={d['data']['resultType']} 条数={len(d['data']['result'])}")
for x in d["data"]["result"][:1]:
    print(f"    样本点数={len(x['values'])}  前3个={x['values'][:3]}")
