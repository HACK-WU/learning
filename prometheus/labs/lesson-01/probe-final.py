import json
import subprocess
import time
import urllib.parse
import urllib.request

PROM = "http://localhost:9095"


def query(q):
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def show(title, qs):
    print("=== %s ===" % title)
    for q in qs:
        d = query(q)
        results = d["data"]["result"]
        if not results:
            print("  %-46s -> (空)" % q)
            continue
        for r in results:
            m = r["metric"]
            label = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
            print("  %-46s %-44s -> %s" % (q, label[:44], r["value"][1]))
    print()


print("### 步骤 1：查看 targets ###")
d = json.loads(urllib.request.urlopen(PROM + "/api/v1/targets?state=active", timeout=10).read())
for t in d["data"]["activeTargets"]:
    print("  job=%-12s url=%-40s health=%s" % (t["labels"]["job"], t["scrapeUrl"], t["health"]))

print()
show("步骤 2：up 指标", ["up"])
show("步骤 3：业务计数器", ["demo_http_requests_total"])
show("步骤 4：scrape 过程指标", [
    "scrape_duration_seconds",
    "scrape_samples_scraped",
    "scrape_series_added",
])
show("步骤 5：TSDB head（自监控已开启）", [
    "prometheus_tsdb_head_series",
    "prometheus_tsdb_head_samples_appended_total",
])
