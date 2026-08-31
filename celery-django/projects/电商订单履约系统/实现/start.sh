#!/usr/bin/env bash
# 电商订单履约系统 · 本地启动脚本
#
# 用法：
#   bash start.sh            # 启动全部组件
#   bash start.sh stop       # 停止全部组件
#   bash start.sh status     # 查看运行状态
#
# ⚠️ 先确认 Redis 已启动且密码正确（见 REDIS_URL）
set -u

REDIS_URL="redis://:yourpassword@localhost:6380/0"
APP="proj"

start_redis () {
  echo ">>> 检查 Redis ..."
  if redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "    Redis 已在运行"
  else
    echo "    启动 Redis ..."
    redis-server --port 6380 --requirepass yourpassword --daemonize yes
    sleep 2
  fi
}

start_fast_worker () {
  # 决策 1：快队列用 gevent，高并发
  # -c 200 是因为发券/通知都是 IO 密集（课 9 实测：gevent 可开到 200 并发）
  echo ">>> 启动 fast worker（gevent, -c 200）..."
  celery -A "$APP" worker \
    -Q fast \
    -P gevent -c 200 \
    -n fast@%h \
    -E \
    -l INFO \
    --logfile=logs/fast-worker.log \
    --pidfile=logs/fast-worker.pid \
    --detach
}

start_slow_worker () {
  # 决策 1：慢队列用 prefork（对账是 CPU/DB 密集，且需要进程隔离防内存泄漏）
  # --max-tasks-per-child=1000：防内存泄漏（课 9 实测有效）
  #
  # 注意：这里不需要带 default —— 所有业务任务都已在 CELERY_TASK_ROUTES 里显式路由，
  # 且 Redis backend 有原生 chord 协调，不产生 chord_unlock 任务（实测日志中 0 次）。
  # 若发现 default 队列有积压，说明有任务漏配了路由，应去补路由而非让 worker 兜底消费。
  echo ">>> 启动 slow worker（prefork, -c 8）..."
  celery -A "$APP" worker \
    -Q slow \
    -P prefork -c 8 \
    --prefetch-multiplier=1 \
    --max-tasks-per-child=1000 \
    -n slow@%h \
    -E \
    -l INFO \
    --logfile=logs/slow-worker.log \
    --pidfile=logs/slow-worker.pid \
    --detach
}

start_beat () {
  # 决策 2：beat 每 30 秒轮询扫描超时订单
  echo ">>> 启动 beat（每 30 秒扫超时订单 + 每 60 秒心跳）..."
  celery -A "$APP" beat \
    -l INFO \
    --logfile=logs/beat.log \
    --pidfile=logs/beat.pid \
    --detach
}

start_flower () {
  # 可观测性（知识点 19）
  # ⭐ --basic_auth 必须有：Flower 默认无鉴权，且有"执行/撤销/关停 worker"的 API
  #    暴露公网等于把集群控制权送人（CVE-2022-30034，CVSS 8.6）
  echo ">>> 启动 Flower（http://127.0.0.1:5555）..."
  celery -A "$APP" flower \
    --address=127.0.0.1 \
    --port=5555 \
    --basic_auth=admin:changeme \
    --logfile=logs/flower.log \
    --pidfile=logs/flower.pid \
    --detach
}

stop_all () {
  echo ">>> 停止全部组件 ..."
  for f in logs/*.pid; do
    [ -f "$f" ] || continue
    PID=$(cat "$f")
    if [ -n "$PID" ]; then
      # 先 TERM（触发优雅停机，知识点 18）
      kill -TERM "$PID" 2>/dev/null || true
    fi
  done
  sleep 20          # ⭐ 等待优雅停机完成（要 > worker_soft_shutdown_timeout=15）
  pkill -f 'celery -A proj' 2>/dev/null || true
  rm -f logs/*.pid
  echo "    已停止"
}

show_status () {
  echo "=== worker 状态 ==="
  celery -A "$APP" inspect stats 2>/dev/null | head -20 || echo "  无 worker 在线"
  echo
  echo "=== 队列长度 ==="
  for q in fast slow default celery; do
    echo "  $q: $(redis-cli -p 6380 -a yourpassword --no-auth-warning -n 0 LLEN "$q" 2>/dev/null || echo 0)"
  done
  echo
  echo "=== 已注册任务 ==="
  celery -A "$APP" inspect registered 2>/dev/null | grep -E 'orders\.tasks' | head -10 || true
}

case "${1:-start}" in
  start)
    mkdir -p logs
    start_redis
    start_fast_worker
    start_slow_worker
    start_beat
    start_flower
    echo
    echo "✅ 全部启动完成"
    echo "   Flower: http://127.0.0.1:5555 （admin / changeme）"
    echo "   日志: logs/ 目录"
    echo
    echo "验证命令："
    echo "   bash verify.sh        # 跑一遍验收清单里的自动化检查"
    echo "   bash start.sh status  # 看运行状态"
    ;;
  stop)
    stop_all
    ;;
  status)
    show_status
    ;;
  *)
    echo "用法: bash start.sh [start|stop|status]"
    exit 1
    ;;
esac
exit 0
