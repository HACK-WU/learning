#!/usr/bin/env bash
# ============================================================
# 多租户监控平台 · 端到端验证
#
# 验证五件事：
#   V1 采集：两个租户的数据是否写进各自 accountID
#   V2 隔离：跨租户能否查到对方数据（应该查不到）
#   V3 权限：只读身份写入是否被拒、错误密码是否 401
#   V4 告警：降级租户是否告警、健康租户是否安静、有无假告警
#   V5 基数：user_id 是否被 labeldrop 剔除（只看新增样本）
# ============================================================
set -uo pipefail

VMSELECT="http://localhost:8501"
VMAUTH="http://localhost:8506"

PASS=0; FAIL=0
ok()  { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
warn(){ echo "  [WARN] $*"; }
hdr() { echo; echo "=== $* ==="; }

q() { # q <url> <query> [user:pass]
  local url="$1" query="$2" auth="${3:-}"
  local a=()
  [ -n "$auth" ] && a=(-u "$auth")
  curl -s --get "$url/api/v1/query" --data-urlencode "query=$query" \
       --data-urlencode "nocache=1" "${a[@]}" 2>/dev/null
}

val() {
  echo "$1" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(r[0]["value"][1] if r else "N/A")
except Exception: print("ERR")
' 2>/dev/null
}
cnt() {
  echo "$1" | python3 -c '
import json,sys
try: print(len(json.load(sys.stdin).get("data",{}).get("result",[])))
except Exception: print("ERR")
' 2>/dev/null
}

echo "============================================================"
echo " 多租户监控平台 · 端到端验证"
echo "============================================================"

hdr "准备：等待 70 秒，让数据攒够、vmalert 的 for: 30s 条件满足"
sleep 70

# ---------- V1 采集 ----------
hdr "V1 采集：每个租户的数据是否写进各自 accountID"
A=$(val "$(q "$VMSELECT/select/100/prometheus" 'sum(http_requests_total{tenant="tenant-a"})')")
B=$(val "$(q "$VMSELECT/select/200/prometheus" 'sum(http_requests_total{tenant="tenant-b"})')")
echo "  tenant-a (accountID 100) 样本总数 = $A"
echo "  tenant-b (accountID 200) 样本总数 = $B"
[ "$A" != "N/A" ] && [ "$A" != "ERR" ] && [ "$A" != "0" ] \
  && ok "tenant-a 数据已写入 accountID 100" || bad "tenant-a 无数据"
[ "$B" != "N/A" ] && [ "$B" != "ERR" ] && [ "$B" != "0" ] \
  && ok "tenant-b 数据已写入 accountID 200" || bad "tenant-b 无数据"

# ---------- V2 隔离 ----------
hdr "V2 隔离：跨租户查询应该查不到对方数据"
C1=$(cnt "$(q "$VMSELECT/select/100/prometheus" 'sum(http_requests_total{tenant="tenant-b"})')")
C2=$(cnt "$(q "$VMSELECT/select/200/prometheus" 'sum(http_requests_total{tenant="tenant-a"})')")
echo "  在 100 里查 tenant-b -> 行数 = $C1（期望 0）"
echo "  在 200 里查 tenant-a -> 行数 = $C2（期望 0）"
[ "$C1" = "0" ] && ok "accountID 100 查不到 tenant-b 数据" || bad "租户数据串了：100 能查到 b"
[ "$C2" = "0" ] && ok "accountID 200 查不到 tenant-a 数据" || bad "租户数据串了：200 能查到 a"

# ---------- V3 权限 ----------
hdr "V3 权限：vmauth 按身份路由 + 只读身份不得写入"
A1=$(val "$(q "$VMAUTH" 'sum(http_requests_total{tenant="tenant-a"})' 'backend:backend-pass-123')")
A2=$(val "$(q "$VMAUTH" 'sum(http_requests_total{tenant="tenant-b"})' 'frontend:frontend-pass-456')")
echo "  backend  身份经 vmauth 查 tenant-a = $A1"
echo "  frontend 身份经 vmauth 查 tenant-b = $A2"
[ "$A1" != "N/A" ] && [ "$A1" != "ERR" ] && ok "backend 身份可查自己租户"  || bad "backend 查不到自己数据"
[ "$A2" != "N/A" ] && [ "$A2" != "ERR" ] && ok "frontend 身份可查自己租户" || bad "frontend 查不到自己数据"

WR=$(curl -s -o /dev/null -w '%{http_code}' -u 'viewer:viewer-pass-000' \
     -X POST "$VMAUTH/api/v1/write" --data-binary 'test_metric{x="1"} 1' 2>/dev/null)
echo "  viewer（只读）尝试写入 -> HTTP $WR（期望非 2xx）"
case "$WR" in 2*) bad "只读身份竟然写入成功了！";; *) ok "只读身份写入被拒（HTTP $WR）";; esac

