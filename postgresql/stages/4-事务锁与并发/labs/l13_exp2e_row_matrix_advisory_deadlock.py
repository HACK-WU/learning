# -*- coding: utf-8 -*-
"""课 13 补测 v3：行锁矩阵 + 死锁 SQLSTATE
IO 模型：后台读取线程 + 队列超时（彻底避免 readline 阻塞）"""
import subprocess, time, threading, queue
ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}


class P:
    def __init__(s, name):
        s.name = name
        s.p = subprocess.Popen(
            ["docker", "exec", "-i", "pg17", "psql", "-U", "postgres",
             "-d", "order_service", "-X", "-q", "-v", "ON_ERROR_STOP=0"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1, env=ENV)
        s.q = queue.Queue()
        s.t = threading.Thread(target=s._reader, daemon=True)
        s.t.start()

    def _reader(s):
        for line in s.p.stdout:
            s.q.put(line.rstrip("\n"))
        s.q.put(None)

    def read_until_end(s, timeout):
        """读到哨兵返回行列表；超时返回 None"""
        out, dl = [], time.time() + timeout
        while True:
            remain = dl - time.time()
            if remain <= 0:
                return None
            try:
                l = s.q.get(timeout=remain)
            except queue.Empty:
                return None
            if l is None:
                return None
            if l.strip() == "@@END@@":
                return out
            out.append(l)

    def run(s, sql, t=40):
        s.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
        s.p.stdin.flush()
        r = s.read_until_end(t)
        return "\n".join(x for x in (r or []) if x.strip())

    def send(s, sql):
        s.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
        s.p.stdin.flush()

    def try_get(s, sql, wait=1.8):
        """发一条可能阻塞的语句：1.8s 内拿到哨兵=OK，否则=BLOCKED"""
        s.p.stdin.write(sql + "\n\\echo '@@END@@'\n")
        s.p.stdin.flush()
        return "OK" if s.read_until_end(wait) is not None else "BLOCKED"


A, B, O = P("A"), P("B"), P("O")
print(A.run("UPDATE finance.accounts SET balance=1000 WHERE id IN (1,2,3);"))
MODES = ["KEY SHARE", "SHARE", "NO KEY UPDATE", "UPDATE"]

print("\n" + "=" * 78)
print("实验 I（重测）· 行级锁冲突矩阵 · 阻塞观察法")
print("=" * 78)
print("  行 = A 已持有（Current）；列 = B 请求（Requested）；X=冲突  ✓=兼容\n")
print("  %-18s %-13s %-13s %-18s %-13s" % ("A＼B", "KEY SHARE", "SHARE", "NO KEY UPDATE", "UPDATE"))
print("  " + "-" * 76)
for m1 in MODES:
    row = []
    for m2 in MODES:
        A.run("BEGIN; SELECT id FROM finance.accounts WHERE id=1 FOR %s;" % m1, 30)
        st = B.try_get("SELECT id FROM finance.accounts WHERE id=1 FOR %s;" % m2)
        row.append("X" if st == "BLOCKED" else "✓")
        A.run("ROLLBACK;", 20)
        if st == "BLOCKED":
            B.read_until_end(15)          # A 已释放，B 必然完成
    print("  %-18s %-13s %-13s %-18s %-13s" % ("FOR " + m1, row[0], row[1], row[2], row[3]))

print("\n\n" + "=" * 78)
print("实验 L（重测）· 死锁的 SQLSTATE")
print("=" * 78)
A.run("\\set VERBOSITY verbose")
print("A:", A.run("BEGIN; UPDATE finance.accounts SET balance=balance+1 WHERE id=1;", 30))
print("B:", B.run("BEGIN; UPDATE finance.accounts SET balance=balance+1 WHERE id=2;", 30))
B.send("UPDATE finance.accounts SET balance=balance-1 WHERE id=1;")
time.sleep(1.3)
print("\nOBS 观察等待中的会话：")
print(O.run("""SELECT a.pid,a.wait_event_type,a.wait_event,pg_blocking_pids(a.pid) AS blocked_by
FROM pg_stat_activity a WHERE a.datname='order_service' AND a.pid<>pg_backend_pid()
AND a.wait_event_type='Lock';"""))
print("\nA 触发死锁 → A 的完整报错：")
print(A.run("UPDATE finance.accounts SET balance=balance-1 WHERE id=2;", 25))
print("\nB 随后成功完成：")
print(B.read_until_end(20))
B.run("SELECT 'B 的 UPDATE 完成' AS note;", 25)
A.run("ROLLBACK;"); B.run("ROLLBACK;")
A.run("\\set VERBOSITY default")
print("\n补测 v3 结束")
