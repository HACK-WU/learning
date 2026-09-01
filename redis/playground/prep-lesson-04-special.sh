#!/usr/bin/env bash
# 课 4 知识点 3：Bitmap / HyperLogLog / Geo —— 实测
PORT=6404
DIR=/tmp/redis-course-l04c
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "########## 1. Bitmap：本质是 String，按位操作 ##########"
redis-cli -p "$PORT" del sign:2026-09 > /dev/null
redis-cli -p "$PORT" setbit sign:2026-09 0 1 > /dev/null
echo "SETBIT 后 type = $(redis-cli -p "$PORT" type sign:2026-09)  <-- 是 string！"
echo "strlen = $(redis-cli -p "$PORT" strlen sign:2026-09) 字节"
# 标记用户 3、8、100 签到
redis-cli -p "$PORT" setbit sign:2026-09 3 1 > /dev/null
redis-cli -p "$PORT" setbit sign:2026-09 8 1 > /dev/null
redis-cli -p "$PORT" setbit sign:2026-09 100 1 > /dev/null
echo "标记用户 3/8/100 后 BITCOUNT = $(redis-cli -p "$PORT" bitcount sign:2026-09)"
echo "strlen 增长到 = $(redis-cli -p "$PORT" strlen sign:2026-09) 字节  <-- 最高位 100 -> ceil(101/8)=13 字节"
echo "GETBIT 用户 100 = $(redis-cli -p "$PORT" getbit sign:2026-09 100)"
echo "GETBIT 用户 101 = $(redis-cli -p "$PORT" getbit sign:2026-09 101)  <-- 未设置默认 0"

echo ""
echo "--- Bitmap 空间对比：100 万用户签到 ---"
redis-cli -p "$PORT" del sign:1m > /dev/null
# 标记 100 万个用户中的一部分
for i in $(seq 1 1000); do redis-cli -p "$PORT" setbit sign:1m $((RANDOM * 1000)) 1 > /dev/null; done
redis-cli -p "$PORT" setbit sign:1m 999999 1 > /dev/null
echo "100 万位图最大偏移 999999 时，内存 = $(redis-cli -p "$PORT" memory usage sign:1m) 字节 ≈ 125 KB"
echo "  对照：若用 Set 存 100 万个整数用户ID，约需数十 MB（此处理论值，下方可实测）"

echo ""
echo "--- Set 存 100 万整数（对照）---"
redis-cli -p "$PORT" del uv:set > /dev/null
seq 1 1000000 | sed "s/^/sadd uv:set /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "Set 100 万整数 scard=$(redis-cli -p "$PORT" scard uv:set), 编码=$(redis-cli -p "$PORT" object encoding uv:set)"
echo "Set 内存 = $(redis-cli -p "$PORT" memory usage uv:set | awk '{printf "%.2f MB", $1/1024/1024}')"
echo "Bitmap 内存 = $(redis-cli -p "$PORT" memory usage sign:1m | awk '{printf "%.2f MB", $1/1024/1024}')"

echo ""
echo "--- BITOP 交并差（用户留存场景）---"
redis-cli -p "$PORT" del d1 d2 > /dev/null
redis-cli -p "$PORT" setbit d1 1 1 > /dev/null; redis-cli -p "$PORT" setbit d1 2 1 > /dev/null; redis-cli -p "$PORT" setbit d1 3 1 > /dev/null
redis-cli -p "$PORT" setbit d2 2 1 > /dev/null; redis-cli -p "$PORT" setbit d2 3 1 > /dev/null; redis-cli -p "$PORT" setbit d2 4 1 > /dev/null
redis-cli -p "$PORT" bitop and d:both d1 d2 > /dev/null
echo "d1={1,2,3} d2={2,3,4}"
echo "BITOP AND (两日都来) bitcount = $(redis-cli -p "$PORT" bitcount d:both)"
redis-cli -p "$PORT" bitop or d:either d1 d2 > /dev/null
echo "BITOP OR  (任一日来) bitcount = $(redis-cli -p "$PORT" bitcount d:either)"

