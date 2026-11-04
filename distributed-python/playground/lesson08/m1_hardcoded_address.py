"""M1：把地址写死在代码里，扩缩容时会怎样？

三个实例，客户端代码里只有 instance-1 的地址（真实项目里就是一个常量）。
跑三个阶段：
  R1 初始状态：3 个实例都健康
  R2 扩容：再起 2 个实例（共 5 个）
  R3 缩容/重启：instance-1 换端口重新拉起（老地址失效）

纯标准库，直接 python3 跑。
"""
import http.client
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HITS = {}
LOCK = threading.Lock()


def bump(sid):
    with LOCK:
        HITS[sid] = HITS.get(sid, 0) + 1


def snapshot():
    with LOCK:
        return dict(HITS)


def reset():
    with LOCK:
        HITS.clear()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"          # 才支持 keep-alive，贴近真实服务
    sid = "?"

    def do_GET(self):
        bump(self.sid)
        body = self.sid.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def start(sid, port=0):
    h = type(f"H_{sid}", (Handler,), {"sid": sid})
    srv = ThreadingHTTPServer(("127.0.0.1", port), h)
    real = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, real


def call(port, timeout=0.5):
    """客户端唯一的调用函数——地址是参数，但调用方传的是写死的那个常量。"""
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        c.request("GET", "/")
        return c.getresponse().read().decode()
    finally:
        c.close()


def phase(label, hardcoded_port, n=30):
    reset()
    ok, fail = 0, 0
    for _ in range(n):
        try:
            call(hardcoded_port)
            ok += 1
        except Exception:
            fail += 1
    hits = snapshot()
    print(f"\n【{label}】客户端共发 {n} 次，写死地址 = 127.0.0.1:{hardcoded_port}")
    print(f"  成功 {ok} / 失败 {fail}")
    for sid in sorted(hits):
        print(f"    {sid:14s} 被打 {hits[sid]:3d} 次")
    return ok, fail, hits


print("=" * 70)
print("M1：地址写死在代码里，扩缩容时会怎样")
print("=" * 70)

# ---- R1：3 个实例都在，客户端只知道 instance-1 ----
s1, p1 = start("instance-1")
s2, p2 = start("instance-2")
s3, p3 = start("instance-3")
print(f"\n集群：instance-1:{p1}  instance-2:{p2}  instance-3:{p3}")
print(f"客户端代码：SERVER = \"127.0.0.1:{p1}\"   ← 常量，写死")

ok1, fail1, h1 = phase("R1 初始：3 个实例都健康", p1)
used = len([v for v in h1.values() if v])
print(f"  → 3 个实例里只有 {used} 个收到流量；另外 {3-used} 个白占资源")

# ---- R2：扩容到 5 个 ----
s4, p4 = start("instance-4")
s5, p5 = start("instance-5")
print(f"\n运维操作：扩容，新起 instance-4:{p4}  instance-5:{p5}（共 5 个）")
ok2, fail2, h2 = phase("R2 扩容后（客户端代码一行没改）", p1)
used2 = len([v for v in h2.values() if v])
print(f"  → 5 个实例里只有 {used2} 个收到流量；新扩的 2 个一次都没被调用")
print(f"  → 有效容量仍是 1/5 = 20%，扩了等于没扩")

# ---- R3：instance-1 缩容/重启，换了端口 ----
s1.shutdown()
s1.server_close()
time.sleep(0.1)
new1, newp1 = start("instance-1(new)")
print(f"\n运维操作：instance-1 重建，端口从 {p1} 变成 {newp1}（滚动升级的正常结果）")
ok3, fail3, h3 = phase("R3 老地址失效后", p1)
print(f"  → 写死的 {p1} 已经没人监听，客户端 100% 失败")
print(f"  → 新实例 {newp1} 活着，但客户端永远找不到它")

print("""
判读（三个问题各对应一段）：
  R1  扩了也不会用：写死一个地址 = 只用一个实例，其余全是备胎
  R2  扩容完全无效：新实例的地址没人知道，容量翻倍但吞吐不变
  R3  重启就全挂：实例换 IP/端口是常态（滚动升级、重新调度），写死的地址直接失效
  → 这三个问题的共同点：地址是"运行期才确定、还会变"的信息，不该写进代码
""")

for s in (s2, s3, s4, s5, new1):
    s.shutdown()
    s.server_close()
