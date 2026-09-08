set +x
PROM=http://localhost:9094

echo "########## 规则求值拿到的是'上次抓取到的数据' ##########"
echo
echo "原理：规则求值时，Prometheus 用的是 TSDB 里已有的样本，"
echo "      而最新样本的时间戳 = 上一次抓取的时刻，不是'此刻'。"
echo

echo "=== 1) 抓取间隔与求值间隔配置 ==="
curl -s "$PROM/api/v1/status/config" | python3 -c "
import sys, re, json
d = json.load(sys.stdin)['data']['yaml']
for line in d.splitlines():
    if 'interval' in line and ('scrape' in line or 'evaluation' in line):
        print('  ' + line.strip())
"

echo
echo "=== 2) 对比：源指标最新样本时间戳 vs 当前时刻 ==="
python3 - << 'PYEOF'
import json, time, urllib.request

BASE = "http://localhost:9094"

def q(expr):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]

import urllib.parse

now = time.time()
res = q("app_requests_total")
if res:
    ts = float(res[0]["value"][1 - 1 + 1 - 1]) if False else float(res[0]["value"][0])
    print("  当前系统时刻:      %.3f" % now)
    print("  app_requests_total 最新样本时间戳: %.3f" % ts)
    print("  -> 源数据滞后: %.2f 秒（这就是抓取间隔造成的）" % (now - ts))
else:
    print("  未查到 app_requests_total")

# recording rule 产物的时间戳
res = q("job:app_requests:rate1m")
if res:
    ts = float(res[0]["value"][0])
    print()
    print("  job:app_requests:rate1m（recording rule 产物）时间戳: %.3f" % ts)
    print("  -> 该时间戳是'求值时刻'，不是源数据的抓取时刻")
PYEOF

echo
echo "=== 3) 多次采样：源指标时间戳的跳变规律（应每 5 秒跳一次） ==="
for i in $(seq 1 10); do
  python3 - << 'PYEOF'
import json, time, urllib.parse, urllib.request
BASE = "http://localhost:9094"
def q(expr):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]
now = time.time()
res = q("app_requests_total")
if res:
    ts = float(res[0]["value"][0])
    print("  查询时刻=%.2f  样本时间戳=%.2f  滞后=%.2fs" % (now, ts, now - ts))
PYEOF
  sleep 2
done
