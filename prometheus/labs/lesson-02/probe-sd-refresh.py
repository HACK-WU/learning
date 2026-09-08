import json
import subprocess
import time
import urllib.request

BASE = "http://localhost:9096"
TARGETS = "/mnt/d/projects/learning/prometheus/labs/lesson-02/sd/targets.json"
BACKUP = "/mnt/d/projects/learning/prometheus/labs/lesson-02/sd/targets.json.bak"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def active_instances(job):
    d = get("/api/v1/targets?state=active")
    return sorted(t["labels"].get("instance", "")
                  for t in d["data"]["activeTargets"]
                  if t["labels"]["job"] == job)


print("=== 修改前 (file-sd-demo) ===")
for i in active_instances("file-sd-demo"):
    print("  " + i)

print()
print("=== 往 targets.json 追加一个新 target（app-payment-2） ===")
with open(TARGETS, encoding="utf-8") as f:
    data = json.load(f)
with open(BACKUP, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

data.append({
    "targets": ["app-payment-2:8080"],
    "labels": {"__meta_service": "payment", "__meta_env": "prod", "__meta_team": "pay"},
})
with open(TARGETS, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print("  已追加，等待 20 秒让 SD 刷新（refresh_interval=15s）")

time.sleep(20)
print("  刷新后:")
for i in active_instances("file-sd-demo"):
    print("    " + i)

print()
print("=== 删掉一个 target（app-order-2） ===")
with open(TARGETS, encoding="utf-8") as f:
    data = json.load(f)
data = [g for g in data if "app-order-2:8080" not in g.get("targets", [])]
with open(TARGETS, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print("  已删除，等待 20 秒")

time.sleep(20)
print("  刷新后:")
for i in active_instances("file-sd-demo"):
    print("    " + i)

print()
print("=== 恢复原始 targets.json ===")
import shutil
shutil.copy(BACKUP, TARGETS)
print("  已恢复")
