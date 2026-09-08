"""课6 共用探针库：查询执行 + 成本量化 + 时间序列采样。

设计原则（承接课5教训）：
1. 全部走 docker exec 在 l6-prom 容器内发请求 —— 不依赖宿主端口，避免端口冲突。
2. 解析一律用 python3，不用 jq（本机 WSL 未预装）。
3. 量化成本用「查询统计 API」，而非只看墙钟耗时 —— 这是本课核心方法论。
"""

import json
import subprocess
import time
import urllib.parse

PROM = "l6-prom"
BASE = "http://localhost:9090"


def _wget(path_with_query):
    """在 Prometheus 容器内发 GET 请求，返回响应体字符串。"""
    cmd = ["docker", "exec", PROM, "wget", "-qO-", f"{BASE}{path_with_query}"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return r.stdout


def query(expr, t=None):
    """瞬时查询，返回 data.result 列表。"""
    q = {"query": expr}
    if t is not None:
        q["time"] = t
    url = "/api/v1/query?" + urllib.parse.urlencode(q)
    out = _wget(url)
    try:
        d = json.loads(out)
    except json.JSONDecodeError:
        return None
    if d.get("status") != "success":
        return None
    return d["data"]["result"]


def query_range(expr, start, end, step):
    """区间查询，返回 data.result 列表。"""
    q = {"query": expr, "start": start, "end": end, "step": step}
    url = "/api/v1/query_range?" + urllib.parse.urlencode(q)
    out = _wget(url)
    try:
        d = json.loads(out)
    except json.JSONDecodeError:
        return None
    if d.get("status") != "success":
        return None
    return d["data"]["result"]


def app_get(path):
    """从 Prometheus 容器内访问 app 的控制端点。"""
    cmd = ["docker", "exec", PROM, "wget", "-qO-", f"http://l6-app:8080{path}"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    return r.stdout.strip()


def now():
    return time.time()


def timed(fn, *args, **kwargs):
    """执行 fn 并返回 (耗时秒, 结果)。"""
    t0 = time.perf_counter()
    r = fn(*args, **kwargs)
    return time.perf_counter() - t0, r


def count_series(expr):
    """统计表达式命中的序列数。"""
    r = query(expr)
    return len(r) if r is not None else -1


def sample_points(expr, seconds=60, every=5):
    """以固定间隔对表达式采样，返回 [(时间戳, 值或None)]。

    值为 None 表示该时刻查询无结果 —— 这是观察 staleness 的关键信号。
    """
    out = []
    for _ in range(seconds // every):
        t = now()
        r = query(expr)
        if r and len(r) > 0:
            out.append((t, float(r[0]["value"][1])))
        else:
            out.append((t, None))
        time.sleep(every)
    return out
