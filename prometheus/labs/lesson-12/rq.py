import sys, json, time, urllib.parse, urllib.request
# range query 查历史，绕开 staleness（instant query 在 target 停后返回空）
PORT, EXPR = sys.argv[1], sys.argv[2]
MINS = int(sys.argv[3]) if len(sys.argv) > 3 else 10
now = int(time.time()); start = now - MINS*60
url = f"http://localhost:{PORT}/api/v1/query_range?" + urllib.parse.urlencode(
    {"query": EXPR, "start": start, "end": now, "step": 60})
try:
    with urllib.request.urlopen(url, timeout=20) as r:
        d = json.load(r)
    res = d.get("data", {}).get("result", [])
    if not res:
        print("empty")
    else:
        vals = res[0]["values"]
        nz = [v for v in vals if v[1] not in ("NaN",)]
        print(f"series={len(res)} points={len(vals)} last={vals[-1][1] if vals else '-'}")
except Exception as e:
    print("ERR", e)
