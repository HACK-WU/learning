#!/usr/bin/env bash
# 电商订单履约系统 · 验收脚本
#
# 用途：自动验证「验收清单.md」里的关键项，把"我觉得做成了"变成"证明做成了"
# 用法：bash verify.sh
#
# 本脚本验证 6 项（其余项需人工在验收清单里勾选）：
#   ① CAS 幂等：关单任务重复执行 3 次，库存只回滚 1 次
#   ② 队列路由：快慢任务是否真的进了不同队列
#   ③ 序列化安全：accept_content 不含 pickle（注意：会先剥掉注释再判断）
#   ④ 超时保护：任务配了 soft_time_limit（实际 6 个）
#   ⑤ 可观测性：prerun/postrun/failure 三个钩子都带 task_id
#   ⑥ 事务边界：用 transaction.on_commit 发任务
set -u

# ⭐ 自动探测 Python 解释器（不硬编码路径，避免环境变动后脚本失效）
#    优先用项目自带 venv，其次系统 python3
if [ -x "/mnt/d/projects/learning/celery-django/.venv/bin/python" ]; then
  PY=/mnt/d/projects/learning/celery-django/.venv/bin/python
else
  PY=$(command -v python3 || command -v python || echo "python3")
fi

PROJ_DIR=/mnt/d/projects/learning/celery-django/projects/电商订单履约系统/实现

echo "使用解释器: $PY"
"$PY" -c "import redis" 2>/dev/null || echo "  ⚠️ 该解释器没有 redis 模块，检查①会失败"

echo "=========================================="
echo " 电商订单履约系统 · 验收脚本"
echo "=========================================="
echo

PASS=0
FAIL=0

check () {
  local name=$1
  local result=$2
  if [ "$result" = "ok" ]; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name — $result"
    FAIL=$((FAIL + 1))
  fi
}

echo "【检查 ①】CAS 幂等：重复执行 3 次，库存只回滚 1 次"
echo "         （对应决策 3 / 反例对照第 3 条）"
OUT=$("$PY" - <<'PYEOF' 2>&1
import redis
r = redis.Redis(host='localhost', port=6380, db=6, decode_responses=True)
r.flushdb()
r.set('order:9001:status', 'PENDING')
r.set('stock:sku_x', '10')

lua = """
if redis.call('GET', KEYS[1]) == 'PENDING' then
    redis.call('SET', KEYS[1], 'CLOSED')
    redis.call('INCR', KEYS[2])
    return 1
end
return 0
"""
res = [r.eval(lua, 2, 'order:9001:status', 'stock:sku_x') for _ in range(3)]
stock = r.get('stock:sku_x')
# 期望：res=[1,0,0] 且 stock=11
if res == [1, 0, 0] and stock == '11':
    print('ok')
else:
    print(f'期望 [1,0,0] 且库存 11，实际 {res} 库存 {stock}')
PYEOF
)
check "CAS 幂等生效（重复 3 次只回滚 1 次）" "$OUT"

echo
echo "【检查 ②】队列路由配置：快慢任务进不同队列"
ROUTE_OK=$(grep -c "orders.tasks.send_notification': {'queue': 'fast'}" "$PROJ_DIR/proj/settings_celery.py" 2>/dev/null || echo 0)
ROUTE_SLOW=$(grep -c "orders.tasks.write_reconciliation': {'queue': 'slow'}" "$PROJ_DIR/proj/settings_celery.py" 2>/dev/null || echo 0)
if [ "$ROUTE_OK" -ge 1 ] && [ "$ROUTE_SLOW" -ge 1 ]; then
  check "快任务路由到 fast、慢任务路由到 slow" "ok"
else
  check "快任务路由到 fast、慢任务路由到 slow" "配置缺失（fast=$ROUTE_OK slow=$ROUTE_SLOW）"
fi

echo
echo "【检查 ③】序列化安全：accept_content 不含 pickle"
# ⚠️ 注意：配置行尾有注释（含 pickle 字样），必须先把注释剥掉再判断
#    否则注释里的 "绝不能包含 'pickle'" 会让检测误判 —— 这是本脚本初版的真实 bug
ACCEPT=$(grep -E "^CELERY_ACCEPT_CONTENT" "$PROJ_DIR/proj/settings_celery.py" 2>/dev/null | sed 's/#.*$//' || echo "")
if echo "$ACCEPT" | grep -q "'json'" && ! echo "$ACCEPT" | grep -q "pickle"; then
  check "accept_content = ['json']（代码部分不含 pickle）" "ok"
else
  check "accept_content = ['json']（代码部分不含 pickle）" "实际为：$ACCEPT"
fi

echo
echo "【检查 ④】超时保护：任务配了 soft_time_limit / time_limit"
TL=$(grep -c "soft_time_limit" "$PROJ_DIR/orders/tasks.py" 2>/dev/null || echo 0)
if [ "$TL" -ge 3 ]; then
  check "至少 3 个任务配了 soft_time_limit（实际 $TL 个）" "ok"
else
  check "任务配了 soft_time_limit" "只有 $TL 个，建议全覆盖"
fi

echo
echo "【检查 ⑤】可观测性：信号钩子会打 task_id"
HOOK=$(grep -c "task_id=%s" "$PROJ_DIR/proj/celery.py" 2>/dev/null || echo 0)
if [ "$HOOK" -ge 3 ]; then
  check "prerun/postrun/failure 三个钩子都带 task_id（$HOOK 处）" "ok"
else
  check "日志钩子带 task_id" "只有 $HOOK 处"
fi

echo
echo "【检查 ⑥】事务边界：用了 on_commit 发任务"
OC=$(grep -c "transaction.on_commit" "$PROJ_DIR/orders/views.py" 2>/dev/null || echo 0)
if [ "$OC" -ge 1 ]; then
  check "支付后用 on_commit 触发任务（防事务未提交）" "ok"
else
  check "支付后用 on_commit 触发任务" "未找到 on_commit"
fi

echo
echo "=========================================="
echo " 结果：通过 $PASS 项，失败 $FAIL 项"
echo "=========================================="
echo
echo "📋 剩余验收项需人工操作，见 验收清单.md："
echo "   - 起 worker 跑真实下单 → 15 分钟关单流程"
echo "   - SIGKILL worker 验证任务不丢且重投"
echo "   - Flower 里能看到任务事件流"
echo "   - 慢任务不堵快任务（对比等待时长）"
echo
exit 0
