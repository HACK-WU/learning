#!/bin/bash
# 课 10 收官：vmauth 限流补救 + 单节点写入路径排查 + 故障演练
set -u
NET=vm-cluster-net
PLAY=/mnt/d/projects/learning/victoriametrics/playground
CFG=$PLAY/vmauth-config.yml

echo "=============================================="
echo " R1 排查：单节点 vm-learn 的写入路径"
echo "=============================================="
echo "  B5 里 /api/v1/write 返回 400，可能是 body 格式问题"
echo "  （我发的是 Influx 纯文本，remote write 端点要 snappy protobuf）"
echo
for P in "/api/v1/write" "/write" "/influx/write" "/prometheus/write"; do
  printf "    单节点 %-22s " "$P"
  curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 10 \
    --data-binary "l10_sn,idx=1 value=1 $(($(date +%s)*1000000000))" \
    "http://localhost:8428$P" 2>/dev/null
done
echo
echo "  -- 单节点正确路径（课 2 用过）--"
printf "    /write (Influx 行协议):      "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 10 \
  --data-binary "l10_sn,idx=1 value=1 $(($(date +%s)*1000000000))" \
  'http://localhost:8428/write'
printf "    /api/v1/import (Influx):     "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST --max-time 10 \
  --data-binary "l10_sn,idx=1 value=1 $(($(date +%s)*1000000000))" \
  'http://localhost:8428/api/v1/import'
echo
echo "  → 单节点版路径: /write, /api/v1/import（无租户段）"
echo "    集群版路径:   /insert/<tenant>/influx/write, /insert/<tenant>/prometheus/api/v1/write"
echo "    ⚠️ 两者【不兼容】，迁移时客户端要改 URL"

echo
echo "=============================================="
echo " R2 vmauth 限流：给大租户戴上嚼子"
echo "=============================================="
echo "  用 -maxConcurrentPerUserRequests 限制单用户并发"
echo
docker rm -f vmauth-limit >/dev/null 2>&1
docker run -d --name vmauth-limit \
  --network "$NET" -p 8426:8427 \
  -v "$CFG:/etc/vmauth/config.yml:ro" \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -maxConcurrentPerUserRequests=2 \
  -maxQueueDuration=1s \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8426/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth(限流版) 就绪 (8426)"; break; fi
  sleep 2
done

echo
echo "  -- 并发 20 个慢查询，看是否触发 429 --"
echo "     （用大范围查询制造慢请求）"
for i in $(seq 1 20); do
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u backend:backend-pass-123 \
    --data-urlencode 'query=count_over_time(l10_big_value[24h])' \
    'http://localhost:8426/api/v1/query' &
done
wait
echo
echo "  -- 统计返回码分布 --"
for i in $(seq 1 20); do
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 30 -u backend:backend-pass-123 \
    --data-urlencode 'query=count_over_time(l10_big_value[24h])' \
    'http://localhost:8426/api/v1/query' 2>/dev/null
done | sort | uniq -c

echo
echo "  -- vmauth 限流指标 --"
curl -s --max-time 15 'http://localhost:8426/metrics' 2>/dev/null \
  | grep -iE 'concurrent|queue|429' | head -8

echo
echo "=============================================="
echo " R3 vmauth 的故障摘除（健康检查）"
echo "=============================================="
echo "  vmauth 用 least_loaded 策略，会自动避开故障后端"
echo "  测试：停掉 vmsel-dedup(8487)，看 backend 查询是否仍可用"
echo
echo -n "    停前 backend 查询: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query'

echo "    停掉 vmsel-dedup ..."
docker stop vmsel-dedup >/dev/null 2>&1
sleep 3

echo -n "    停后 backend 查询: "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query'

echo -n "    连查 3 次:        "
for i in 1 2 3; do
  printf "%s " "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -u backend:backend-pass-123 \
    --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query')"
done
echo

echo "    恢复 vmsel-dedup ..."
docker start vmsel-dedup >/dev/null 2>&1
sleep 8
echo -n "    恢复后查询:       "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query'
echo "  → vmauth 自动摘除故障后端，查询不中断"

echo
echo "=============================================="
echo " R4 vmauth 本身的高可用"
echo "=============================================="
echo "  vmauth 无状态，可部署多个 + 前置 LB"
docker rm -f vmauth-2 >/dev/null 2>&1
docker run -d --name vmauth-2 \
  --network "$NET" -p 8425:8427 \
  -v "$CFG:/etc/vmauth/config.yml:ro" \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8425/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth-2 就绪 (8425)"; break; fi
  sleep 2
done

echo
echo "  停掉 vmauth-learn(8427)，用 vmauth-2(8425) 查询"
docker stop vmauth-learn >/dev/null 2>&1
sleep 3
printf "    经 vmauth-learn(8427, 已停): "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 10 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8427/api/v1/query' 2>/dev/null
printf "    经 vmauth-2(8425):           "
curl -s -o /dev/null -w 'HTTP %{http_code}\n' --max-time 20 -u backend:backend-pass-123 \
  --data-urlencode 'query=l10_va_value' 'http://localhost:8425/api/v1/query' 2>/dev/null
echo "  → vmauth 无状态，多实例 + LB 即可高可用"

docker start vmauth-learn >/dev/null 2>&1
sleep 5
echo "  vmauth-learn 已恢复"

echo
echo "=============================================="
echo " R5 配置热重载验证（改租户映射）"
echo "=============================================="
echo "  修改配置：把 viewer 从 tenant 100 改到 tenant 200"
python3 - <<'PY'
p = "/mnt/d/projects/learning/victoriametrics/playground/vmauth-config.yml"
s = open(p).read()
s2 = s.replace(
  '  - username: "viewer"\n    password: "viewer-pass-000"\n    url_map:\n'
  '      - src_paths:\n          - "/api/v1/query"\n          - "/api/v1/query_range"\n'
  '        url_prefix:\n          - "http://vmselect-learn:8481/select/100/prometheus"',
  '  - username: "viewer"\n    password: "viewer-pass-000"\n    url_map:\n'
  '      - src_paths:\n          - "/api/v1/query"\n          - "/api/v1/query_range"\n'
  '        url_prefix:\n          - "http://vmselect-learn:8481/select/200/prometheus"')
open(p,"w").write(s2)
print("  配置已改: viewer 100 -> 200" if s2 != s else "  [WARN] 未匹配，配置未改")
PY

echo
printf "    viewer 重载前查到的值: "
curl -s --max-time 20 -u viewer:viewer-pass-000 --data-urlencode 'query=l10_va_value' \
  'http://localhost:8427/api/v1/query' \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception: print("N/A")' 2>&1

curl -s -o /dev/null -w '    触发 /-/reload: HTTP %{http_code}\n' --max-time 10 \
  'http://localhost:8427/-/reload'
sleep 3

printf "    viewer 重载后查到的值: "
curl -s --max-time 20 -u viewer:viewer-pass-000 --data-urlencode 'query=l10_va_value' \
  'http://localhost:8427/api/v1/query' \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); r=d.get("data",{}).get("result",[])
    print(sorted(set(x["value"][1] for x in r)) if r else "空")
except Exception: print("N/A")' 2>&1
echo "  → 若从 100 变成 200，说明热重载生效（无需重启）"
