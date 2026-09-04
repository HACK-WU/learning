#!/usr/bin/env bash
# ============================================================
# 部署脚本：一次发布 = 备份 → 迁移 → 静态文件 → 重启 → 验证
#
# 用法：
#   bash deploy.sh                # 正常部署
#   bash deploy.sh --skip-backup  # 跳过备份（仅限可重建的环境）
#
# 设计要点（课 22 上线清单）：
#   1. 每一步都有明确的"在哪跑"：本地 / 构建机 / 目标机
#   2. 每一步失败都有对应的回滚动作
#   3. 迁移与重启分离：迁移失败不会把服务停掉
#   4. 部署后必须验证，验证不过自动回滚
# ============================================================
set -uo pipefail

PY="${PYTHON:-python}"
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1

cd "$(dirname "$0")"

SKIP_BACKUP=0
[ "${1:-}" = "--skip-backup" ] && SKIP_BACKUP=1

PORT="${PORT:-8000}"
HOST="${HOST:-127.0.0.1}"
BACKUP_DIR="backups"
LOG_DIR="logs"
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

STAMP=$(date +%Y%m%d-%H%M%S)

step() { echo ""; echo "▶ $1"; }
ok()   { echo "   ✅ $1"; }
die()  { echo "   ❌ $1"; echo ""; echo "🚫 部署中断：请按下面的回滚点处理"; exit 1; }

# ------------------------------------------------------------------
# 阶段 0：部署前检查（在构建机跑，不碰目标机）
# ------------------------------------------------------------------
step "阶段 0/5　部署前检查（构建机）"
export DJANGO_SETTINGS_MODULE="config.settings_prod"
if ! $PY manage.py check --fail-level ERROR 2>&1; then
  die "生产配置检查未通过——先修配置，不要带着问题上线"
fi
ok "生产配置检查通过"

# ------------------------------------------------------------------
# 阶段 1：备份（目标机）
# ------------------------------------------------------------------
step "阶段 1/5　备份（目标机）"
if [ "$SKIP_BACKUP" -eq 1 ]; then
  echo "   ⏭  已跳过备份（--skip-backup）"
else
  if [ -f db.sqlite3 ]; then
    cp db.sqlite3 "$BACKUP_DIR/db-$STAMP.sqlite3" \
      && ok "数据库已备份 → $BACKUP_DIR/db-$STAMP.sqlite3" \
      || die "备份失败——没有备份就不许继续"
  else
    echo "   ⏭  数据库不存在（首次部署），跳过备份"
  fi
fi
# ⚠️ 回滚点 1：备份失败 → 中止部署，不做任何变更，环境保持不变

# ------------------------------------------------------------------
# 阶段 2：迁移（目标机）
# ------------------------------------------------------------------
step "阶段 2/5　迁移（目标机）"
# 先看看要执行哪些迁移，做到心里有数
$PY manage.py showmigrations shop --plan 2>&1 | tail -5

if ! $PY manage.py migrate --no-input 2>&1; then
  die "迁移失败。回滚点 2：恢复 $BACKUP_DIR/db-$STAMP.sqlite3 后重试"
fi
ok "迁移完成"
# ⚠️ 回滚点 2：迁移失败 → 用备份文件覆盖 db.sqlite3
#   注意：migrate 跑的是 DDL，transaction.atomic 管不了（课 14），
#   所以要回滚到备份文件，而不是指望 SQL 回滚

# ------------------------------------------------------------------
# 阶段 3：静态文件（目标机）
# ------------------------------------------------------------------
step "阶段 3/5　收集静态文件（目标机）"
if ! $PY manage.py collectstatic --no-input 2>&1; then
  echo "   ⚠️  collectstatic 失败——不影响服务启动，但要尽快修复"
else
  ok "静态文件已收集"
fi
# 回滚点 3：静态文件收集失败不影响回滚（可重跑），风险等级低

# ------------------------------------------------------------------
# 阶段 4：启动服务（目标机）
# ------------------------------------------------------------------
step "阶段 4/5　启动服务（目标机）"
# 先停掉旧进程
if [ -f "$LOG_DIR/server.pid" ]; then
  OLD_PID=$(cat "$LOG_DIR/server.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "   停止旧进程 $OLD_PID"
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
  rm -f "$LOG_DIR/server.pid"
fi

nohup waitress-serve --host="$HOST" --port="$PORT" \
  --threads=4 config.wsgi:application \
  > "$LOG_DIR/server-$STAMP.log" 2>&1 &
NEW_PID=$!
echo $NEW_PID > "$LOG_DIR/server.pid"
ok "服务已启动（PID=$NEW_PID，日志 $LOG_DIR/server-$STAMP.log）"

# ------------------------------------------------------------------
# 阶段 5：部署后验证（目标机）
# ------------------------------------------------------------------
step "阶段 5/5　部署后验证（目标机）"

# 等待端口就绪，最多 30 秒
READY=0
for i in $(seq 1 30); do
  if curl -sf "http://$HOST:$PORT/api/v1/health/" > /tmp/health.json 2>/dev/null; then
    READY=1
    break
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "   ❌ 健康检查 30 秒内未通过"
  echo ""
  echo "   🔙 自动回滚（回滚点 4）："
  kill "$NEW_PID" 2>/dev/null || true
  if [ "$SKIP_BACKUP" -eq 0 ] && [ -f "$BACKUP_DIR/db-$STAMP.sqlite3" ]; then
    cp "$BACKUP_DIR/db-$STAMP.sqlite3" db.sqlite3
    echo "      数据库已回滚到 $BACKUP_DIR/db-$STAMP.sqlite3"
  fi
  echo "      服务已停止，请查看 $LOG_DIR/server-$STAMP.log"
  exit 1
fi

ok "健康检查通过：$(cat /tmp/health.json)"

echo ""
echo "=========================================="
echo "🎉 部署完成"
echo "   服务地址：http://$HOST:$PORT"
echo "   进程 PID：$NEW_PID"
echo "   本次日志：$LOG_DIR/server-$STAMP.log"
echo "   本次备份：$BACKUP_DIR/db-$STAMP.sqlite3"
echo ""
echo "📋 部署后人工确认（课 22 上线清单，脚本查不了的三类）："
echo "   1. 密钥来源是否正确（不是硬编码、不是默认值）"
echo "   2. 监控是否接上（日志有没有被采集）"
echo "   3. 恢复演练是否做过（备份存在 ≠ 能恢复出来）"
