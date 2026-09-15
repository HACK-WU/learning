# -*- coding: utf-8 -*-
"""课 13 实验 4（修正重测）：idle 锁持有 / idle timeout 正确姿势 / 长事务钉死元组 / 40001 SQLSTATE"""
import subprocess, time, threading, queue
ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}


class P:
    def __init__(s, name):
        s.name = name; s.dead = False
        s.p = subprocess.Popen(["docker","exec","-i","pg17","psql","-U","postgres",
            "-d","order_service","-X","-q","-v","ON_ERROR_STOP=0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, env=ENV)
        s.q = queue.Queue()
        threading.Thread(target=s._reader, daemon=True).start()
    def _reader(s):
        for line in s.p.stdout: s.q.put(line.rstrip("\n"))
        s.q.put(None)
    def read_until_end(s, timeout):
        out, dl = [], time.time()+timeout
        while True:
            rem = dl-time.time()
            if rem <= 0: return None
            try: l = s.q.get(timeout=rem)
            except queue.Empty: return None
            if l is None: s.dead=True; return "EOF"
            if l.strip()=="@@END@@": return out
            out.append(l)
    def run(s, sql, t=60):
        if s.dead: return "[会话已断开]"
        s.p.stdin.write(sql+"\n\\echo '@@END@@'\n"); s.p.stdin.flush()
        r = s.read_until_end(t)
        if r is None: return "[超时]"
        if r == "EOF": return "[连接已被服务器终止]"
        return "\n".join(x for x in r if x.strip())
    def send(s, sql):
        s.p.stdin.write(sql+"\n\\echo '@@END@@'\n"); s.p.stdin.flush()
    def reopen(s): s.__init__(s.name)


def hdr(t): print("\n"+"="*78+"\n"+t+"\n"+"="*78)


A,B,O = P("A"),P("B"),P("O")

hdr("实验 M-3（修正）· idle in transaction 会一直持有它拿过的锁")
print("A 在事务里查一次表（拿 AccessShareLock），然后什么都不做：")
print(A.run("BEGIN; SELECT * FROM finance.accounts WHERE id=1;"))
time.sleep(1.5)
print("\nOBS 看它此刻的状态与持有的锁：")
print(O.run("""SELECT a.pid, a.state, round(extract(epoch from (now()-a.xact_start))::numeric,1) AS xact_s,
       l.locktype, l.mode, l.granted, coalesce(c.relname,'') AS rel
FROM pg_stat_activity a LEFT JOIN pg_locks l ON l.pid=a.pid
LEFT JOIN pg_class c ON c.oid=l.relation
WHERE a.datname='order_service' AND a.pid<>pg_backend_pid() AND a.state LIKE 'idle in transaction%'
ORDER BY a.pid, l.locktype;"""))
print(A.run("ROLLBACK;"))
print("\n→ 结论：事务一开，锁就一直攥着，直到 COMMIT/ROLLBACK —— 哪怕应用层早就'查询完毕'了")

hdr("实验 N（修正）· idle_in_transaction_session_timeout：客户端静默才触发")
print("N-1 默认值：", O.run("SELECT current_setting('idle_in_transaction_session_timeout') AS v;"))
print("\nN-2 设 3s，A 开事务后【客户端静默 6 秒】（不执行 pg_sleep，服务端真正 idle）：")
print(A.run("SET idle_in_transaction_session_timeout='3s'; BEGIN; SELECT 1 AS tx_started;"))
print("   ...客户端静默 6 秒...")
time.sleep(6)
print(A.run("SELECT '6 秒后还能执行吗' AS note;", 30))
if A.dead:
    print("   → 连接已被服务器终止（超时生效）")
    print("\nN-3 服务器日志证据：")
    lg = subprocess.run(["docker","logs","--tail","80","pg17"],capture_output=True,text=True,env=ENV,timeout=25)
    for l in (lg.stdout+lg.stderr).split("\n"):
        if "idle-in-transaction" in l or "idle_in_transaction" in l or "terminating connection" in l:
            print("   "+l)
    A.reopen()
else:
    print("   → 仍活着（未生效，需排查）")
print("\nN-4 对照：不开事务时静默 6 秒不受影响（幂等验证）：")
print(A.run("SET idle_in_transaction_session_timeout='3s';"))
print("   ...静默 6 秒...")
time.sleep(6)
print(A.run("SELECT '没开事务，静默 6s 也活着' AS note;", 30))
print(A.run("SET idle_in_transaction_session_timeout=0;"))

hdr("实验 P（修正）· 长事务钉死元组：用 REPEATABLE READ 固定快照")
print("P-0 建表（关 autovacuum，1 万行）：")
print(O.run("""DROP TABLE IF EXISTS finance.bloat_lt;
CREATE TABLE finance.bloat_lt (id int PRIMARY KEY, v text) WITH (autovacuum_enabled=false);
INSERT INTO finance.bloat_lt SELECT g,'v'||g FROM generate_series(1,10000) g;
VACUUM finance.bloat_lt;""", 90))
print("\nP-1 A 开 REPEATABLE READ 事务并查表（固定一个快照，然后停住）：")
print(A.run("BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) AS cnt FROM finance.bloat_lt;", 40))
print("\nP-2 OBS 看 A 此刻钉住的 backend_xmin：")
print(O.run("""SELECT pid, state, backend_xmin,
       round(extract(epoch from (now()-xact_start))::numeric,1) AS xact_s
FROM pg_stat_activity WHERE datname='order_service' AND pid<>pg_backend_pid() AND backend_xmin IS NOT NULL;"""))
print("\nP-3 B 把 1 万行全改一遍（产生 1 万死元组）：")
print(B.run("UPDATE finance.bloat_lt SET v=v||'-x'; SELECT pg_stat_force_next_flush();", 60))
time.sleep(1)
print("   死元组：", O.run("SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='bloat_lt';"))
print("\nP-4 现在 VACUUM —— 关键看 'dead but not yet removable' 字段：")
print(O.run("VACUUM (VERBOSE) finance.bloat_lt;", 90))
print("   死元组（VACUUM 后）：", O.run("SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='bloat_lt';"))
print("\nP-5 A 提交，再 VACUUM —— 这次应清干净：")
print(A.run("COMMIT;"))
print(O.run("VACUUM (VERBOSE) finance.bloat_lt; SELECT pg_stat_force_next_flush();", 90))
time.sleep(1)
print("   死元组（提交后 VACUUM）：", O.run("SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='bloat_lt';"))

hdr("实验 R（补测）· SERIALIZABLE 40001 的 SQLSTATE")
A.run("\\set VERBOSITY verbose")
print("R-1 A/B 都进 SERIALIZABLE 并读同一行：")
print(A.run("BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT balance FROM finance.accounts WHERE id=2;", 30))
print(B.run("BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT balance FROM finance.accounts WHERE id=2;", 30))
print("\nR-2 A 改并提交：")
print(A.run("UPDATE finance.accounts SET balance=balance-10 WHERE id=2; COMMIT;", 30))
print("\nR-3 B 也改同一行 → 完整报错（含 SQLSTATE）：")
print(B.run("UPDATE finance.accounts SET balance=balance-20 WHERE id=2;", 30))
print("\nR-4 B ROLLBACK 后重试（第二次成功）：")
print(B.run("ROLLBACK;"))
print(B.run("BEGIN ISOLATION LEVEL SERIALIZABLE; UPDATE finance.accounts SET balance=balance-20 WHERE id=2; COMMIT; SELECT balance FROM finance.accounts WHERE id=2;", 30))
A.run("\\set VERBOSITY default")

hdr("清理")
print(O.run("DROP TABLE IF EXISTS finance.bloat_lt;", 40))
print("\n实验 4 结束")
