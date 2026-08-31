#!/usr/bin/env bash
# 课5 一键验证脚本：队列属性 + 消息属性 + 队列类型
# 用法：bash /mnt/d/projects/learning/rabbitmq/playground/l5-verify.sh
# 前置：rabbitmq-learn 容器运行中（docker start rabbitmq-learn）

set -u
PASS=0; FAIL=0
DEX="docker exec -e RABBITMQADMIN_USERNAME=learn -e RABBITMQADMIN_PASSWORD=learn123 rabbitmq-learn"
PG=/mnt/d/projects/learning/rabbitmq/playground

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "############################################"
echo "#  课 5 验证：队列与消息的属性"
echo "############################################"

echo ""
echo "=== 检查 0：容器是否就绪 ==="
if docker exec rabbitmq-learn rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
  ok "RabbitMQ 容器运行中"
else
  echo "  ⚠️ 容器未运行，尝试启动..."
  docker start rabbitmq-learn >/dev/null 2>&1
  for i in $(seq 1 60); do
    docker exec rabbitmq-learn rabbitmq-diagnostics -q check_running >/dev/null 2>&1 && break
    sleep 1
  done
  docker exec rabbitmq-learn rabbitmq-diagnostics -q check_running >/dev/null 2>&1 \
    && ok "容器已启动" || { bad "容器无法启动，请先 docker start rabbitmq-learn"; exit 1; }
fi

echo ""
echo "=== 检查 1：stream 插件已启用（知识点3 需要）==="
docker exec rabbitmq-learn rabbitmq-plugins list 2>&1 | grep -q "\[E\*\] rabbitmq_stream" \
  && ok "stream 插件已启用" \
  || { echo "     正在启用..."; docker exec rabbitmq-learn rabbitmq-plugins enable rabbitmq_stream rabbitmq_stream_management >/dev/null 2>&1; sleep 3; \
       docker exec rabbitmq-learn rabbitmq-plugins list 2>&1 | grep -q "\[E\*\] rabbitmq_stream" \
         && ok "stream 插件已启用" || bad "stream 插件启用失败"; }

echo ""
echo "=== 检查 2：三种队列类型都能声明 ==="
for t in classic quorum stream; do
  $DEX rabbitmqadmin declare queue --name "v_$t" --type "$t" --durable true --non-interactive >/dev/null 2>&1 \
    && ok "声明 $t 队列成功" || bad "声明 $t 队列失败"
done

echo ""
echo "=== 检查 3：默认类型是 classic ==="
$DEX rabbitmqadmin declare queue --name v_default --durable true --non-interactive >/dev/null 2>&1
sleep 1
got=$(docker exec rabbitmq-learn rabbitmqctl list_queues name type 2>/dev/null | awk '$1=="v_default"{print $2}')
[ "$got" = "classic" ] && ok "未指定类型时默认 classic（实测：$got）" || bad "默认类型异常（实测：$got）"

echo ""
echo "=== 检查 4：quorum/stream 拒绝非持久化 ==="
for t in quorum stream; do
  out=$($DEX rabbitmqadmin declare queue --name "v_nd_$t" --type "$t" --durable false --non-interactive 2>&1)
  echo "$out" | grep -qi "transient_nonexcl_queues\|not permitted\|PRECONDITION" \
    && ok "$t 拒绝非持久化（4.3 特性）" || bad "$t 未拒绝非持久化"
done

echo ""
echo "=== 检查 5：stream 拒绝 auto-delete ==="
out=$($DEX rabbitmqadmin declare queue --name v_stream_ad --type stream --durable true --auto-delete true --non-interactive 2>&1)
echo "$out" | grep -qi "invalid property" \
  && ok "stream 拒绝 auto-delete" || bad "stream 未拒绝 auto-delete"

echo ""
echo "=== 检查 6：属性不可改（inequivalent）==="
out=$($DEX rabbitmqadmin declare queue --name v_classic --type quorum --durable true --non-interactive 2>&1)
echo "$out" | grep -qi "inequivalent" \
  && ok "改类型报 inequivalent" || bad "改类型未报 inequivalent"
out=$($DEX rabbitmqadmin declare queue --name v_classic --type classic --durable false --non-interactive 2>&1)
echo "$out" | grep -qi "inequivalent\|transient_nonexcl" \
  && ok "改 durable 报 inequivalent" || bad "改 durable 未报 inequivalent"

echo ""
echo "=== 检查 1b：P0 守护 —— 裸 queue_declare 在 4.3 上确实被拒 ==="
cd "$PG" && python l5-check-541.py > /tmp/l5_541.log 2>&1
grep -q "code=541" /tmp/l5_541.log \
  && ok "裸 queue_declare 被拒（541）→ 第一幕叙事与实测一致" \
  || bad "541 未复现，第一幕叙事需复核"

