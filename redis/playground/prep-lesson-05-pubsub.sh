#!/usr/bin/env bash
# 课 5 Pub/Sub 实验：订阅 / 发布 / 模式匹配 / 消息丢失 / 与 Stream 对比
# 环境：WSL Ubuntu 24.04 + Redis 8.10.1
set -u

DIR=/tmp/redis-l05p
PORT=7203
mkdir -p $DIR

redis-server --port $PORT --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no >/dev/null 2>&1 &
SRV_PID=$!
sleep 1.2
R() { redis-cli -p "$PORT" "$@"; }
sec() { echo; echo "===== $1 ====="; }

sec "① 发布者无人订阅时，消息直接丢弃"
echo "发布到 news.sport（此时无人订阅）:"
R PUBLISH news.sport "无人接收的消息"
echo "  返回 0 = 0 个订阅者收到，这条消息永久消失"

sec "② 订阅后发布，消息能收到"
# 后台起一个订阅者，输出到文件
( redis-cli -p $PORT SUBSCRIBE news.sport > $DIR/sub1.log 2>&1 ) &
SUB1=$!
sleep 0.6
echo "再发布一条："
R PUBLISH news.sport "有人接收的消息"
sleep 0.5
kill $SUB1 2>/dev/null
echo "-- 订阅者收到的内容："
cat $DIR/sub1.log

sec "③ 订阅者必须先订阅：先发布、后订阅 => 收不到"
R PUBLISH news.late "先发的消息"
( redis-cli -p $PORT SUBSCRIBE news.late > $DIR/sub2.log 2>&1 ) &
SUB2=$!
sleep 0.6
R PUBLISH news.late "后发的消息"
sleep 0.5
kill $SUB2 2>/dev/null
echo "-- 订阅者只收到了："
grep -c "后发的消息" $DIR/sub2.log | xargs echo "  '后发的消息' 出现次数："
grep -c "先发的消息" $DIR/sub2.log | xargs echo "  '先发的消息' 出现次数：  <-- 0，已丢失"

sec "④ 模式匹配订阅 PSUBSCRIBE news.*"
( redis-cli -p $PORT PSUBSCRIBE 'news.*' > $DIR/sub3.log 2>&1 ) &
SUB3=$!
sleep 0.6
R PUBLISH news.sport "体育新闻" > /dev/null
R PUBLISH news.tech "科技新闻" > /dev/null
R PUBLISH order.pay "订单消息" > /dev/null
sleep 0.5
kill $SUB3 2>/dev/null
echo "-- 模式订阅者收到："
grep -E "体育新闻|科技新闻|订单消息" $DIR/sub3.log | sed 's/^/  /'
echo "  （order.pay 不匹配 news.*，未被收到）"

sec "⑤ 订阅者不消费 -> 输出缓冲区堆积 -> 被断开"
R CONFIG SET client-output-buffer-limit "pubsub 2mb 1mb 5" > /dev/null
echo "  pubsub 缓冲区限制已设为 2mb 硬限制"
( redis-cli -p $PORT SUBSCRIBE big.chan > /dev/null 2>&1 ) &
SUB4=$!
sleep 0.6
echo "  持续发布 5MB 数据给一个不消费的订阅者……"
python3 - "$PORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.create_connection(("127.0.0.1", port))
payload = b"x" * 1000
sent = 0
try:
    for i in range(6000):
        msg = payload
        s.sendall(b"*3\r\n$7\r\nPUBLISH\r\n$8\r\nbig.chan\r\n$%d\r\n%s\r\n" % (len(msg), msg))
        sent += len(msg)
        if i % 1000 == 0:
            s.recv(65536)
except Exception as e:
    print("  发布端异常：", e)
print("  已发布约 %.2f MB" % (sent / 1024 / 1024))
PY
sleep 1
echo "-- CLIENT LIST 查看订阅者状态："
R CLIENT LIST | grep -o "cmd=subscribe[^ ]*.*omem=[0-9]*" | head -3
echo "  （omem 持续增长即输出缓冲区堆积；超过硬限制 Redis 会主动断开订阅者）"
kill $SUB4 2>/dev/null

sec "⑥ 与 Stream 的关键差异：Pub/Sub 没有持久化与确认"
echo "  Pub/Sub：消息不落盘、无 ACK、订阅者掉线即丢"
echo "  Stream  ：消息落 RDB/AOF、有 PEL 与 XACK、消费者掉线消息仍在"
echo "-- 证据：Pub/Sub 发布后查 keyspace，什么都留不下"
R PUBLISH news.sport "试试能不能留下痕迹" > /dev/null
echo "  DBSIZE = $(R DBSIZE)   （发布不影响 keyspace）"
R XADD s:persist '*' msg "同样一条消息" > /dev/null
echo "  写入 Stream 后 DBSIZE = $(R DBSIZE)   （Stream 留下了数据）"

sec "⑦ 频道数量与订阅关系查询"
( redis-cli -p $PORT SUBSCRIBE ch:a ch:b > /dev/null 2>&1 ) &
SUB5=$!
sleep 0.6
echo "-- PUBSUB CHANNELS（活跃频道）："
R PUBSUB CHANNELS
echo "-- PUBSUB NUMSUB："
R PUBSUB NUMSUB ch:a ch:b
echo "-- PUBSUB NUMPAT（模式订阅数）："
R PUBSUB NUMPAT
kill $SUB5 2>/dev/null

R shutdown nosave 2>/dev/null
wait $SRV_PID 2>/dev/null
rm -rf $DIR
echo; echo "Pub/Sub 实验结束，实例已清理。"
