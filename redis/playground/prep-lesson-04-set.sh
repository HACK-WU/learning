#!/usr/bin/env bash
# 课 4 知识点 1：Set 交并差与去重 —— 实测
PORT=6404
DIR=/tmp/redis-course-l04a
mkdir -p "$DIR"
redis-server --port "$PORT" --daemonize yes --save '' --appendonly no --dir "$DIR" > /dev/null 2>&1
sleep 1

echo "########## 1. 去重：天然幂等 ##########"
redis-cli -p "$PORT" del uv:page:1 > /dev/null
redis-cli -p "$PORT" sadd uv:page:1 u1 u2 u3 > /dev/null
redis-cli -p "$PORT" sadd uv:page:1 u2 u3 u4   # 重复加入 u2 u3
echo "两次 SADD 后 scard = $(redis-cli -p "$PORT" scard uv:page:1) （期望 4，不是 6）"
echo "成员: $(redis-cli -p "$PORT" smembers uv:page:1 | sort | tr '\n' ' ')"

echo ""
echo "########## 2. 交并差三件套 ##########"
redis-cli -p "$PORT" del tag:A tag:B > /dev/null
redis-cli -p "$PORT" sadd tag:A u1 u2 u3 u4 > /dev/null
redis-cli -p "$PORT" sadd tag:B u3 u4 u5 u6 > /dev/null
echo "A = $(redis-cli -p "$PORT" smembers tag:A | sort | tr '\n' ' ')"
echo "B = $(redis-cli -p "$PORT" smembers tag:B | sort | tr '\n' ' ')"
echo "SINTER  A∩B = $(redis-cli -p "$PORT" sinter tag:A tag:B | sort | tr '\n' ' ')"
echo "SUNION  A∪B = $(redis-cli -p "$PORT" sunion tag:A tag:B | sort | tr '\n' ' ')"
echo "SDIFF   A-B = $(redis-cli -p "$PORT" sdiff tag:A tag:B | sort | tr '\n' ' ')"
echo "SDIFF   B-A = $(redis-cli -p "$PORT" sdiff tag:B tag:A | sort | tr '\n' ' ')   <-- 方向敏感！"

echo ""
echo "########## 3. SINTER 到底遍历谁？用 SINTERCARD 看限制 ##########"
# Redis 7.0+ 才有 SINTERCARD
redis-cli -p "$PORT" sintercard 2 tag:A tag:B 2>&1 | head -2

echo ""
echo "########## 4. 最易错点：SINTER vs SINTERSTORE 的语义差异 ##########"
redis-cli -p "$PORT" del dest:inter > /dev/null
redis-cli -p "$PORT" sinterstore dest:inter tag:A tag:B > /dev/null
echo "SINTERSTORE 返回的是结果基数: $(redis-cli -p "$PORT" sinterstore dest:inter tag:A tag:B)"
echo "dest:inter 类型: $(redis-cli -p "$PORT" type dest:inter)"
echo "dest:inter 内容: $(redis-cli -p "$PORT" smembers dest:inter | sort | tr '\n' ' ')"
echo "--- 覆盖行为：把结果存进一个已存在的 String key ---"
redis-cli -p "$PORT" set dest:str "i-am-a-string" > /dev/null
redis-cli -p "$PORT" sinterstore dest:str tag:A tag:B > /dev/null
echo "SINTERSTORE 覆盖 String key 后，type = $(redis-cli -p "$PORT" type dest:str)  <-- 类型被覆盖！"

echo ""
echo "########## 5. 随机抽取：SRANDMEMBER vs SPOP ##########"
redis-cli -p "$PORT" del pool > /dev/null
redis-cli -p "$PORT" sadd pool a b c d e > /dev/null
echo "抽前 scard = $(redis-cli -p "$PORT" scard pool)"
echo "SRANDMEMBER (不删除): $(redis-cli -p "$PORT" srandmember pool 2 | tr '\n' ' ')"
echo "抽后 scard = $(redis-cli -p "$PORT" scard pool)  <-- SRANDMEMBER 不减"
echo "SPOP (删除): $(redis-cli -p "$PORT" spop pool 2 | tr '\n' ' ')"
echo "抽后 scard = $(redis-cli -p "$PORT" scard pool)  <-- SPOP 减 2"

echo ""
echo "########## 6. Set 编码：intset -> listpack -> hashtable ##########"
redis-cli -p "$PORT" del s:int s:str > /dev/null
redis-cli -p "$PORT" sadd s:int 1 2 3 > /dev/null
echo "3 个整数     -> $(redis-cli -p "$PORT" object encoding s:int)"
redis-cli -p "$PORT" del s:int > /dev/null
for i in $(seq 1 600); do redis-cli -p "$PORT" sadd s:int "$i" > /dev/null; done
echo "600 个整数   -> $(redis-cli -p "$PORT" object encoding s:int)  (set-max-intset-entries=512)"
redis-cli -p "$PORT" sadd s:str "hello" > /dev/null
echo "混入字符串后 -> $(redis-cli -p "$PORT" object encoding s:int)  <-- 不可逆！"

echo ""
echo "清理中..."
redis-cli -p "$PORT" shutdown nosave 2>/dev/null
rmdir "$DIR" 2>/dev/null
echo "done"
