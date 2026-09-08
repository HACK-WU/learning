#!/usr/bin/env python3
"""
课 7 可控 remote write receiver。

目的：精确注入故障（5xx / 延迟 / 丢弃），以便观察 Prometheus
remote write 的队列行为、重试语义与数据丢失点。

协议：HTTP POST，body 为 snappy 压缩的 protobuf WriteRequest。
我们不需要完整解码时序内容，只要：
  1. 解压成功 -> 说明这是一次有效写入
  2. 统计解压后的字节数，粗略代表样本量
因此使用 snappy 的 raw/ framed 两种尝试解压，不做 protobuf 解析。

控制端点（HTTP GET，端口 8080）：
  /mode/ok      正常接受 (204)
  /mode/500     返回 500
  /mode/503     返回 503
  /mode/429     返回 429
  /mode/slow    延迟 30s 后返回 204
  /mode/drop    读完整请求体但返回 204（吞掉数据，模拟"假成功"）
  /stats        查看当前统计
  /reset        重置统计
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = "ok"
STATS = {
    "requests": 0,
    "accepted": 0,
    "rejected": 0,
    "bytes_compressed": 0,
    "bytes_decompressed": 0,
    "first_seen": None,
    "last_seen": None,
}
LOCK = threading.Lock()


def decompress_try(body):
    """尝试解压 snappy。返回 (解压后字节数, 方式)。失败返回 (0, 'none')。"""
    try:
        import snappy
    except ImportError:
        return 0, "no-lib"
    for name, fn in (("framed", "uncompress"), ("raw", "decompress")):
        try:
            out = getattr(snappy, fn)(body)
            return len(out), name
        except Exception:
            continue
    return 0, "failed"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # 安静模式：日志走 /stats，避免刷屏
        pass

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def _record(self, ok, nbytes, dec, how):
        with LOCK:
            STATS["requests"] += 1
            if ok:
                STATS["accepted"] += 1
            else:
                STATS["rejected"] += 1
            STATS["bytes_compressed"] += nbytes
            STATS["bytes_decompressed"] += dec
            now = time.time()
            if STATS["first_seen"] is None:
                STATS["first_seen"] = now
            STATS["last_seen"] = now

    def do_GET(self):
        global MODE
        path = self.path.split("?")[0]
        if path.startswith("/mode/"):
            MODE = path.split("/mode/")[1]
            body = json.dumps({"mode": MODE}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/stats":
            with LOCK:
                s = dict(STATS)
            s["mode"] = MODE
            body = json.dumps(s, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/reset":
            with LOCK:
                for k in STATS:
                    STATS[k] = 0 if "bytes" in k or "requests" in k or "accept" in k or "reject" in k else None
            body = b'{"reset":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = b'{"usage":"/mode/{ok|500|503|429|slow|drop} /stats /reset","write_endpoint":"/api/v1/write"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        body = self._read_body()
        dec, how = decompress_try(body)
        mode = MODE

        if mode == "slow":
            time.sleep(30)

        if mode in ("500", "503", "429"):
            self._record(False, len(body), dec, how)
            code = int(mode)
            # 429/503 带 Retry-After，观察 Prometheus 是否尊重它
            payload = b"injected failure"
            self.send_response(code)
            if code in (429, 503):
                self.send_header("Retry-After", "2")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        # ok / drop / slow 都返回 204（drop 是"假成功"：数据被吞）
        self._record(True, len(body), dec, how)
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"receiver listening on :{port} (write=/api/v1/write, ctrl=:8080)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
