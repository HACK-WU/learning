import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    return get("/api/v1/query?query=" + urllib.parse.quote(q))


print("=== 1) metric_relabel drop：app_debug_user_id 是否被丢弃 ===")
for job in ["metric-relabel-demo", "honor-normal"]:
    d = query('app_debug_user_id{job="%s"}' % job)
    n = len(d["data"]["result"])
    print("  job=%-22s -> %s" % (job, "有 %d 条（未被丢弃）" % n if n else "无结果（已被 drop）"))

print()
print("=== 2) metric_relabel replace：scraped_by 标签是否加上 ===")
d = query('app_build_info{job="metric-relabel-demo"}')
for r in d["data"]["result"]:
    print("  %s" % json.dumps(r["metric"], ensure_ascii=False, sort_keys=True))

print()
print("=== 3) 对照：honor-normal 的同类样本（没有 scraped_by） ===")
d = query('app_build_info{job="honor-normal"}')
for r in d["data"]["result"]:
    print("  %s" % json.dumps(r["metric"], ensure_ascii=False, sort_keys=True))

print()
print("=== 4) 各 job 抓到的样本数对比（drop 前后） ===")
d = query("scrape_samples_scraped")
for r in d["data"]["result"]:
    m = r["metric"]
    if m.get("job", "").startswith(("metric-relabel", "honor-")):
        print("  job=%-22s -> %s 样本" % (m.get("job"), r["value"][1]))

print()
print("=== 5) 服务发现发现的 target 总数 ===")
for q in ["prometheus_sd_discovered_targets", "prometheus_sd_file_mtime_seconds"]:
    d = query(q)
    for r in d["data"]["result"]:
        print("  %-36s job=%-22s -> %s"
              % (q, r["metric"].get("job", "-"), r["value"][1]))
