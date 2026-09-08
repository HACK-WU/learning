#!/usr/bin/env bash
# 多集群统一监控平台 —— 一键验收脚本
#
# 用法：./verify.sh
# 前置：docker compose up -d 已执行且容器就绪（约 40 秒）
#
# 本脚本逐项验证「验收清单.md」里的自测项，输出 PASS / FAIL。
# 它复现了本项目开发时真实踩到的每一个坑，所以失败信息本身有教学价值。

set -u
PASS=0
FAIL=0

# 颜色（WSL/终端支持时生效）
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
info() { echo "       $1"; }

# 统一用 curl 查询，避免花括号未编码导致 400（阶段 1 课 2 的坑）
q() {
  local url="$1"; local expr="$2"; shift 2
  curl -s -G "$url" --data-urlencode "query=$expr" "$@"
}

echo "=========================================="
echo " 多集群统一监控平台 —— 验收自检"
echo "=========================================="
echo ""

echo "--- 1. 基础设施 ---"

# 1.1 容器数量（3 app + 4 prom + mimir + alertmanager + webhook = 10）
N=$(docker ps --filter "name=multi-cluster-monitoring" --format '{{.Names}}' | wc -l)
[ "$N" -eq 10 ] && ok "10 个容器全部运行（实际 $N）" || bad "容器数应为 10，实际 $N"

# 1.2 Mimir ready
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:19510/ready)
[ "$CODE" = "200" ] && ok "Mimir 就绪（HTTP $CODE）" || bad "Mimir 未就绪（HTTP $CODE），首次启动需等待约 60 秒"

# 1.3 Alertmanager ready
CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:19530/-/ready)
[ "$CODE" = "200" ] && ok "Alertmanager 就绪（HTTP $CODE）" || bad "Alertmanager 未就绪（HTTP $CODE）"

echo ""
echo "--- 2. 采集链路（阶段 1） ---"

# 2.1 三个采集端 targets 全 up
for P in 19500 19501 19502; do
  R=$(curl -s "http://localhost:$P/api/v1/targets" | grep -o '"health":"up"' | wc -l)
  [ "$R" -ge 2 ] && ok "采集端 $P 有 $R 个健康目标" || bad "采集端 $P 健康目标不足（$R）"
done

# 2.2 external_labels 生效（数据带 env 标签）
CNT=$(q http://localhost:19510/prometheus/api/v1/query 'count by (env) (up)' -H 'X-Scope-OrgID: tenant-demo' \
      | grep -o '"env":"[a-z]*"' | sort -u | wc -l)
[ "$CNT" -eq 3 ] && ok "三个环境的 env 标签均已附加（$CNT 个）" \
  || bad "env 标签数应为 3（prod/staging/dev），实际 $CNT"

echo ""
echo "--- 3. 长期存储与全局视图（阶段 3） ---"

# 3.1 数据已写入 Mimir
N=$(q http://localhost:19510/prometheus/api/v1/query 'count(http_requests_total)' -H 'X-Scope-OrgID: tenant-demo' \
    | grep -o '"value":\[[0-9.]*,"[0-9]*"\]' | grep -o '"[0-9]*"\]$' | tr -d '"[]' )
[ "${N:-0}" -gt 0 ] 2>/dev/null && ok "Mimir 已收到业务数据（${N} 条序列）" \
  || bad "Mimir 中查不到 http_requests_total，检查 remote write 与租户头"

# 3.2 多租户隔离：无租户头应 401
CODE=$(curl -s -o /dev/null -w '%{http_code}' -G http://localhost:19510/prometheus/api/v1/query \
       --data-urlencode 'query=up')
[ "$CODE" = "401" ] && ok "多租户生效：无 X-Scope-OrgID 返回 401" \
  || bad "无租户头应返回 401，实际 $CODE（多租户未生效）"

# 3.3 全局层 remote read 能读到三个集群
N=$(q http://localhost:19520/api/v1/query 'count(count by (cluster) (http_requests_total))' \
    | grep -o '"value":\[[0-9.]*,"[0-9]*"\]' | grep -o '"[0-9]*"\]$' | tr -d '"[]')
[ "${N:-0}" -ge 3 ] 2>/dev/null && ok "全局视图可见 $N 个集群" \
  || bad "全局层只读到 ${N:-0} 个集群（应 3 个）"
info "若此处为 0：检查 prometheus-global.yml 是否误配 external_labels"
info "—— external_labels 会被附加到 remote read 的选择器上，导致查不到数据且不报错"

echo ""
echo "--- 4. 告警分层（阶段 2） ---"

# 4.1 Alertmanager 收到告警
N=$(curl -s http://localhost:19530/api/v2/alerts | grep -o '"alertname"' | wc -l)
[ "$N" -gt 0 ] && ok "Alertmanager 有 $N 条活跃告警" || bad "无活跃告警（可能规则未触发或尚未求值）"

# 4.2 分层路由：dev 应进 silent 通道
if [ -f ./logs/silent.log ]; then
  N=$(grep -c '"env": "dev"' ./logs/silent.log 2>/dev/null | tail -1)
  N=${N:-0}
  if [ "$N" -gt 0 ] 2>/dev/null; then
    ok "dev 告警进入 silent 通道（$N 条）"
  else
    bad "dev 告警未进入 silent 通道"
  fi
else
  bad "silent.log 不存在，dev 告警未送达"
fi

# 4.3 分层路由：pager 通道只应出现 prod
#     注意 grep -c 在多文件/异常时可能返回多行，必须 tail -1 取最终计数
if [ -f ./logs/pager.log ]; then
  WRONG=$(grep -c '"env": "dev"\|"env": "staging"' ./logs/pager.log 2>/dev/null | tail -1)
  WRONG=${WRONG:-0}
  if [ "$WRONG" -eq 0 ] 2>/dev/null; then
    ok "pager 通道无 dev/staging 噪声"
  else
    bad "pager 通道混入 $WRONG 条非 prod 告警，路由分层失效"
  fi
else
  info "pager.log 尚未生成（prod 未发生故障，属正常现象）"
fi

echo ""
echo "=========================================="
echo " 结果：PASS=$PASS  FAIL=$FAIL"
echo "=========================================="
echo ""
echo "提示：想验证 pager 通道，可执行："
echo "  docker stop multi-cluster-monitoring-app-prod-1"
echo "  等待约 60 秒后 cat logs/pager.log"
echo "  docker start multi-cluster-monitoring-app-prod-1   # 恢复"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
