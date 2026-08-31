#!/usr/bin/env bash
# 决策 3 验证：幂等实现的两种方式 + 重复执行的真实危害
# 场景：关单任务被重复执行（实测已证明宕机会重投），如何保证"同一订单只关一次"
# 对比：① 无幂等（反例）② CAS 数据库状态机 ③ Redis SET NX 去重
set -u

if [ -x "/mnt/d/projects/learning/celery-django/.venv/bin/python" ]; then
  PY=/mnt/d/projects/learning/celery-django/.venv/bin/python
else
  PY=$(command -v python3 || command -v python || echo "python3")
fi
cd /mnt/d/projects/learning/celery-django/playground || exit 0

echo "#####################################################"
echo "# 模拟：同一个关单任务被执行 3 次（宕机重投 + 网络抖动）"
echo "#####################################################"

"$PY" - <<'PYEOF' || true
import redis, time

r = redis.Redis(host='localhost', port=6380, db=5, decode_responses=True)
r.flushdb()

print("=" * 55)
print("方式 ①：无幂等（反例）—— 每次都执行")
print("=" * 55)
r.set('order:2001:status', 'PENDING')
r.set('stock:sku_1', '10')          # 库存 10

def close_order_naive(order_id):
    """❌ 反例：不做任何幂等检查，直接关单 + 回滚库存"""
    status = r.get(f'order:{order_id}:status')
    # 没有任何检查，直接执行
    r.set(f'order:{order_id}:status', 'CLOSED')
    r.incr('stock:sku_1', 1)         # 回滚库存
    return 'CLOSED'

for i in range(3):
    close_order_naive(2001)
print(f"执行 3 次后 → 库存 = {r.get('stock:sku_1')}（应为 11，实际被回滚了 3 次！）")
print(f"             订单状态 = {r.get('order:2001:status')}")

print()
print("=" * 55)
print("方式 ②：CAS 状态机（课 5 教的）—— 靠状态条件拦截")
print("=" * 55)
r.set('order:2002:status', 'PENDING')
r.set('stock:sku_2', '10')

def close_order_cas(order_id):
    """✅ CAS：只有 PENDING 才能变 CLOSED（用 Lua 保证原子性）"""
    lua = """
    if redis.call('GET', KEYS[1]) == 'PENDING' then
        redis.call('SET', KEYS[1], 'CLOSED')
        redis.call('INCR', KEYS[2])
        return 1
    end
    return 0
    """
    return r.eval(lua, 2, f'order:{order_id}:status', 'stock:sku_2')

results = [close_order_cas(2002) for _ in range(3)]
print(f"执行 3 次 → 返回值 = {results}（1=真的关了，0=被拦截）")
print(f"           库存 = {r.get('stock:sku_2')}（应为 11，只回滚 1 次 ✅）")
print(f"           订单状态 = {r.get('order:2002:status')}")

print()
print("=" * 55)
print("方式 ③：Redis SET NX 去重 —— 抢锁，抢到才执行")
print("=" * 55)
r.set('stock:sku_3', '10')

def close_order_nx(order_id):
    """✅ SET NX + 过期时间：抢到锁的才执行"""
    key = f'idem:close_order:{order_id}'
    got = r.set(key, '1', nx=True, ex=600)   # ⭐ ex 必须有，否则死锁
    if not got:
        return 0, '已被处理过，跳过'
    # 抢到锁 → 执行业务逻辑
    r.incr('stock:sku_3', 1)
    return 1, '执行关单'

res = [close_order_nx(2003) for _ in range(3)]
print(f"执行 3 次 → {res}")
print(f"           库存 = {r.get('stock:sku_3')}（应为 11，只回滚 1 次 ✅）")
print(f"           幂等 key = {r.get('idem:close_order:2003')}（ex=600 自动过期）")

print()
print("=" * 55)
print("方式 ④：⚠️ SET NX 但忘了 ex（死锁陷阱）")
print("=" * 55)
r.delete('idem:deadlock:demo')
r.set('idem:deadlock:demo', '1', nx=True)     # ❌ 没有 ex
print(f"第一次抢锁（无过期时间）= {r.set('idem:deadlock:demo', '1', nx=True)}")
print(f"TTL = {r.ttl('idem:deadlock:demo')}  ← -1 表示永不过期")
print("后果：若任务在抢锁后、业务逻辑完成前崩溃 → 这个订单永远无法再被关单")
PYEOF

echo
echo "==============================================="
echo "验证结束"
exit 0
