#!/usr/bin/env bash
# 课 5 Stream 实验：写入 / 读取 / 消费者组 / PEL / 消费确认
# 环境：WSL Ubuntu 24.04 + Redis 8.10.1
# 独立端口 7201，不触碰默认 6379
set -u

DIR=/tmp/redis-l05s
PORT=7201
mkdir -p $DIR

redis-server --port $PORT --bind 127.0.0.1 --dir $DIR \
  --save '' --appendonly no >/dev/null 2>&1 &
SRV_PID=$!
sleep 1.2

R() { redis-cli -p "$PORT" "$@"; }
sec() { echo; echo "===== $1 ====="; }

sec "① XADD 写入与 ID 结构"
R DEL mystream > /dev/null
R XADD mystream '*' sensor-id 1234 temperature 19.8
R XADD mystream '*' sensor-id 1234 temperature 21.3
echo "-- 指定显式 ID（必须大于已有最大 ID，否则报错）："
R XADD mystream 1000-0 k v
echo "-- 试图写入更小的 ID（会报错）："
R XADD mystream 999-0 k v
echo "-- XLEN："
R XLEN mystream

sec "② XRANGE / XREVRANGE（- + 表示最小最大）"
R XRANGE mystream - + COUNT 2
echo "-- XREVRANGE 倒序取 2 条："
R XREVRANGE mystream + - COUNT 2

sec "③ 阻塞读取 XREAD BLOCK"
echo "-- 阻塞 1000ms 读新消息（\$ 表示从现在开始；无人写入 -> nil）"
start=$(date +%s%N)
R XREAD BLOCK 1000 STREAMS mystream '$'
end=$(date +%s%N)
echo "实际阻塞耗时：$(( (end - start) / 1000000 )) ms"

sec "④ 消费者组：组内多个消费者分摊消息（不会重复投递）"
R DEL orders > /dev/null
R XGROUP CREATE orders g1 '$' MKSTREAM > /dev/null
echo "-- 组创建后写入 5 条："
for i in 1 2 3 4 5; do R XADD orders '*' oid "100$i" amount $((i * 10)) > /dev/null; done
echo "[c1 读 3 条]"; R XREADGROUP GROUP g1 c1 COUNT 3 STREAMS orders '>' | grep -E "^[0-9]+-[0-9]+$|^oid$|^100[0-9]$"
echo "[c2 读 3 条]"; R XREADGROUP GROUP g1 c2 COUNT 3 STREAMS orders '>' | grep -E "^[0-9]+-[0-9]+$|^oid$|^100[0-9]$"
echo "  ^ 同一条消息只会被组内一个消费者拿到（c1 拿 1001-1003，c2 拿 1004-1005）"

sec "⑤ PEL：已读未确认的消息（Pending Entries List）"
echo "-- XPENDING 概览（总条数 / 最小ID / 最大ID / 各消费者持有数）："
R XPENDING orders g1
echo "-- PEL 明细（ID / 消费者 / 空闲ms / 投递次数）："
R XPENDING orders g1 - + 10

sec "⑥ XACK 确认后 PEL 清空"
echo "确认前 pending 条数：$(R XPENDING orders g1 | head -1)"
# 逐个确认所有 PEL 中的 ID
R XPENDING orders g1 - + 100 | awk 'NR%4==1' | while read -r id; do
  [ -n "$id" ] && R XACK orders g1 "$id" > /dev/null
done
echo "确认后 XPENDING："
R XPENDING orders g1

sec "⑦ 消费者崩溃后的消息转移：XCLAIM"
R XADD orders '*' oid 2001 amount 10 > /dev/null
R XREADGROUP GROUP g1 c1 COUNT 1 STREAMS orders '>' > /dev/null
echo "-- c1 已拿到但未确认，模拟 c1 崩溃"
echo "转移前 PEL："
R XPENDING orders g1 - + 10
VICTIM=$(R XPENDING orders g1 - + 10 | awk 'NR%4==1' | head -1)
echo "-- c2 认领空闲超过 0ms 的消息 $VICTIM："
R XCLAIM orders g1 c2 0 "$VICTIM" | grep -E "^[0-9]+-[0-9]+$|^oid$|^2001$"
echo "转移后 PEL："
R XPENDING orders g1 - + 10

sec "⑧ XTRIM 限制流长度（~ 近似 vs = 精确）"
R DEL tstream > /dev/null
for i in $(seq 1 1000); do R XADD tstream '*' i $i > /dev/null; done
echo "裁剪前长度：$(R XLEN tstream)"
R XTRIM tstream MAXLEN '~' 10 > /dev/null
echo "MAXLEN ~ 10 后长度：$(R XLEN tstream)   （~ 是近似裁剪，按 radix tree 节点整体释放，会多于 10）"
R XTRIM tstream MAXLEN '=' 5 > /dev/null
echo "MAXLEN = 5  后长度：$(R XLEN tstream)   （= 是精确裁剪，但代价更高）"

sec "⑨ XINFO 查看流与组信息"
echo "-- 流："
R XINFO STREAM orders | paste - - | head -8
echo "-- 消费组："
R XINFO GROUPS orders | paste - -

sec "⑩ 内存代价：Stream vs List 存同样 1 万条"
R DEL s:stream s:list > /dev/null
for i in $(seq 1 10000); do R XADD s:stream '*' i $i > /dev/null; done
for i in $(seq 1 10000); do R RPUSH s:list $i > /dev/null; done
echo "Stream 1 万条：$(R MEMORY USAGE s:stream) 字节"
echo "List   1 万条：$(R MEMORY USAGE s:list) 字节"

R shutdown nosave 2>/dev/null
wait $SRV_PID 2>/dev/null
rm -rf $DIR
echo; echo "Stream 实验结束，实例已清理。"