echo ""
echo "########## 2. HyperLogLog：有误差的计数 ##########"
redis-cli -p "$PORT" del hll:uv > /dev/null
echo "--- 加入 100 万个不同元素 ---"
seq 1 1000000 | sed "s/^/pfadd hll:uv u/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "PFCOUNT = $(redis-cli -p "$PORT" pfcount hll:uv)  (真实值 1000000)"
echo "误差 = $(awk "BEGIN{printf \"%.3f%%\", (1000000-$(redis-cli -p "$PORT" pfcount hll:uv))/1000000*100}")"
echo "HLL 内存 = $(redis-cli -p "$PORT" memory usage hll:uv) 字节  <-- 固定约 12KB"
echo "type = $(redis-cli -p "$PORT" type hll:uv)"

echo ""
echo "--- HLL 误差随规模变化（官方标准误差 0.81%）---"
for n in 1000 10000 100000; do
  k="hll:t:$n"
  redis-cli -p "$PORT" del "$k" > /dev/null
  seq 1 "$n" | sed "s/^/pfadd $k v/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  c=$(redis-cli -p "$PORT" pfcount "$k")
  echo "  n=$n -> PFCOUNT=$c, 误差=$(awk "BEGIN{printf \"%.2f%%\", ($n-$c)/$n*100}")"
done

echo ""
echo "--- HLL 不能取元素（与 Set 的本质区别）---"
echo "尝试 SMEMBERS 式操作：HLL 无此命令，只能 PFCOUNT / PFMERGE"
echo "PFMERGE 多天合并去重："
redis-cli -p "$PORT" del hll:d1 hll:d2 > /dev/null
seq 1 5000 | sed "s/^/pfadd hll:d1 x/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
seq 2500 7500 | sed "s/^/pfadd hll:d2 x/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  day1=$(redis-cli -p "$PORT" pfcount hll:d1), day2=$(redis-cli -p "$PORT" pfcount hll:d2)"
redis-cli -p "$PORT" pfmerge hll:week hll:d1 hll:d2 > /dev/null
echo "  合并后 PFCOUNT=$(redis-cli -p "$PORT" pfcount hll:week) (真实去重值 7500)"

echo ""
echo "########## 3. Geo：底层是 ZSet ##########"
redis-cli -p "$PORT" del geo:cities > /dev/null
redis-cli -p "$PORT" geoadd geo:cities 116.4074 39.9042 北京 > /dev/null
redis-cli -p "$PORT" geoadd geo:cities 121.4737 31.2304 上海 > /dev/null
redis-cli -p "$PORT" geoadd geo:cities 113.2644 23.1291 广州 > /dev/null
echo "GEOADD 后 type = $(redis-cli -p "$PORT" type geo:cities)  <-- 是 zset！"
echo "底层编码 = $(redis-cli -p "$PORT" object encoding geo:cities)"
echo "--- 用 ZSet 命令直接操作 Geo ---"
echo "ZRANGE 看到的是 geohash 编码后的分数："
redis-cli -p "$PORT" zrange geo:cities 0 -1 withscores
echo "GEOPOS 北京 = $(redis-cli -p "$PORT" geopos geo:cities 北京 | tr '\n' ' ')"
echo "--- GEODIST 算距离 ---"
echo "北京-上海距离 = $(redis-cli -p "$PORT" geodist geo:cities 北京 上海 km) km"
echo "--- GEORADIUS / GEOSEARCH（6.2+ 推荐 GEOSEARCH）---"
echo "GEORADIUSBYMEMBER(旧): 北京 1000km 内 = $(redis-cli -p "$PORT" georadiusbymember geo:cities 北京 1000 km | tr '\n' ' ')"
echo "GEOSEARCH(新): 北京 1000km 内 = $(redis-cli -p "$PORT" geosearch geo:cities frommember 北京 byradius 1000 km | tr '\n' ' ')"

echo ""
echo "--- Geo 精度陷阱：极坐标公式 ---"
echo "GEODIST 默认单位 m；用 km 需显式指定"
echo "北京-广州 = $(redis-cli -p "$PORT" geodist geo:cities 北京 广州 km) km"
echo "--- 删除用 ZREM（因为底层是 ZSet）---"
redis-cli -p "$PORT" zrem geo:cities 广州 > /dev/null
echo "ZREM 删除广州后，成员数 = $(redis-cli -p "$PORT" zcard geo:cities)"

echo ""
echo "清理中..."
redis-cli -p "$PORT" flushall > /dev/null
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
