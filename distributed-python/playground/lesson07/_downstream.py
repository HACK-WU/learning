"""公共：一个真实的本地下游 HTTP 服务（ThreadingHTTPServer）。

延迟 / 返回码 / 是否"挂但还在等"都可配置；累计被打次数用于观察
"熔断到底替下游挡掉了多少次请求"。
"""
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        srv = self.server
        with srv.lock:
            srv.hits += 1
        # 模拟"下游卡住"：先干活再返回 503
        time.sleep(srv.delay)
        body = b"down" if srv.code >= 500 else b"ok"
        try:
            self.send_response(srv.code)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # 客户端已经超时走人，这是正常现象

    def log_message(self, *args):
        pass


class Downstream:
    def __init__(self, delay: float = 0.05, code: int = 200):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.httpd.daemon_threads = True
        self.httpd.delay = delay
        self.httpd.code = code
        self.httpd.hits = 0
        self.httpd.lock = threading.Lock()
        self.port = self.httpd.server_address[1]
        self._t = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}/work"

    @property
    def hits(self) -> int:
        return self.httpd.hits

    def __enter__(self):
        self._t.start()
        return self

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()


def pct(values, p):
    """最近秩百分位，避免插值带来的"看起来更准"的假象。"""
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round(p / 100 * (len(s) - 1)))))
    return s[k]
