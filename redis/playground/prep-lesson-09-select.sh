#!/bin/bash
# 实验 5：生态与选型 —— 在本机实测「Redis 能力边界」，用数据支撑选型判断
set -u
MOD=/usr/lib/redis/modules
DIR=/tmp/redis-l09
mkdir -p $DIR

# 启一个干净实例用于选型对比测试
redis-cli -p 7105 shutdown nosave 2>/dev/null
sleep 0.3
nohup redis-server --port 7105 --bind 127.0.0.1 --dir $DIR --save '' \
  --appendonly no --loadmodule $MOD/redisbloom.so \
  > $DIR/7105.log 2>&1 &
sleep 1
R="redis-cli -p 7105"

echo "================================================================"
echo "  实验 5：选型决策的实测依据"
echo "================================================================"

echo ""
echo "--- (1) 内存效率：同一个业务对象，不同编码的开销 ---"
$R flushall > /dev/null

# 100 万个小 String
echo "  写入 100 万个 String（user:{id} -> 100B value）"
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
def cmd(*a):
    out = [b'*%d\r\n' % len(a)]
    for x in a:
        b = str(x).encode()
        out.append(b'$%d\r\n%s\r\n' % (len(b), b))
    s.sendall(b''.join(out))
for i in range(0, 1000000, 1000):
    batch = b''
    for j in range(1000):
        k = ('user:%d' % (i+j)).encode(); v = b'x'*100
        batch += b'*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n' % (len(k), k, len(v), v)
    s.sendall(batch)
    for _ in range(1000):
        while b'\r\n' not in s.recv(65536):
            pass
PY
echo "  DBSIZE = $($R dbsize)"
$R info memory | grep -E "used_memory_human|used_memory_dataset_human|mem_fragmentation_ratio"

echo ""
echo "  --- 同样 100 万个对象，改用 Hash 分桶存储（hset bucket:{id//1000} {id} val）---"
$R flushall > /dev/null
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
for i in range(0, 1000000, 1000):
    batch = b''
    for j in range(1000):
        uid = i + j
        bkt = uid // 1000
        k = ('bucket:%d' % bkt).encode()
        f = str(uid).encode(); v = b'x'*100
        batch += b'*4\r\n$4\r\nHSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n' % (
            len(k), k, len(f), f, len(v), v)
    s.sendall(batch)
    for _ in range(1000):
        while b'\r\n' not in s.recv(65536):
            pass
PY
echo "  DBSIZE = $($R dbsize)  （1000 个 bucket，每个 1000 字段）"
$R info memory | grep -E "used_memory_human|used_memory_dataset_human|mem_fragmentation_ratio"

echo ""
echo "  ⚠️ 注意：Redis 8 对小 Hash 会用 listpack 编码，这是省内存的关键。"
echo "     但当 field 数超过 hash-max-listpack-entries（默认 128）就退化为 hashtable。"
$R config get hash-max-listpack-entries
$R config get hash-max-listpack-value

echo ""
echo "--- (2) 概率结构 vs 精确结构的内存对比（课 8 布隆的延续）---"
$R flushall > /dev/null
echo "  写入 10 万个 id："
echo "  (a) Set（精确）"
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
for i in range(0, 100000, 1000):
    batch = b''
    for j in range(1000):
        m = ('id:%d' % (i+j)).encode()
        batch += b'*2\r\n$4\r\nSADD\r\n$%d\r\n%s\r\n' % (len(m), m)
    s.sendall(batch)
    for _ in range(1000):
        while b'\r\n' not in s.recv(65536):
            pass
PY
echo "      SCARD = $($R scard idset 2>/dev/null || echo 0)"
# 用 scan 方式统计
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
for i in range(100000):
    m = ('id:%d' % i).encode()
    s.sendall(b'*3\r\n$4\r\nSADD\r\n$5\r\nidset\r\n$%d\r\n%s\r\n' % (len(m), m))
    s.recv(65536)
PY
echo "      SCARD = $($R scard idset)"
echo "      MEMORY USAGE idset = $($R memory usage idset) bytes"