echo ""
echo "=== 检查 7：Python 侧 —— 队列属性组合 ==="
cd "$PG" && python l5-queue-props2.py > /tmp/l5_p2.log 2>&1
grep -q "code=541" /tmp/l5_p2.log \
  && ok "transient 非独占被拒（541，且关闭整个连接）" || bad "transient 限制未复现"
grep -q "code=405" /tmp/l5_p2.log \
  && ok "exclusive 队列被其他连接访问报 405 RESOURCE_LOCKED" || bad "exclusive 独占性未复现"
grep -q "连接级" /tmp/l5_p2.log \
  && ok "exclusive 是连接级独占（非信道级）" || bad "exclusive 级别判定失败"

echo ""
echo "=== 检查 8：Python 侧 —— auto-delete 语义 ==="
cd "$PG" && python l5-autodelete.py > /tmp/l5_ad.log 2>&1
grep -q "l5_ad_q 存在? False" /tmp/l5_ad.log \
  && ok "auto-delete：最后消费者断开后删除" || bad "auto-delete 未生效"
grep -q "l5_noad_q 存在? True" /tmp/l5_ad.log \
  && ok "对照组：非 auto-delete 队列保留" || bad "对照组异常"
grep -q "l5_ad_never 存在? True" /tmp/l5_ad.log \
  && ok "auto-delete 队列从未消费时不删除" || bad "auto-delete 时机判定失败"

echo ""
echo "=== 检查 9：Python 侧 —— 消息属性 ==="
cd "$PG" && python l5-msg-props.py > /tmp/l5_mp.log 2>&1
grep -q "delivery_mode      = 2" /tmp/l5_mp.log \
  && ok "消息属性可完整写入并读出（delivery_mode=2）" || bad "消息属性读写失败"
grep -q "user_id" /tmp/l5_mp.log \
  && ok "headers / message_id / timestamp 等属性齐全" || bad "属性不全"
grep -q "PRECONDITION_FAILED - user_id" /tmp/l5_mp.log \
  && ok "user_id 冒充他人被拒（406）" || bad "user_id 校验未复现"
grep -q "delivery_mode = None" /tmp/l5_mp.log \
  && ok "不设 properties 时 delivery_mode 回传为 None" || bad "默认值判定失败"

echo ""
echo "=== 检查 10：消息大小限制 ==="
cd "$PG" && python l5-msg-size3.py > /tmp/l5_sz.log 2>&1
grep -q "取出长度 = 5242880" /tmp/l5_sz.log \
  && ok "5 MiB 大消息可正常收发" || bad "大消息收发失败"
grep -q "larger than configured max size" /tmp/l5_sz.log \
  && ok "超限消息报 406 且未入队" || bad "超限行为未复现"
grep -q "连接是否存活? True" /tmp/l5_sz.log \
  && ok "超限是 channel 级错误（连接存活）" || bad "超限错误级别判定失败"

echo ""
echo "=== 检查 11：arguments 参数 ==="
cd "$PG" && python l5-args.py > /tmp/l5_ar.log 2>&1
grep -q "发了 5 条，队列深度 = 3" /tmp/l5_ar.log \
  && ok "x-max-length 生效（超出丢弃）" || bad "x-max-length 未生效"
grep -q "2.5 秒后深度 = 0" /tmp/l5_ar.log \
  && ok "x-message-ttl 生效（过期清除）" || bad "x-message-ttl 未生效"
grep -q "high-1(p9)" /tmp/l5_ar.log \
  && ok "x-max-priority 生效（高优先级先出）" || bad "优先级未生效"
grep -q "3.5 秒后：队列已消失" /tmp/l5_ar.log \
  && ok "x-expires 生效（空闲队列自动删除）" || bad "x-expires 未生效"
grep -q "stream + x-message-ttl: ❌" /tmp/l5_ar.log \
  && ok "stream 拒绝 x-message-ttl（特性边界）" || bad "stream 参数边界未复现"

echo ""
echo "=== 检查 12：持久化（重启验证，可选、较慢）==="
echo "  （如需验证重启存活，手动执行：bash $PG/l5-restart.sh）"
echo "  已实测结论：durable 队列 + delivery_mode=2 → 重启后存活；delivery_mode=1 → 丢失"

echo ""
echo "############################################"
echo "#  结果：通过 $PASS 项，失败 $FAIL 项"
echo "############################################"
[ "$FAIL" -eq 0 ] && echo "🎉 全部通过" || echo "⚠️ 有失败项，请检查上方输出"
