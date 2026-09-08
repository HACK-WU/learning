import json
import urllib.request

BASE = "http://localhost:9095"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


print("=== /api/v1/targets?state=active ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    labels = t["labels"]
    print(
        "job=%-14s url=%-42s health=%-6s err=%s"
        % (
            labels.get("job"),
            t["scrapeUrl"],
            t["health"],
            (t.get("lastError") or "")[:50],
        )
    )

print()
print("=== up ===")
d = get("/api/v1/query?query=up")
for r in d["data"]["result"]:
    m = r["metric"]
    print("job=%-12s instance=%-24s -> %s" % (m.get("job"), m.get("instance"), r["value"][1]))

print()
print("=== demo_http_requests_total ===")
d = get("/api/v1/query?query=demo_http_requests_total")
for r in d["data"]["result"]:
    m = r["metric"]
    print("endpoint=%-12s job=%-10s instance=%-20s -> %s"
          % (m.get("endpoint"), m.get("job"), m.get("instance"), r["value"][1]))
