#!/usr/bin/env bash
# 课 6《确认机制与预取》一键验证脚本
# 覆盖三个知识点的核心事实，共 20 项检查
export PYTHONIOENCODING=utf-8
PG=/mnt/d/projects/learning/rabbitmq/playground
cd "$PG" || exit 1

pass=0; fail=0
ok()   { echo "  ✅ $1"; pass=$((pass+1)); }
bad()  { echo "  ❌ $1"; fail=$((fail+1)); }

echo "=============================================================="
echo " 课 6 验证：确认机制与预取"
echo "=============================================================="

echo ""
echo "=== 环境 ==="
docker exec rabbitmq-learn rabbitmqctl status > /dev/null 2>&1 \
  && ok "RabbitMQ 容器运行中" || bad "RabbitMQ 容器未运行"
python3 -c "import pika; assert pika.__version__ >= '1.0'" 2>/dev/null \
  && ok "pika 可用（$(python3 -c 'import pika;print(pika.__version__)')）" || bad "pika 不可用"

echo ""
echo "=== 知识点 1：消费者确认 ==="
python3 -u l6-ack2.py > /tmp/l6_v_ack.log 2>&1
grep -q "redelivered=True" /tmp/l6_v_ack.log \
  && ok "未 ack 断开后消息重投（redelivered=True）" || bad "重投未复现"
grep -q "unacked=1  total=3" /tmp/l6_v_ack.log \
  && ok "manual ack 期间状态为 unacked=1 / total=3" || bad "unacked 状态未观测到"
grep -q "崩溃后.*ready=3  unacked=0" /tmp/l6_v_ack.log \
  && ok "消费者崩溃后消息回到 ready（未丢失）" || bad "崩溃后消息未回到队列"

python3 -u l6-qos-probe.py > /tmp/l6_v_qos.log 2>&1
grep -q "auto_ack=True + prefetch_count=1" /tmp/l6_v_qos.log
if grep -A2 "auto_ack=True + prefetch_count=1" /tmp/l6_v_qos.log | grep -q "ready= 0  unacked= 0  total= 0"; then
  ok "P0 事实：prefetch 对 auto_ack 无效（10 条一次性推空）"
else
  bad "prefetch 对 auto_ack 的行为与记录不符"
fi
grep -A2 "auto_ack=False + 不设 prefetch" /tmp/l6_v_qos.log | grep -q "unacked=10" \
  && ok "不设 prefetch 时 10 条全部进入 unacked" || bad "无 prefetch 的 unacked 行为不符"

echo ""
echo "=== 知识点 2：发布者确认 ==="
python3 -u l6-confirm.py > /tmp/l6_v_cf.log 2>&1
grep -q "UnroutableError" /tmp/l6_v_cf.log \
  && ok "mandatory=True 路由不到 → 抛 UnroutableError（退回）" || bad "mandatory 退回未复现"
grep -q "静默丢弃" /tmp/l6_v_cf.log \
  && ok "mandatory=False 路由不到 → 静默丢弃" || bad "静默丢弃未验证"

python3 -u l6-perf.py > /tmp/l6_v_pf1.log 2>&1
grep -q "confirm（异步）" /tmp/l6_v_pf1.log \
  && ok "性能对照表生成（无确认/confirm/事务）" || bad "性能对照缺失"

python3 -u l6-perf2.py > /tmp/l6_v_pf2.log 2>&1
# 从"条/ RTT"列取值，所有 N 下都应接近 1（0.5~1.5 之间即视为"≈1 个 RTT"）
ratios=$(grep -E "^\s+(100|300|600)\s+" /tmp/l6_v_pf2.log | awk '{print $NF}')
inrange=1
for v in $ratios; do
  awk -v x="$v" 'BEGIN{exit !(x>=0.5 && x<=1.5)}' || inrange=0
done
if [ -n "$ratios" ] && [ "$inrange" -eq 1 ]; then
  ok "P0 事实：pika confirm 单条耗时 ≈ 1 个 RTT（实测比值: $ratios）"
else
  bad "RTT 占比验证失败（比值: $ratios，期望均落在 0.5~1.5）"
fi

python3 -u l6-confirm-frames3.py > /tmp/l6_v_f3.log 2>&1
grep -q "4 连接并发" /tmp/l6_v_f3.log \
  && ok "并发 publish 吞吐提升（RTT 等待可重叠）" || bad "并发对照缺失"

python3 -u l6-xdeath-check.py > /tmp/l6_v_xd.log 2>&1
# 连续 nack(requeue=True) 三次都不应出现 x-death
if ! grep -q "x-death     = \[{" /tmp/l6_v_xd.log; then
  ok "P0 事实：nack(requeue=True) 不写 x-death（计数需自己维护）"
else
  bad "requeue=True 竟然写入了 x-death，讲义结论需复核"
fi
grep -q "x-death = \[{'count': 1" /tmp/l6_v_xd.log \
  && ok "requeue=False 后死信队列才出现 x-death（count=1）" || bad "死信 x-death 未复现"

echo ""
echo "=== 知识点 3：预取与公平分发 ==="
python3 -u l6-prefetch.py > /tmp/l6_v_pre.log 2>&1
# 不设 prefetch 时结果取决于谁先连上（线程调度随机），可能是 0:40 或 40:0。
# 关键事实是"一方独占"，而非具体谁独占 —— 两种极端都算复现。
if grep -q "快慢比: 0.0 : 1" /tmp/l6_v_pre.log; then
  ok "P0 事实：不设 prefetch 时慢消费者独占全部（0:40）"
elif grep -qE "快慢比: 40\.0 : 1" /tmp/l6_v_pre.log; then
  ok "P0 事实：不设 prefetch 时快消费者独占全部（40:0）"
else
  bad "不设 prefetch 的分发结果与预期不符（既非 0:40 也非 40:0）"
fi
grep -q "快慢比: 19.0 : 1" /tmp/l6_v_pre.log \
  && ok "prefetch=1 时快者多劳（38:2，19:1）" || bad "prefetch=1 公平性不符"
grep -q "快慢比: 3.0 : 1" /tmp/l6_v_pre.log \
  && ok "prefetch=10 时按比例分发（30:10，3:1）" || bad "prefetch=10 分发不符"

# 吞吐趋势：prefetch=1 应显著低于 prefetch=20/100（小预取值受 RTT 制约）
t1=$(grep -E "^\s+1\s+" /tmp/l6_v_pre.log | awk '{print $NF}')
t20=$(grep -E "^\s+20\s+" /tmp/l6_v_pre.log | awk '{print $NF}')
t100=$(grep -E "^\s+100\s+" /tmp/l6_v_pre.log | awk '{print $NF}')
if [ -n "$t1" ] && [ -n "$t20" ] && [ "$t20" -gt "$t1" ] 2>/dev/null \
   && [ "$t100" -gt "$t1" ] 2>/dev/null; then
  ok "吞吐随 prefetch 增大而提升（1→${t1}，20→${t20}，100→${t100} 条/秒）"
else
  bad "吞吐与 prefetch 关系未验证（1→$t1，20→$t20，100→$t100）"
fi

echo ""
echo "=============================================================="
echo " 结果：$pass 项通过，$fail 项失败"
echo "=============================================================="
[ "$fail" -eq 0 ] || exit 1
