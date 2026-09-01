#!/usr/bin/env bash
# 课 4 知识点 1 补充：Set 编码转换的精确阈值（管道批量写入，避免循环开销）
PORT=6404
DIR=/tmp/redis-course-l04a2
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "=== 阈值配置 ==="
echo "set-max-intset-entries = $(redis-cli -p "$PORT" config get set-max-intset-entries | tail -1)"
echo "set-max-listpack-entries = $(redis-cli -p "$PORT" config get set-max-listpack-entries | tail -1)"
echo "set-max-listpack-value = $(redis-cli -p "$PORT" config get set-max-listpack-value | tail -1)"

echo ""
echo "=== 场景 A：全是整数，逐步增大基数 ==="
for n in 100 512 513 1000; do
  redis-cli -p "$PORT" del s:int > /dev/null
  seq 1 "$n" | redis-cli -p "$PORT" -x sadd s:int > /dev/null 2>&1
  # -x sadd 会把整块当成一个成员，改用管道
  redis-cli -p "$PORT" del s:int > /dev/null
  seq 1 "$n" | sed "s/^/sadd s:int /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  echo "  $n 个整数 -> $(redis-cli -p "$PORT" object encoding s:int)  (实际 scard=$(redis-cli -p "$PORT" scard s:int))"
done

echo ""
echo "=== 场景 B：全是字符串（非整数），逐步增大基数 ==="
for n in 100 128 129 200; do
  redis-cli -p "$PORT" del s:str > /dev/null
  seq 1 "$n" | sed "s/^/sadd s:str m/" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
  echo "  $n 个字符串 -> $(redis-cli -p "$PORT" object encoding s:str)  (实际 scard=$(redis-cli -p "$PORT" scard s:str))"
done

echo ""
echo "=== 场景 C：整数集合混入一个长字符串（超 set-max-listpack-value=64）==="
redis-cli -p "$PORT" del s:mix > /dev/null
seq 1 10 | sed "s/^/sadd s:mix /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  10 个整数 -> $(redis-cli -p "$PORT" object encoding s:mix)"
redis-cli -p "$PORT" sadd s:mix "$(printf 'x%.0s' $(seq 1 70))" > /dev/null
echo "  混入 70 字节字符串 -> $(redis-cli -p "$PORT" object encoding s:mix)  <-- value 阈值触发"

echo ""
echo "=== 场景 D：不可逆性验证（删回小数后能否转回）==="
redis-cli -p "$PORT" del s:irr > /dev/null
seq 1 600 | sed "s/^/sadd s:irr /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  600 个整数 -> $(redis-cli -p "$PORT" object encoding s:irr)"
for i in $(seq 101 600); do redis-cli -p "$PORT" srem s:irr "$i" > /dev/null; done
echo "  删到只剩 100 个 -> $(redis-cli -p "$PORT" object encoding s:irr)  (scard=$(redis-cli -p "$PORT" scard s:irr))"

echo ""
echo "=== 场景 E：intset 是否真的双向（删到阈值内能否转回 intset）==="
redis-cli -p "$PORT" del s:irr2 > /dev/null
seq 1 600 | sed "s/^/sadd s:irr2 /" | redis-cli -p "$PORT" --pipe > /dev/null 2>&1
echo "  600 个整数 -> $(redis-cli -p "$PORT" object encoding s:irr2)"
for i in $(seq 100 600); do redis-cli -p "$PORT" srem s:irr2 "$i" > /dev/null; done
echo "  删到只剩 99 个 -> $(redis-cli -p "$PORT" object encoding s:irr2)  (scard=$(redis-cli -p "$PORT" scard s:irr2))"

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
