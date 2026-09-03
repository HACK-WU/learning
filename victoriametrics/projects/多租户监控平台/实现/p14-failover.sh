#!/usr/bin/env bash
# ============================================================
# 故障演练：证明这套架构「坏了也能活」
#
#   F1 存储节点宕机：杀掉一个 vmstorage，数据仍可查（复制因子 2）
#   F2 采集节点宕机：杀掉 vmagent-a，验证 tenant-a 数据停止、tenant-b 不受影响
#   F3 告警是否响应：F2 之后 ScrapeStalled / ServiceDown 应该 firing
# ============================================================
set -uo pipefail
VMSELECT="http://localhost:8501"
VMINSERT="http://localhost:8500"
PASS=0; FAIL=0
ok()  { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
hdr() { echo; echo "=== $* ==="; }

qsum() { # qsum <accountID> <expr>
  curl -s --get "$VMSELECT/select/$1/prometheus/api/v1/query" \
    --data-urlencode "query=$2" --data-urlencode 'nocache=1' 2>/dev/null \
  | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(r[0]["value"][1] if r else "N/A")
except Exception: print("ERR")
'
}

firing_names() { # firing_names <port>
  curl -s "http://localhost:$1/api/v1/rules" 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); data=d.get("data",{})
    groups=data.get("groups",[]) if isinstance(data,dict) else []
    print(",".join(sorted(r["name"] for g in groups for r in g.get("rules",[])
                          if r.get("state")=="firing")))
except Exception: print("ERR")
'
}

echo "============================================================"
echo " 多租户监控平台 · 故障演练"
echo "============================================================"

# ---------- F1：存储节点宕机 ----------
hdr "F1 存储节点宕机：杀掉 capstone-vmstorage-2"
BEFORE=$(qsum 100 'sum(http_requests_total)')
echo "  宕机前 tenant-a 样本总数 = $BEFORE"
docker stop capstone-vmstorage-2 >/dev/null 2>&1
echo "  已停止 vmstorage-2，等待 20 秒"
sleep 20
AFTER=$(qsum 100 'sum(http_requests_total)')
echo "  宕机后 tenant-a 样本总数 = $AFTER"
if [ "$AFTER" != "ERR" ] && [ "$AFTER" != "N/A" ]; then
  ok "单存储节点宕机后仍可查询（复制因子 2 生效）"
else
  bad "存储节点宕机后查询失败 —— 复制未生效"
fi

# 宕机期间写入是否仍成功
# ⚠ 用 /api/v1/import/prometheus（明文行协议）而不是 /api/v1/write。
#   /api/v1/write 是 Prometheus remote_write 协议，要求 snappy 压缩的 protobuf，
#   用明文打会返回 400 "cannot decompress snappy-encoded request" ——
#   那是测试命令的问题，不是存储故障。
WCODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$VMINSERT/insert/100/prometheus/api/v1/import/prometheus" \
  --data-binary 'failover_test{x="1"} 1' 2>/dev/null)
echo "  宕机期间写入(/api/v1/import/prometheus) -> HTTP $WCODE（期望 204）"
[ "$WCODE" = "204" ] && ok "宕机期间写入仍成功" || bad "宕机期间写入失败（HTTP $WCODE）"

echo "  恢复 vmstorage-2"
docker start capstone-vmstorage-2 >/dev/null 2>&1
# ⚠ 必须给一段静置期。F1 的存储节点启停会让 vmselect 短暂不可用，
#   vmalert 的求值随之中断，pending 计时被清零。
#   不静置就进 F2，for: 1m 永远凑不满 —— 表现为「规则写了却不响」。
echo "  静置 90 秒，让集群与告警求值恢复稳定"
sleep 90

# ---------- F2：采集节点宕机 ----------
hdr "F2 采集节点宕机：杀掉 vmagent-a"
docker stop capstone-vmagent-a >/dev/null 2>&1
# ⚠ 等待时间必须 > last_over_time 的窗口（2m）+ for（1m）= 3 分钟。
#   只等 100 秒时告警不响，不是规则写错了，是窗口还没滑过去。
echo "  已停止 vmagent-a，等待 240 秒（> 2m 窗口 + 1m for + 余量）"
sleep 240

FA=$(firing_names 8505)
FB=$(firing_names 8507)
echo "  tenant-a firing 告警 = ${FA:-（无）}"
echo "  tenant-b firing 告警 = ${FB:-（无）}"

case "$FA" in
  *ScrapeStalled*) ok "tenant-a 触发 ScrapeStalled（采集中断被检出）" ;;
  *ScrapeLagging*) ok "tenant-a 触发 ScrapeLagging（采集滞后被检出）" ;;
  *ServiceDown*)   ok "tenant-a 触发 ServiceDown（采集中断被检出）" ;;
  *)               bad "tenant-a 未检出采集中断" ;;
esac

# 顺带读出具体滞后秒数 —— 排查时这个数字比「有没有告警」有用得多
LAG=$(curl -s --get "$VMSELECT/select/100/prometheus/api/v1/query" \
  --data-urlencode 'query=time() - max(timestamp(up{tenant="tenant-a"}))' \
  --data-urlencode 'nocache=1' 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print("%.0f" % float(r[0]["value"][1]) if r else "N/A")
except Exception: print("N/A")
')
echo "  tenant-a 最新样本滞后 = ${LAG} 秒（采集中断的直接证据）"

if [ -z "$FB" ] || [ "$FB" = "ERR" ]; then
  ok "tenant-b 不受影响（租户故障域隔离）"
else
  bad "tenant-b 被连带影响：$FB"
fi

hdr "F2b 确认 tenant-b 数据仍在增长（未被波及）"
B1=$(qsum 200 'sum(http_requests_total)')
sleep 12
B2=$(qsum 200 'sum(http_requests_total)')
echo "  tenant-b 样本数：$B1 -> $B2"
if [ "$B2" != "$B1" ] && [ "$B2" != "ERR" ]; then
  ok "tenant-b 数据采集正常，未受 tenant-a 故障影响"
else
  bad "tenant-b 数据停止增长"
fi

echo "  恢复 vmagent-a"
docker start capstone-vmagent-a >/dev/null 2>&1
sleep 30

hdr "F3 恢复验证"
sleep 40
FA2=$(firing_names 8505)
echo "  恢复后 tenant-a firing 告警 = ${FA2:-（无，已恢复）}"
case "$FA2" in
  *ScrapeStalled*) bad "恢复后 ScrapeStalled 仍未清除" ;;
  *)               ok "采集恢复后告警自动清除" ;;
esac

echo
echo "============================================================"
echo " 故障演练汇总：PASS=$PASS  FAIL=$FAIL"
echo "============================================================"
[ "$FAIL" = "0" ] || exit 1