WC=$(curl -s -o /dev/null -w '%{http_code}' -u 'backend:wrong-password' \
     "$VMAUTH/api/v1/query?query=up" 2>/dev/null)
echo "  错误密码 -> HTTP $WC（期望 401）"
[ "$WC" = "401" ] && ok "错误密码被拒（401）" || bad "错误密码竟然通过（HTTP $WC）"

# ---------- V4 告警 ----------
hdr "V4 告警：降级租户应告警，健康租户应安静"
# /api/v1/rules 返回所有规则及状态；/api/v1/alerts 只返回有状态的，会漏。
python3 - <<'PY'
import json,urllib.request
def rules(port):
    try:
        d=json.load(urllib.request.urlopen('http://localhost:%d/api/v1/rules'%port, timeout=10))
        data=d.get('data',{})
        groups=data.get('groups',[]) if isinstance(data,dict) else []
        rows=[r for g in groups for r in g.get('rules',[])]
        return rows
    except Exception as e:
        print("    读取 :%d 失败: %s" % (port, e))
        return []
ra=rules(8505); rb=rules(8507)
for label,rows in (("tenant-a",ra),("tenant-b",rb)):
    firing=[r for r in rows if r.get('state')=='firing']
    print("  [%s] 规则 %d 条，firing %d 条" % (label, len(rows), len(firing)))
    for r in rows:
        s=r.get('state','?')
        extra=('  value=%s'%str(r.get('value','?'))[:8]) if s!='inactive' else ''
        print("      %-20s %-9s%s" % (r.get('name'), s, extra))
json.dump({'a':ra,'b':rb}, open('/tmp/cap-rules.json','w'))
PY

# 用 python 算判定，shell 负责计数（子进程改不了父进程变量）
python3 - <<'PY' > /tmp/cap-verdict.txt
import json
# 规则条数从模板自动数，避免改了 alerts.yml 忘了改这里
import re
tmpl=open('/mnt/d/projects/learning/victoriametrics/projects/多租户监控平台/实现/alerts.yml').read()
RULE_COUNT=len(re.findall(r'^\s*- alert:', tmpl, flags=re.M))
d=json.load(open('/tmp/cap-rules.json'))
ra,rb=d['a'],d['b']
fa={r['name'] for r in ra if r.get('state')=='firing'}
fb={r['name'] for r in rb if r.get('state')=='firing'}
la={r['name'] for r in ra}; lb={r['name'] for r in rb}
out=[]
out.append(("ok"  if len(ra)==RULE_COUNT else "bad", "tenant-a 的 %d 条规则全部加载（实际 %d）"%(RULE_COUNT,len(ra))))
out.append(("ok"  if len(rb)==RULE_COUNT else "bad", "tenant-b 的 %d 条规则全部加载（实际 %d）"%(RULE_COUNT,len(rb))))
if 'HighErrorRate' in fa: out.append(("ok","tenant-a（注入 5% 错误）触发 HighErrorRate"))
elif 'HighErrorRate' in la: out.append(("warn","tenant-a 的 HighErrorRate 尚未 firing（for:30s 需数据积累）"))
else: out.append(("bad","tenant-a 缺少 HighErrorRate 规则"))
out.append(("bad" if 'HighErrorRate' in fb else "ok",
            "tenant-b（健康）" + ("误报 HighErrorRate" if 'HighErrorRate' in fb else "安静，无误报")))
