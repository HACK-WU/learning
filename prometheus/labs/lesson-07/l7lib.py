#!/usr/bin/env python3
"""课 7 通用探针库：封装 Prometheus / receiver / VM 的访问。"""
import json
import time
import urllib.parse
import urllib.request

PROM = "http://localhost:19100"
RECV = "http://localhost:19099"
VM = "http://localhost:19101"


def _get(url, timeout=60):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _post(url, data, timeout=60):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def query(q, at=None, host=None):
    base = host or PROM
    url = f"{base}/api/v1/query?query={urllib.parse.quote(q)}"
    if at is not None:
        url += f"&time={at}"
    return _get(url)


def query_range(q, start, end, step, host=None):
    base = host or PROM
    url = (f"{base}/api/v1/query_range?query={urllib.parse.quote(q)}"
           f"&start={start}&end={end}&step={step}")
    return _get(url)


def qnum(q, at=None, host=None):
    """返回单个数值；无数据返回 None。"""
    try:
        d = query(q, at=at, host=host)["data"]["result"]
        if not d:
            return None
        return float(d[0]["value"][1])
    except Exception:
        return None


def qcount(q, at=None, host=None):
    """返回结果序列条数。"""
    try:
        return len(query(q, at=at, host=host)["data"]["result"])
    except Exception:
        return 0


def qpoints(q, start, end, step, host=None):
    """返回区间查询的总点数。"""
    try:
        res = query_range(q, start, end, step, host=host)["data"]["result"]
        return sum(len(s["values"]) for s in res), len(res)
    except Exception:
        return 0, 0


def qseries(q, at=None, host=None):
    """返回原始 result 列表。"""
    try:
        return query(q, at=at, host=host)["data"]["result"]
    except Exception:
        return []


def recv_mode(m):
    return _get(f"{RECV}/mode/{m}", timeout=10)


def recv_stats():
    return _get(f"{RECV}/stats", timeout=10)


def recv_reset():
    return _get(f"{RECV}/reset", timeout=10)


def post(url, data, timeout=60):
    return _post(url, data, timeout=timeout)


def now():
    return time.time()


def timing(fn, n=5, warmup=1):
    """跑 n 次取中位数与极值，用于抵消本机噪声。"""
    for _ in range(warmup):
        fn()
    xs = []
    for _ in range(n):
        t0 = time.time()
        fn()
        xs.append((time.time() - t0) * 1000)
    xs.sort()
    return {
        "min": xs[0],
        "med": xs[len(xs) // 2],
        "max": xs[-1],
        "n": n,
    }


def pct(a, b):
    """a 相对 b 的变化倍数。"""
    if b == 0:
        return float("inf") if a else 0.0
    return a / b
