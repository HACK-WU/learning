#!/bin/bash
# 验证：vmauth 负载均衡到不同 vmselect，结果会不会不一致？
# 现象：同一条查询，backend/frontend 返回 5，viewer 返回 10
# 猜想：vmauth 在多个 url_prefix 间负载均衡，而它们的 dedup 配置不同
set -u
Q='count_over_time(l10_vc_value[1h])'

echo "=============================================="
echo " X1 后端 vmselect 的 dedup 配置"
echo "=============================================="
for c in vmselect-learn vmsel-dedup vmsel-d5; do
  printf "    %-16s " "$c"
  docker inspect "$c" --format '{{range .Args}}{{.}} {{end}}' 2>&1 | tr '\n' ' '
  echo
done

echo
echo "=============================================="
echo " X2 直连各 vmselect 查同一个查询"
echo "=============================================="
for p in 8481 8487 8489; do
  printf "    port %s: " "$p"
  curl -s --max-time 20 --data-urlencode "query=$Q" \
    "http://localhost:$p/select/100/prometheus/api/v1/query" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null
done
echo "     8481=无dedup  8487=dedup30s  8489=dedup5s"

echo
echo "=============================================="
echo " X3 关键：经 vmauth 连查 12 次，看结果是否抖动"
echo "=============================================="
echo "   backend → tenant 100 → [vmselect-learn(无dedup), vmsel-dedup(30s)]"
echo
printf "    "
for i in $(seq 1 12); do
  v=$(curl -s --max-time 20 -u backend:backend-pass-123 \
      --data-urlencode "query=$Q" \
      'http://localhost:8427/api/v1/query' \
      | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null)
  printf "%s " "$v"
done
echo
echo
echo "  → 若结果在 5 和 10 之间跳变，说明【同一个查询返回了不一致的结果】"

echo
echo "=============================================="
echo " X4 各 vmauth 实例的配置差异（解释 viewer=10）"
echo "=============================================="
echo "  -- vmauth-learn(8427) 的 user 路由 --"
docker exec vmauth-learn cat /etc/vmauth/config.yml 2>/dev/null \
  | grep -A2 'username' | head -20

echo
echo "  -- viewer 走哪个后端 --"
docker exec vmauth-learn cat /etc/vmauth/config.yml 2>/dev/null \
  | awk '/username: "viewer"/,0' | head -12

echo
echo "=============================================="
echo " X5 结论验证：viewer 的 url_prefix 有几个"
echo "=============================================="
N=$(docker exec vmauth-learn cat /etc/vmauth/config.yml 2>/dev/null \
    | awk '/username: "viewer"/,0' | grep -c 'vmselect\|vmsel')
echo "    viewer 的后端数: $N"
echo
echo "  ⚠️ 若 viewer 只配了 1 个后端（无 dedup 的 vmselect-learn），"
echo "     它就会稳定返回【翻倍后的 10】"
echo "     而 backend/frontend 有 2 个后端（含 vmsel-dedup），"
echo "     在 5(有dedup) 和 10(无dedup) 之间跳变"

echo
echo "=============================================="
echo " X6 修复：让所有后端 dedup 配置一致"
echo "=============================================="
echo "  这正是课 9 误区 4 的实证："
echo "    '所有 vmselect 的 dedup 配置必须一致，"
echo "     否则同一个查询打到不同的 vmselect 会返回不同结果'"
echo
echo "  修复方法：给所有 vmselect 配相同的 -dedup.minScrapeInterval"
echo
echo "  验证修复效果（连查 12 次，结果应该稳定）:"
printf "    "
for i in $(seq 1 12); do
  v=$(curl -s --max-time 20 --data-urlencode "query=$Q" \
      'http://localhost:8489/select/100/prometheus/api/v1/query' \
      | python3 -c 'import json,sys
d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
print(int(sum(float(x["value"][1]) for x in r)) if r else 0)' 2>/dev/null)
  printf "%s " "$v"
done
echo "   (8489 = dedup=5s，单后端)"
