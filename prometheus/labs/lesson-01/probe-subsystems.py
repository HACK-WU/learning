import json
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
            print("  %-52s -> (空)" % q)
            continue
        for r in results:
            m = r["metric"]
            label = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
            print("  %-52s %-46s -> %s" % (q, label[:46], r["value"][1]))
    print()


show("scrape 健康与耗时", [
    "up",
    "scrape_duration_seconds",
    "scrape_samples_scraped",
    "scrape_samples_post_metric_relabeling",
    "scrape_series_added",
])

show("TSDB 视角：Prometheus 自己暴露的存储指标", [
    "prometheus_tsdb_head_series",
    "prometheus_tsdb_head_samples_appended_total",
    "prometheus_tsdb_head_chunks",
])

show("组件边界：各子系统的自我观测", [
    "prometheus_sd_discovered_targets",
    "prometheus_target_scrapes_exceeded_sample_limit_total",
    "prometheus_engine_query_duration_seconds_count",
])
