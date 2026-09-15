# -*- coding: utf-8 -*-
"""补测：40001 / 40P01 / 55P03 三个 SQLSTATE 一次拿全"""
import subprocess, time, threading, queue
ENV={"PATH":"/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
class P:
    def __init__(s,n):
        s.p=subprocess.Popen(["docker","exec","-i","pg17","psql","-U","postgres","-d","order_service",
            "-X","-q","-v","ON_ERROR_STOP=0"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,text=True,bufsize=1,env=ENV)
        s.q=queue.Queue(); s.dead=False
        threading.Thread(target=s._r,daemon=True).start()
    def _r(s):
        for l in s.p.stdout: s.q.put(l.rstrip("\n"))
        s.q.put(None)
    def read(s,t):
        out,dl=[],time.time()+t
        while True:
            rem=dl-time.time()
            if rem<=0: return None
            try: l=s.q.get(timeout=rem)
            except queue.Empty: return None
            if l is None: return "EOF"
            if l.strip()=="@@"+"END@@": return out
            out.append(l)
    def run(s,sql,t=40):
        s.p.stdin.write(sql+"\n\\echo '@@END@@'\n"); s.p.stdin.flush()
        r=s.read(t)
        if r is None: return "[超时]"
        if r=="EOF": return "[连接终止]"
        return "\n".join(x for x in r if x.strip())
    def send(s,sql):
        s.p.stdin.write(sql+"\n\\echo '@@END@@'\n"); s.p.stdin.flush()
A,B=P("A"),P("B")
A.run("\\set VERBOSITY verbose"); B.run("\\set VERBOSITY verbose")

print("="*70); print("① 40001 serialization_failure —— SERIALIZABLE 并发更新"); print("="*70)
print(A.run("BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT balance FROM finance.accounts WHERE id=3;"))
print(B.run("BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT balance FROM finance.accounts WHERE id=3;"))
print(A.run("UPDATE finance.accounts SET balance=balance-1 WHERE id=3; COMMIT;"))
print("\nB 的报错："); print(B.run("UPDATE finance.accounts SET balance=balance-1 WHERE id=3;"))
print(B.run("ROLLBACK;"))

print("\n"+"="*70); print("② 40P01 deadlock_detected"); print("="*70)
print(A.run("BEGIN; UPDATE finance.accounts SET balance=balance+1 WHERE id=1;"))
print(B.run("BEGIN; UPDATE finance.accounts SET balance=balance+1 WHERE id=2;"))
B.send("UPDATE finance.accounts SET balance=balance-1 WHERE id=1;")
time.sleep(1.3)
print("A 的报错："); print(A.run("UPDATE finance.accounts SET balance=balance-1 WHERE id=2;",25))
print(B.read(20)); print(B.run("ROLLBACK;")); print(A.run("ROLLBACK;"))

print("\n"+"="*70); print("③ 55P03 lock_not_available —— NOWAIT"); print("="*70)
print(A.run("BEGIN; SELECT * FROM finance.accounts WHERE id=1 FOR UPDATE;"))
print("B 的报错："); print(B.run("SELECT * FROM finance.accounts WHERE id=1 FOR UPDATE NOWAIT;"))
print(A.run("ROLLBACK;"))
print("\n补测结束")
