#!/usr/bin/env bash
cat > /mnt/d/projects/learning/prometheus/labs/lesson-12/rq.py <<'PY'
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
PY

echo "===== 停 app，切断新数据源 ====="
docker stop l12-app >/dev/null 2>&1
sleep 10

echo
echo "########## 决定性验证：range 查询对比 A（删）/ B（未删） ##########"
echo "--- A：删除了 idx=~'00000.*'（1000 条） ---"
echo -n "  A count(l12_series)          : "; python3 /mnt/d/projects/learning/prometheus/labs/lesson-12/rq.py 19510 'count(l12_series)' 10
echo -n "  A count(idx=~\"00000.*\")      : "; python3 /mnt/d/projects/learning/prometheus/labs/lesson-12/rq.py 19510 'count(l12_series{idx=~"00000.*"})' 10

echo "--- B：未删除 ---"
echo -n "  B count(l12_series)          : "; python3 /mnt/d/projects/learning/prometheus/labs/lesson-12/rq.py 19511 'count(l12_series)' 10
echo -n "  B count(idx=~\"00000.*\")      : "; python3 /mnt/d/projects/learning/prometheus/labs/lesson-12/rq.py 19511 'count(l12_series{idx=~"00000.*"})' 10

echo
echo "===== 判读 ====="
echo "若 A 的 00000.* 计数明显低于 B（如 0 vs 1000）→ 删除确实生效"
echo "若两者相同 → 删除未生效（或 staleness 仍在干扰）"
