# -*- coding: utf-8 -*-
"""课 13 实验 1：表级锁（各命令自动获取的锁模式 + 冲突矩阵实测）
三会话模型：HOLDER(持锁) / WAITER(被阻塞) / OBS(观察者，永远不被阻塞)
"""
import subprocess, time

ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}


class Psql:
    def __init__(self, name):
        self.name = name
        self.p = subprocess.Popen(
            ["docker", "exec", "-i", "pg17", "psql", "-U", "postgres",
             "-d", "order_service", "-X", "-q", "-v", "ON_ERROR_STOP=0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1, env=ENV)

    def run(self, sql, timeout=40):
        try:
            self.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
            self.p.stdin.flush()
        except Exception as e:
            return "[write error] %s" % e
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

    def collect(self, timeout=40):
        out, deadline = [], time.time() + timeout
        while time.time() < deadline:
            line = self.p.stdout.readline()
            if not line:
                break
            if line.strip() == "@@END@@":
                break
            out.append(line.rstrip("\n"))
        return "\n".join(x for x in out if x.strip())

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass


def hdr(t):
    print("\n" + "=" * 78)
    print(t)
    print("=" * 78)


def show(r, indent="  "):
    for line in r.split("\n"):
        if line.strip():
            print(indent + line)


OBS = Psql("OBS")
HOLDER = Psql("HOLDER")
WAITER = Psql("WAITER")

Q_WAIT = r"""
SELECT a.pid, a.state, a.wait_event_type, a.wait_event,
       left(regexp_replace(a.query, '\s+', ' ', 'g'), 58) AS query_head,
       pg_blocking_pids(a.pid) AS blocked_by
FROM pg_stat_activity a
WHERE a.datname = 'order_service' AND a.pid <> pg_backend_pid()
  AND a.state = 'active' AND a.wait_event_type IS NOT NULL
ORDER BY a.pid;
"""

Q_LOCKS = r"""
SELECT l.pid, l.locktype, l.mode, l.granted,
       coalesce(c.relname, '') AS rel,
       pg_blocking_pids(l.pid) AS blocked_by
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
WHERE l.database = (SELECT oid FROM pg_database WHERE datname = 'order_service')
  AND l.pid <> pg_backend_pid()
ORDER BY l.granted DESC, l.pid, l.mode;
"""

# ---------- setup ----------
hdr("SETUP · 建表")
show(OBS.run(r"""
DROP TABLE IF EXISTS finance.accounts, finance.task_queue, finance.inventory;
CREATE TABLE finance.accounts (id int PRIMARY KEY, owner text, balance numeric(12,2) NOT NULL DEFAULT 0, CHECK (balance >= 0));
INSERT INTO finance.accounts VALUES (1,'alice',1000.00),(2,'bob',1000.00),(3,'carol',1000.00);
CREATE TABLE finance.inventory (id int PRIMARY KEY, name text, qty int NOT NULL);
INSERT INTO finance.inventory VALUES (1,'phone',100),(2,'laptop',50);
CREATE TABLE finance.task_queue (id serial PRIMARY KEY, payload text, status text DEFAULT 'pending');
INSERT INTO finance.task_queue (payload) SELECT 'task-'||g FROM generate_series(1,5) g;
ANALYZE finance.accounts;
SELECT count(*) AS accounts FROM finance.accounts;
""", 60))

# ---------- 实验 A：各命令自动获取的表级锁 ----------
hdr("实验 A · 各命令在 finance.accounts 上自动获取的表级锁")
print("  （单会话：BEGIN → 执行命令 → 查 pg_locks → ROLLBACK）\n")


def probe(label, stmt):
    sql = r"""
BEGIN;
%s
SELECT coalesce(string_agg(mode, ' + ' ORDER BY mode), '(none)') AS locks
FROM (SELECT DISTINCT mode FROM pg_locks WHERE relation = 'finance.accounts'::regclass AND granted) x;
ROLLBACK;
""" % stmt
    r = OBS.run(sql, 40).strip()
    lines = [x for x in r.split("\n") if x.strip()]
    print("  %-32s → %s" % (label, lines[-1].strip() if lines else "?"))


probe("SELECT", "SELECT count(*) FROM finance.accounts;")
probe("UPDATE", "UPDATE finance.accounts SET balance = balance WHERE id = 1;")
probe("INSERT", "INSERT INTO finance.accounts VALUES (99,'tmp',1);")
probe("DELETE", "DELETE FROM finance.accounts WHERE id = 99;")
probe("SELECT FOR UPDATE", "SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE;")
probe("SELECT FOR SHARE", "SELECT * FROM finance.accounts WHERE id = 1 FOR SHARE;")
probe("SELECT FOR NO KEY UPDATE", "SELECT * FROM finance.accounts WHERE id = 1 FOR NO KEY UPDATE;")
probe("SELECT FOR KEY SHARE", "SELECT * FROM finance.accounts WHERE id = 1 FOR KEY SHARE;")
probe("CREATE INDEX", "CREATE INDEX idx_tmp_owner ON finance.accounts(owner);")
probe("ALTER TABLE ADD COLUMN", "ALTER TABLE finance.accounts ADD COLUMN tmp_c int;")
probe("TRUNCATE", "TRUNCATE finance.accounts;")
probe("LOCK TABLE (不写模式 = 默认)", "LOCK TABLE finance.accounts;")
probe("VACUUM 之外：ANALYZE", "ANALYZE finance.accounts;")

print("\n  --- 显式 LOCK TABLE 八种模式全列 ---")
for m in ["ACCESS SHARE", "ROW SHARE", "ROW EXCLUSIVE", "SHARE UPDATE EXCLUSIVE",
          "SHARE", "SHARE ROW EXCLUSIVE", "EXCLUSIVE", "ACCESS EXCLUSIVE"]:
    r = OBS.run(r"""
BEGIN;
LOCK TABLE finance.accounts IN %s MODE;
SELECT coalesce(string_agg(mode,' + ' ORDER BY mode),'(none)') FROM (SELECT DISTINCT mode FROM pg_locks WHERE relation='finance.accounts'::regclass AND granted) x;
ROLLBACK;
""" % m, 30).strip()
    lines = [x for x in r.split("\n") if x.strip()]
    print("  LOCK TABLE ... IN %-24s → %s" % (m + " MODE", lines[-1].strip() if lines else "?"))

# ---------- 实验 B：ACCESS EXCLUSIVE 阻塞 SELECT ----------
hdr("实验 B · ACCESS EXCLUSIVE 是唯一能阻塞纯 SELECT 的模式（官方 Tip 实测）")
HOLDER.send(r"""
BEGIN;
LOCK TABLE finance.accounts IN ACCESS EXCLUSIVE MODE;
SELECT 'HOLDER 已持有 ACCESS EXCLUSIVE' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")

t0 = time.time()
WAITER.send("SELECT id, balance FROM finance.accounts WHERE id = 1;")
time.sleep(3)
hdr("  3 秒后 OBS 观察（SELECT 应该仍在等待）")
show(OBS.run(Q_WAIT, 20), "  ")
show(OBS.run(Q_LOCKS, 20), "  ")

HOLDER.send("ROLLBACK;")
r = WAITER.collect(25)
print("\n  HOLDER ROLLBACK 后，WAITER 的结果（等了 %.1f 秒）：" % (time.time() - t0))
show(r, "  ")

# ---------- 实验 C：ROW EXCLUSIVE 之间不冲突 ----------
hdr("实验 C · ROW EXCLUSIVE 之间不冲突（两个会话同时 UPDATE 不同行）")
HOLDER.send(r"""
BEGIN;
UPDATE finance.accounts SET balance = balance - 100 WHERE id = 1;
SELECT 'HOLDER 改了 id=1，未提交' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")
r = WAITER.run(r"""
BEGIN;
UPDATE finance.accounts SET balance = balance - 100 WHERE id = 2;
SELECT 'WAITER 改 id=2 成功（没被阻塞）' AS note;
ROLLBACK;
""", 25)
show(r, "  WAITER: ")
HOLDER.send("ROLLBACK;")
HOLDER.collect(15)

# ---------- 实验 D：SHARE（CREATE INDEX 非 CONCURRENTLY）----------
hdr("实验 D · SHARE 模式：阻塞写入，但不阻塞读")
HOLDER.send(r"""
BEGIN;
LOCK TABLE finance.accounts IN SHARE MODE;
SELECT 'HOLDER 持有 SHARE' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")

print("\n  D-1 读（SELECT）应畅通：")
show(WAITER.run("SELECT count(*) AS cnt FROM finance.accounts;", 12), "  ")
print("  D-2 写（UPDATE）应被阻塞：")
WAITER.send("UPDATE finance.accounts SET balance = balance WHERE id = 3;")
time.sleep(3)
show(OBS.run(Q_WAIT, 20), "  ")
show(OBS.run(Q_LOCKS, 20), "  ")
HOLDER.send("ROLLBACK;")
print("\n  HOLDER ROLLBACK 后 WAITER：")
show(WAITER.collect(25), "  ")

# ---------- 实验 E：SHARE UPDATE EXCLUSIVE 不阻塞读写 ----------
hdr("实验 E · SHARE UPDATE EXCLUSIVE（VACUUM/ANALYZE/CREATE INDEX CONCURRENTLY 用的模式）")
HOLDER.send(r"""
BEGIN;
LOCK TABLE finance.accounts IN SHARE UPDATE EXCLUSIVE MODE;
SELECT 'HOLDER 持有 SHARE UPDATE EXCLUSIVE' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")
print("  E-1 读：")
show(WAITER.run("SELECT count(*) AS cnt FROM finance.accounts;", 12), "  ")
print("  E-2 写：")
show(WAITER.run("UPDATE finance.accounts SET balance = balance WHERE id = 3; SELECT '写成功，没被阻塞' AS note;", 15), "  ")
print("  E-3 第二个会话也想拿 SHARE UPDATE EXCLUSIVE（自我冲突 → 应阻塞）：")
WAITER.send("BEGIN; LOCK TABLE finance.accounts IN SHARE UPDATE EXCLUSIVE MODE; SELECT '拿到' AS note;")
time.sleep(3)
show(OBS.run(Q_WAIT, 20), "  ")
HOLDER.send("ROLLBACK;")
print("  HOLDER ROLLBACK 后 WAITER：")
show(WAITER.collect(20), "  ")
WAITER.send("ROLLBACK;")
WAITER.collect(15)

# ---------- 实验 F：lock_timeout ----------
hdr("实验 F · lock_timeout 实测（等锁超时报错，而不是无限等）")
HOLDER.send(r"""
BEGIN;
LOCK TABLE finance.accounts IN ACCESS EXCLUSIVE MODE;
SELECT 'HOLDER 持有 ACCESS EXCLUSIVE' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")
r = WAITER.run(r"""
SET lock_timeout = '2s';
\timing on
SELECT id FROM finance.accounts WHERE id = 1;
""", 30)
print("  WAITER（lock_timeout=2s）：")
show(r, "  ")
HOLDER.send("ROLLBACK;")
HOLDER.collect(15)

# ---------- 实验 G：NOWAIT ----------
hdr("实验 G · NOWAIT：不等，直接报错")
HOLDER.send(r"""
BEGIN;
SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE;
SELECT 'HOLDER 锁住 id=1 这一行' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")
print("  G-1 SELECT FOR UPDATE NOWAIT：")
show(WAITER.run("SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE NOWAIT;", 15), "  ")
print("  G-2 SELECT FOR UPDATE（默认会等）：")
WAITER.send("SELECT * FROM finance.accounts WHERE id = 1 FOR UPDATE;")
time.sleep(2.5)
show(OBS.run(Q_WAIT, 20), "  ")
HOLDER.send("ROLLBACK;")
print("  HOLDER ROLLBACK 后 WAITER：")
show(WAITER.collect(20), "  ")

# ---------- 实验 H：SKIP LOCKED ----------
hdr("实验 H · SKIP LOCKED：跳过被锁的行（队列场景）")
HOLDER.send(r"""
BEGIN;
SELECT id FROM finance.task_queue WHERE id <= 2 FOR UPDATE;
SELECT 'HOLDER 锁住 task 1,2' AS note;
""")
show(HOLDER.collect(20), "  HOLDER: ")
print("  H-1 普通 SELECT FOR UPDATE（应阻塞）：")
WAITER.send("SELECT id FROM finance.task_queue ORDER BY id FOR UPDATE;")
time.sleep(2.5)
show(OBS.run(Q_WAIT, 20), "  ")
print("  H-2 换成 SKIP LOCKED：")
HOLDER.send("ROLLBACK;")
show(WAITER.collect(20), "  (上面那条解除阻塞后返回) ")
show(WAITER.run("SELECT id, payload FROM finance.task_queue ORDER BY id FOR UPDATE SKIP LOCKED;", 15), "  无锁时全部返回: ")

print("\n  --- 再演一次：持锁下 SKIP LOCKED ---")
HOLDER.send("BEGIN; SELECT id FROM finance.task_queue WHERE id <= 2 FOR UPDATE;")
HOLDER.collect(15)
show(WAITER.run("SELECT id, payload FROM finance.task_queue ORDER BY id FOR UPDATE SKIP LOCKED;", 15), "  SKIP LOCKED 结果: ")
HOLDER.send("ROLLBACK;")
HOLDER.collect(15)

hdr("实验 1 结束")
for c in (OBS, HOLDER, WAITER):
    c.close()
