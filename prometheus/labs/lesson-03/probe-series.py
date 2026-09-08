import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9097"


def query(q):
    url = BASE + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def show(title, q):
    d = query(q)
    res = d["data"]["result"]
    print("=== %s ===" % title)
    print("  %s" % q)
    if d["status"] != "success":
        print("  ERROR:", d.get("error"))
        return
    if res:
        print("  -> %s  %s" % (res[0]["value"][1], json.dumps(res[0]["metric"], ensure_ascii=False)))
    else:
        print("  -> (空)")
    print()


# 1) 应用暴露的业务序列数
show("业务序列总数（应用自己暴露的）", 'count({__name__=~"app_.*"})')

# 2) 按指标名拆分
for name in ["app_requests_total", "app_build_info", "app_debug_user_id"]:
    show(name, "count(%s)" % name)

# 3) 全库序列总数（含 Prometheus 自动生成的 up/scrape_*）
show("全库序列总数", "count({__name__=~\".+\"})")

# 4) head 里的序列数（TSDB 自己数的）
show("TSDB 报告的 head 序列数", "prometheus_tsdb_head_series")

# 5) 每个指标的样本数
show("app_requests_total 的样本点数", 'count_over_time(app_requests_total[1h])')