$R flushall > /dev/null
echo "  (b) 布隆过滤器（概率，允许误判）"
$R bf.reserve idfilter 0.001 100000 > /dev/null
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
for i in range(100000):
    m = ('id:%d' % i).encode()
    s.sendall(b'*3\r\n$6\r\nBF.ADD\r\n$9\r\nidfilter\r\n$%d\r\n%s\r\n' % (len(m), m))
    s.recv(65536)
PY
echo "      MEMORY USAGE idfilter = $($R memory usage idfilter) bytes"
set_u=$($R memory usage idset 2>/dev/null)
echo ""
echo "  → 精确 vs 概率的内存差距（10 万元素）"

echo ""
echo "--- (3) 什么时候 Redis 不是答案：全量扫描型查询 ---"
$R flushall > /dev/null
echo "  写入 10 万条带数值的记录（模拟「订单金额」）"
python3 - <<'PY'
import socket
s = socket.create_connection(('127.0.0.1', 7105))
for i in range(0, 100000, 1000):
    batch = b''
    for j in range(1000):
        uid = i + j
        k = ('order:%d' % uid).encode()
        v = ('{"uid":%d,"amount":%d,"city":"city%d"}' % (uid, uid % 10000, uid % 50)).encode()
        batch += b'*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n' % (len(k), k, len(v), v)
    s.sendall(batch)
    for _ in range(1000):
        while b'\r\n' not in s.recv(65536):
            pass
PY
echo "  DBSIZE = $($R dbsize)"
echo ""
echo "  需求：找出 amount > 9000 的所有订单"
echo "  (a) Redis 原生：必须把 10 万条全部取回客户端再过滤"
/usr/bin/time -f "      耗时 %e 秒" $R --scan --count 1000 > /dev/null 2>/tmp/t1
python3 - <<'PY'
import socket, time
s = socket.create_connection(('127.0.0.1', 7105))
t0 = time.time()
# 模拟：先 SCAN 出所有 key，再 MGET 全部，再在客户端过滤
cursor = b'0'
keys = []
while True:
    s.sendall(b'*3\r\n$4\r\nSCAN\r\n$%d\r\n%s\r\n$5\r\nCOUNT\r\n$4\r\n1000\r\n' % (len(cursor), cursor))
    # 读 array of 2
    def read_reply():
        buf = b''
        while b'\r\n' not in buf:
            buf += s.recv(65536)
        line, rest = buf.split(b'\r\n', 1)
        t, v = line[:1], line[1:]
        if t == b'*':
            n = int(v)
            return [read_reply_r(rest) for _ in range(n)], rest
    # 简化：直接用 redis-cli 做
    break
print("      (用 redis-cli 实测)")
PY

echo "  (b) 用 RediSearch 建立索引后查询"
$R ft.create orderidx ON hash PREFIX 1 "ord:" SCHEMA amount NUMERIC SORTABLE city TAG 2>/dev/null
echo "      （需要数据存为 Hash 才能建索引，这里说明结构约束）"

echo ""
echo "  实测：把 10 万条 JSON 全量取回客户端过滤"
python3 - <<'PY'
import socket, time, json
s = socket.create_connection(('127.0.0.1', 7105))
def send(*args):
    out = [b'*%d\r\n' % len(args)]
    for a in args:
        b = a.encode() if isinstance(a, str) else str(a).encode()
        out.append(b'$%d\r\n%s\r\n' % (len(b), b))
    s.sendall(b''.join(out))
    return s.recv(65536)
t0 = time.time()
matched = 0
for i in range(100000):
    r = send('GET', 'order:%d' % i)
    # 简化解析：只看长度
    if b'amount":9' in r or (len(r) > 40 and r.split(b'\r\n')[1][-12:].startswith(b'{"uid"')):
        pass
    try:
        body = r.split(b'\r\n', 2)[2].rsplit(b'\r\n', 2)[0]
        d = json.loads(body)
        if d['amount'] > 9000:
            matched += 1
    except Exception:
        pass
dt = time.time() - t0
print("      全量扫描 10 万条并过滤：耗时 %.2f 秒，命中 %d 条" % (dt, matched))
print("      → 这类「按条件筛选」的需求，Redis 原生做是 O(N) 全量传输，")
print("        数据库里一条 SQL 加索引就能解决。这就是「不该用 Redis」的信号。")
PY

echo ""
echo "================================================================"
echo "  实验 5 完成"
echo "================================================================"
