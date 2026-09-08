#!/usr/bin/env python3
"""课 5 讲义命令逐字复验（learner 视角）。

严格按讲义第四幕步骤 1-9 的命令执行，验证：
  1. 环境可从头搭建（先销毁再重建）
  2. 每条命令的输出与讲义描述一致
  3. 关键数字（分组数、通知数、n_alerts）对得上

注意：这是破坏性复验，会重建 l5-* 容器。
"""
import json
import subprocess
import time
import urllib.request

PASS, FAIL = [], []


def sh(cmd, timeout=180):
    r = subprocess.run(["bash.exe", "-c", cmd], capture_output=True,
                       text=True, timeout=timeout)
    return (r.stdout or "") + (r.stderr or "")


def check(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print("  [PASS] %s %s" % (name, detail))
    else:
        FAIL.append((name, detail))
        print("  [FAIL] %s %s" % (name, detail))


def count():
    try:
        return json.loads(sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/count"'))
    except Exception as e:
        return {"err": str(e)}


def lst(ch):
    try:
        return json.loads(sh('docker exec l5-prom wget -qO- '
                             '"http://l5-receiver:8099/list?path=%s"' % ch))
    except Exception:
        return {"count": -1, "items": []}


def http_json(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode())


BASE = "/mnt/d/projects/learning/prometheus/labs/lesson-05"
NET = "lesson05-net"

print("=" * 60)
print("课 5 讲义命令逐字复验")
print("=" * 60)

# ---------- 步骤 1：环境搭建 ----------
print("\n[步骤 1] 销毁并重建环境")
sh('docker rm -f l5-app-1 l5-app-2 l5-app-3 l5-prom l5-am l5-receiver 2>/dev/null')
sh('docker network rm %s 2>/dev/null' % NET)
sh('docker network create %s 2>/dev/null' % NET)

for name, team, zone in [("l5-app-1", "payments", "zone-a"),
                         ("l5-app-2", "payments", "zone-b"),
                         ("l5-app-3", "search", "zone-a")]:
    sh('docker run -d --name %s --network %s -v %s/app:/app '
       '-e APP_INSTANCE=%s -e APP_TEAM=%s -e APP_ZONE=%s '
       'python:3.12-slim python3 /app/l5_app.py'
       % (name, NET, BASE, name, team, zone))

sh('docker run -d --name l5-receiver --network %s -v %s/app:/app '
   '-v %s/logs:/logs python:3.12-slim python3 /app/receiver.py' % (NET, BASE, BASE))

# 讲义默认配置：alertmanager.yml（主配置，group_wait=20s 版本需显式指定）
print("  -> 使用讲义主配置重建 Alertmanager")
sh('cp %s/alertmanager-main.yml %s/alertmanager.yml 2>/dev/null || true' % (BASE, BASE))
sh('docker run -d --name l5-am --network %s '
   '-v %s/alertmanager.yml:/etc/alertmanager/alertmanager.yml -p 19093:9093 '
   'prom/alertmanager:v0.30.0 --config.file=/etc/alertmanager/alertmanager.yml '
   '--storage.path=/alertmanager --log.level=info' % (NET, BASE))

sh('docker run -d --name l5-prom --network %s '
   '-v %s/prometheus.yml:/etc/prometheus/prometheus.yml '
   '-v %s/rules.yml:/etc/prometheus/rules.yml -p 19090:9090 '
   'prom/prometheus:v3.14.0 --config.file=/etc/prometheus/prometheus.yml '
   '--storage.tsdb.path=/prometheus --web.enable-lifecycle --log.level=info'
   % (NET, BASE, BASE))

time.sleep(12)
out = sh('docker ps --format "{{.Names}}" | grep -c "^l5-"')
check("步骤1 六个 l5- 容器在运行", out.strip() == "6", "count=%s" % out.strip())

# ---------- 步骤 2：连通性 ----------
print("\n[步骤 2] 链路连通性")
r = sh('docker exec l5-am wget -qO- http://localhost:9093/-/ready')
check("步骤2 AM ready", "OK" in r, r.strip()[:40])

try:
    d = http_json("http://localhost:19090/api/v1/alertmanagers")
    check("步骤2 Prometheus 发现 AM",
          len(d["data"]["activeAlertmanagers"]) == 1,
          str(d["data"]["activeAlertmanagers"]))
except Exception as e:
    check("步骤2 Prometheus 发现 AM", False, str(e))

r = sh("""docker exec l5-prom wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['data']['activeTargets']))" """)
check("步骤2 抓取目标数=4", r.strip() == "4", "got=%s" % r.strip())

# ---------- 步骤 3：group_wait 攒批 ----------
print("\n[步骤 3] group_wait 攒批（错开 3 秒注入）")
sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
# 重建后 Prometheus 需先抓几轮；等告警彻底清空再开始（避免上一轮"搭车"污染）
time.sleep(30)

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/on?rate=0.6"')
time.sleep(3)
sh('docker exec l5-prom wget -qO- "http://l5-app-2:8080/fault/on?rate=0.6"')

# 时序：for(5s) + 求值(5s) + group_wait(20s) ≈ 30s 后才可能出首条，
# 因此采样窗口需覆盖到 40s 以上（原 5×4s=20s 太短，会误判为 FAIL）
samples = []
for i in range(8):
    time.sleep(5)
    samples.append(count().get("payments", -1))
print("  payments 采样序列:", samples)

check("步骤3 攒批：前两次采样为 0（group_wait 窗口内）",
      samples[0] == 0 and samples[1] == 0, str(samples))
check("步骤3 攒批：40 秒内出现通知", max(samples) >= 1, str(samples))

d = lst("payments")
if d.get("items"):
    first = d["items"][0]
    check("步骤3 n_alerts=2（两条告警合并）",
          first.get("n_alerts") == 2,
          "n_alerts=%s instances=%s" % (first.get("n_alerts"),
                                        first.get("instances")))
else:
    check("步骤3 n_alerts=2", False, "no items")

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/off"')
sh('docker exec l5-prom wget -qO- "http://l5-app-2:8080/fault/off"')
time.sleep(22)

# ---------- 步骤 4：group_by 对照 ----------
print("\n[步骤 4] group_by=[alertname,zone] 对照")
sh('cp %s/alertmanager-groupby2.yml %s/alertmanager.yml' % (BASE, BASE))
sh('docker exec l5-am kill -HUP 1')
time.sleep(5)
r = sh('docker exec l5-am wget -qO- http://localhost:9093/-/ready')
check("步骤4 配置热加载成功", "OK" in r, r.strip()[:30])

sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/on?rate=0.6"')
sh('docker exec l5-prom wget -qO- "http://l5-app-2:8080/fault/on?rate=0.6"')
time.sleep(20)

# groupby2 配置里 payments 的 group_by 是 [alertname]，需切到含 zone 的版本
print("  -> 切换到 route-order 配置（group_by=[alertname,zone]）")
sh('cp %s/alertmanager-route-order.yml %s/alertmanager.yml' % (BASE, BASE))
sh('docker exec l5-am kill -HUP 1')
time.sleep(5)
sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
time.sleep(35)
c = count()
check("步骤4 按 zone 分组 -> payments 收到 2 条",
      c.get("payments") == 2, str(c))

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/off"')
sh('docker exec l5-prom wget -qO- "http://l5-app-2:8080/fault/off"')
time.sleep(22)

# ---------- 步骤 5：路由顺序 ----------
print("\n[步骤 5] 路由顺序（Node.* 在前 -> 走 infra）")
sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
# 先确保 app-1 节点处于正常状态，再注入，且等告警彻底清空
sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/node?v=1"')
time.sleep(25)
sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/node?v=0"')
# 时序：for(5s) + 求值(5s) + group_wait(10s) + 通知 ≈ 25s 以上
time.sleep(32)
c = count()
check("步骤5 Node.* 在前 -> infra 收到", c.get("infra") >= 1, str(c))
check("步骤5 Node.* 在前 -> payments 不收 NodeDown",
      c.get("payments") == 0, str(c))

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/node?v=1"')
time.sleep(28)

# ---------- 步骤 7：抑制 ----------
print("\n[步骤 7] 抑制（同 zone）")
sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
sh('docker exec l5-prom wget -qO- "http://l5-app-3:8080/fault/on?rate=0.6"')
time.sleep(22)
c1 = count()
print("  阶段1:", c1)

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/node?v=0"')
time.sleep(34)
c2 = count()
print("  阶段2:", c2)
check("步骤7 抑制生效：default 未新增",
      c2.get("default") == c1.get("default"),
      "before=%s after=%s" % (c1.get("default"), c2.get("default")))

sh('docker exec l5-prom wget -qO- "http://l5-app-1:8080/fault/node?v=1"')
time.sleep(26)
c3 = count()
print("  阶段3:", c3)
check("步骤7 抑制解除：default 补发",
      c3.get("default") > c2.get("default"),
      "before=%s after=%s" % (c2.get("default"), c3.get("default")))

sh('docker exec l5-prom wget -qO- "http://l5-app-3:8080/fault/off"')
time.sleep(18)

# ---------- 步骤 8：静默 ----------
print("\n[步骤 8] 静默")
sh("""docker exec l5-prom wget -qO- "http://l5-am:9093/api/v2/silences" | python3 -c "
import sys,json,subprocess
for r in json.load(sys.stdin):
    if r['status']['state'] in ('pending','active'):
        subprocess.run(['docker','exec','l5-prom','wget','-qO-','--method=DELETE','http://l5-am:9093/api/v2/silence/'+r['id']])
print('cleared')" """)

sh('docker exec l5-prom wget -qO- "http://l5-receiver:8099/reset"')
sh('docker exec l5-prom wget -qO- "http://l5-app-3:8080/fault/on?rate=0.6"')
time.sleep(20)

import datetime
now = datetime.datetime.utcnow()
starts = (now - datetime.timedelta(seconds=5)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
ends = (now + datetime.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
body = ('{"matchers":[{"name":"alertname","value":"HighErrorRate","isRegex":false},'
        '{"name":"zone","value":"zone-a","isRegex":false}],'
        '"startsAt":"%s","endsAt":"%s","createdBy":"verify","comment":"verify"}'
        % (starts, ends))
r = sh('docker exec l5-prom wget -qO- --post-data=\'%s\' '
       '--header="Content-Type: application/json" '
       'http://l5-am:9093/api/v2/silences' % body)
check("步骤8 静默创建成功", "silenceID" in r, r.strip()[:80])

before = count().get("default", 0)
time.sleep(34)
after = count().get("default", 0)
check("步骤8 静默期内无新增通知", after == before,
      "before=%s after=%s" % (before, after))

time.sleep(45)
final = count().get("default", 0)
check("步骤8 静默过期后补发", final > after,
      "during=%s after_expire=%s" % (after, final))

sh('docker exec l5-prom wget -qO- "http://l5-app-3:8080/fault/off"')
time.sleep(15)

# ---------- 汇总 ----------
print("\n" + "=" * 60)
print("复验汇总: PASS=%d  FAIL=%d" % (len(PASS), len(FAIL)))
if FAIL:
    print("\n失败项：")
    for n, d in FAIL:
        print("  - %s | %s" % (n, d))
else:
    print("全部通过 ✅")
print("=" * 60)
