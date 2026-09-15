# -*- coding: utf-8 -*-
"""课 13 实验 1b（修正版）：实验 A 取值修正 + G/H 重跑 + VACUUM 抓锁
严格规则：每次 send 后必须 collect，避免输出缓冲错位
"""
import subprocess, time

ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}


class Psql:
    def __init__(self, name):
        self.p = subprocess.Popen(
            ["docker", "exec", "-i", "pg17", "psql", "-U", "postgres",
             "-d", "order_service", "-X", "-q", "-v", "ON_ERROR_STOP=0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1, env=ENV)

    def run(self, sql, timeout=60):
        self.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
        self.p.stdin.flush()
        out, deadline = [], time.time() + timeout
        while time.time() < deadline:
            line = self.p.stdout.readline()
            if not line:
                break
            if line.strip() == "@@END@@":
                break
            out.append(line.rstrip("\n"))
        return "\n".join(x for x in out if x.strip())

    def send(self, sql):
        self.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
        self.p.stdin.flush()

    def collect(self, timeout=60):
        out, deadline = [], time.time() + timeout
        while time.time() < deadline:
            line = self.p.stdout.readline()
            if not line:
                break
            if line.strip() == "@@END@@":
                break
            out.append(line.rstrip("\n"))
        return "\n".join(x for x in out if x.strip())


def hdr(t):
    print("\n" + "=" * 78 + "\n" + t + "\n" + "=" * 78)


def show(r, indent="  "):
    for line in r.split("\n"):
        if line.strip():
            print(indent + line)


def val(r):
    """从 psql 输出里取出数据行（去掉表头/分隔/(N rows)）"""
    lines = [x.strip() for x in r.split("\n") if x.strip()]
    if len(lines) >= 4:
        return lines[-2]
    if lines:
        return lines[-1]
    return "?"


OBS = Psql("OBS")
HOLDER = Psql("HOLDER")
WAITER = Psql("WAITER")

Q_WAIT = r"""
SELECT a.pid, a.wait_event_type, a.wait_event,
       left(regexp_replace(a.query, '\s+', ' ', 'g'), 52) AS query_head,
       pg_blocking_pids(a.pid) AS blocked_by
FROM pg_stat_activity a
WHERE a.datname='order_service' AND a.pid <> pg_backend_pid()
  AND a.state='active' AND a.wait_event_type IS NOT NULL ORDER BY a.pid;
"""

# ================= 实验 A（修正取值）=================
hdr("实验 A · 各命令在 finance.accounts 上自动获取的表级锁")
print("  （BEGIN → 执行命令 → 查 pg_locks → ROLLBACK）\n")

def probe(label, stmt):
    r = OBS.run(r"""
BEGIN;
%s
SELECT coalesce(string_agg(mode,' + ' ORDER BY mode),'(none)') AS locks
FROM (SELECT DISTINCT mode FROM pg_locks WHERE relation='finance.accounts'::regclass AND granted) x;
ROLLBACK;
""" % stmt, 60)
    print("  %-30s → %s" % (label, val(r)))

probe("SELECT", "SELECT count(*) FROM finance.accounts;")
probe("UPDATE", "UPDATE finance.accounts SET balance = balance WHERE id = 1;")
probe("DELETE", "DELETE FROM finance.accounts WHERE id = 99;")
probe("INSERT", "INSERT INTO finance.accounts VALUES (99,'tmp',1);")
probe("SELECT FOR UPDATE", "SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE;")
probe("SELECT FOR NO KEY UPDATE", "SELECT * FROM finance.accounts WHERE id = 1 FOR NO KEY UPDATE;")
probe("SELECT FOR SHARE", "SELECT * FROM finance.accounts WHERE id = 1 FOR SHARE;")
probe("SELECT FOR KEY SHARE", "SELECT * FROM finance.accounts WHERE id = 1 FOR KEY SHARE;")
probe("CREATE INDEX", "CREATE INDEX idx_tmp_owner ON finance.accounts(owner);")
probe("ALTER TABLE ADD COLUMN", "ALTER TABLE finance.accounts ADD COLUMN tmp_c int;")
probe("TRUNCATE", "TRUNCATE finance.accounts;")
probe("ANALYZE", "ANALYZE finance.accounts;")
probe("LOCK TABLE（不写模式）", "LOCK TABLE finance.accounts;")
probe("CREATE TRIGGER 类（SHARE ROW EXCL）", "LOCK TABLE finance.accounts IN SHARE ROW EXCLUSIVE MODE;")

print("\n  --- 显式 LOCK TABLE 八种模式 ---")
for m in ["ACCESS SHARE", "ROW SHARE", "ROW EXCLUSIVE", "SHARE UPDATE EXCLUSIVE",
          "SHARE", "SHARE ROW EXCLUSIVE", "EXCLUSIVE", "ACCESS EXCLUSIVE"]:
    r = OBS.run(r"""
BEGIN;
LOCK TABLE finance.accounts IN %s MODE;
SELECT coalesce(string_agg(mode,' + ' ORDER BY mode),'(none)')
FROM (SELECT DISTINCT mode FROM pg_locks WHERE relation='finance.accounts'::regclass AND granted) x;
ROLLBACK;
""" % m, 40)
    print("  %-42s → %s" % ("LOCK TABLE ... IN " + m + " MODE", val(r)))

# ================= VACUUM 抓锁 =================
hdr("实验 A-2 · VACUUM 的锁（大表 100 万行，高频轮询抓拍）")
HOLDER.send("VACUUM (ANALYZE) finance.orders_big;")
hits = []
for _ in range(40):
    r = OBS.run(r"""
SELECT mode, granted FROM pg_locks
WHERE relation='finance.orders_big'::regclass AND pid <> pg_backend_pid();""", 5)
    if "ShareUpdateExclusiveLock" in r:
        hits.append(r.strip().replace("\n", " | "))
        break
    time.sleep(0.02)
print("  抓拍结果：", hits[0] if hits else "(VACUUM 太快，未抓到 —— 见下方官方结论)")
print(HOLDER.collect(90))
print("  → 官方：VACUUM（不带 FULL）获取 SHARE UPDATE EXCLUSIVE（PG 17 docs 13.3.1）")

# ================= 实验 G（重跑，先 RESET）=================
hdr("实验 G · NOWAIT：不等，直接报错（SQLSTATE 55P03）")
print(WAITER.run("RESET lock_timeout; SHOW lock_timeout;", 20))
HOLDER.send("BEGIN; SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE; SELECT 'HOLDER 锁住 id=1' AS note;")
print("  HOLDER:", val(HOLDER.collect(20)))
print("\n  G-1 NOWAIT（应立即报错）：")
show(WAITER.run("SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE NOWAIT;", 15), "  ")
print("  G-2 不带 NOWAIT（应阻塞）：")
WAITER.send(r"""\timing on
SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE;""")
time.sleep(3)
show(OBS.run(Q_WAIT, 20), "  ")
show(OBS.run(r"""
SELECT l.pid, l.locktype, l.mode, l.granted, coalesce(c.relname,'') AS rel,
       pg_blocking_pids(l.pid) AS blocked_by
FROM pg_locks l LEFT JOIN pg_class c ON c.oid=l.relation
WHERE l.database=(SELECT oid FROM pg_database WHERE datname='order_service')
  AND l.pid <> pg_backend_pid() ORDER BY l.granted DESC, l.pid;""", 20), "  ")
HOLDER.send("ROLLBACK;")
print("\n  HOLDER ROLLBACK 后 WAITER：")
show(WAITER.collect(25), "  ")
print(HOLDER.collect(20))

# ================= 实验 H（重跑 SKIP LOCKED）=================
hdr("实验 H · SKIP LOCKED：跳过被锁的行（队列场景）")
print(WAITER.run("\\timing off", 10))
HOLDER.send("BEGIN; SELECT id FROM finance.task_queue WHERE id <= 2 FOR UPDATE; SELECT 'HOLDER 锁住 task 1,2' AS note;")
print("  HOLDER:", val(HOLDER.collect(20)))
print("\n  H-1 不带 SKIP LOCKED 的全表 FOR UPDATE（应阻塞）：")
WAITER.send("SELECT id, payload FROM finance.task_queue ORDER BY id FOR UPDATE;")
time.sleep(3)
show(OBS.run(Q_WAIT, 20), "  ")
HOLDER.send("ROLLBACK;")
print("  HOLDER ROLLBACK 后返回：")
show(WAITER.collect(25), "  ")
print(HOLDER.collect(20))
print("\n  H-2 重新持锁，用 SKIP LOCKED：")
HOLDER.send("BEGIN; SELECT id FROM finance.task_queue WHERE id <= 2 FOR UPDATE; SELECT 'HOLDER 锁住 1,2' AS note;")
print("  HOLDER:", val(HOLDER.collect(20)))
show(WAITER.run("SELECT id, payload FROM finance.task_queue ORDER BY id FOR UPDATE SKIP LOCKED;", 20),
     "  SKIP LOCKED 结果（应只剩 3,4,5）: ")
HOLDER.send("ROLLBACK;")
print(HOLDER.collect(20))

hdr("实验 1b 结束")