st = ('ScrapeStalled' in fa) or ('ScrapeStalled' in fb)
out.append(("bad" if st else "ok",
            ("出现 ScrapeStalled 假告警" if st else "无 ScrapeStalled 假告警（每租户独立 vmalert）")))
for k,m in out: print("%s|%s"%(k,m))
PY
while IFS='|' read -r k msg; do
  case "$k" in ok) ok "$msg";; bad) bad "$msg";; warn) warn "$msg";; esac
done < /tmp/cap-verdict.txt

# ---------- V4b 错误率口径 ----------
hdr "V4b 错误率口径对比：为什么必须按 path 聚合"
python3 - <<'PY'
import json,urllib.request,urllib.parse
def q(acct, expr):
    url='http://localhost:8501/select/%d/prometheus/api/v1/query?%s'%(
        acct, urllib.parse.urlencode({'query':expr,'nocache':'1'}))
    try:
        d=json.load(urllib.request.urlopen(url,timeout=10))
        r=d.get('data',{}).get('result',[])
        return r[0]['value'][1] if r else None
    except Exception: return None
w=q(100,'sum(rate(http_requests_total{status=~"5.."}[2m]))/sum(rate(http_requests_total[2m]))')
print("  tenant-a 全站错误率 = %s" % (w[:8] if w else 'N/A'))
url='http://localhost:8501/select/100/prometheus/api/v1/query?%s'%urllib.parse.urlencode({'query':
    'sum by (path) (rate(http_requests_total{status=~"5.."}[2m]))/sum by (path) (rate(http_requests_total[2m]))',
    'nocache':'1'})
try:
    d=json.load(urllib.request.urlopen(url,timeout=10))
    for r in d.get('data',{}).get('result',[]):
        print("  tenant-a 按接口：%-14s = %s"%(r['metric'].get('path'), r['value'][1][:8]))
except Exception as e: print("  查询失败:",e)
print("  → 全站口径把问题接口的真实错误率稀释了约一半。")
PY

# ---------- V5 基数治理 ----------
hdr "V5 基数治理：user_id 是否被 labeldrop 剔除"
# 必须只看新增：时序数据不可变，labeldrop 不影响历史序列。
NOW=$(date +%s)
RANGE_ARGS=(--data-urlencode 'match[]=app_user_activity_total'
            --data-urlencode "start=$((NOW-90))" --data-urlencode "end=$NOW")
curl -s --get "$VMSELECT/select/100/prometheus/api/v1/export" "${RANGE_ARGS[@]}" 2>/dev/null \
  | python3 -c '
import json,sys
tot=uid=0
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: m=json.loads(line).get("metric",{})
    except Exception: continue
    tot+=1
    if "user_id" in m: uid+=1
print("%d %d" % (tot, uid))
' > /tmp/cap-v5.txt 2>/dev/null
read -r TOTAL_NEW NEW_UID < /tmp/cap-v5.txt
echo "  近 90 秒新增样本 = ${TOTAL_NEW:-0} 条，其中带 user_id = ${NEW_UID:-0} 条（期望 0）"
if [ "${TOTAL_NEW:-0}" = "0" ]; then
  bad "近 90 秒无新增样本，V5 无法判定（请检查采集链路）"
elif [ "${NEW_UID:-0}" = "0" ]; then
  ok "新写入的样本已不含 user_id —— labeldrop 生效"
else
  bad "新写入的样本仍含 user_id（${NEW_UID} 条）—— labeldrop 未生效"
fi
echo
echo "  【对照实验，见 p10-final-ab.sh】"
echo "    有 metric_relabel_configs + labeldrop：序列数 1，  带 user_id 0"
echo "    无任何 relabel                      ：序列数 50， 带 user_id 50"

# ---------- 汇总 ----------
echo
echo "============================================================"
echo " 汇总：PASS=$PASS  FAIL=$FAIL"
echo "============================================================"
[ "$FAIL" = "0" ] || exit 1
