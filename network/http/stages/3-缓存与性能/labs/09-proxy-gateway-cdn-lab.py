#!/usr/bin/env python3
"""课 9 本地实验：正向代理、反向代理、边缘缓存与转发头。"""

import json
import subprocess
import threading
import time
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


def send_json(handler, payload, extra=None):
    body = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode()
    handler.send_response(200)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    for key, value in (extra or {}).items():
        handler.send_header(key, value)
    handler.end_headers()
    handler.wfile.write(body)


class OriginHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        headers = {
            key: self.headers.get(key)
            for key in ("Via", "Forwarded", "X-Forwarded-For", "X-Real-IP")
            if self.headers.get(key) is not None
        }
        send_json(
            self,
            {"role": "origin", "path": self.path, "headers": headers},
            {"Cache-Control": "public, max-age=5, s-maxage=30"},
        )

    def log_message(self, *_):
        pass


def start(server):
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


class ReverseProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    origin_port = None

    def do_GET(self):
        # 只有实验边缘节点带来的标记才视为受信任上游；它不是生产头部。
        trusted_upstream = self.headers.get("X-Lab-Upstream") == "edge"
        incoming_via = self.headers.get("Via") if trusted_upstream else None
        via = ", ".join(filter(None, [incoming_via, "1.1 lab-reverse"]))
        client_ip = self.client_address[0]
        incoming_xff = self.headers.get("X-Forwarded-For") if trusted_upstream else None
        xff = ", ".join(filter(None, [incoming_xff, client_ip]))
        forwarded = self.headers.get("Forwarded") if trusted_upstream else None
        forwarded = ", ".join(
            filter(None, [forwarded, f"for={client_ip};proto=http;by=127.0.0.1"])
        )

        conn = HTTPConnection("127.0.0.1", self.origin_port, timeout=3)
        conn.request(
            "GET",
            urlsplit(self.path).path or "/",
            headers={
                "Host": "origin.example",
                "Via": via,
                "Forwarded": forwarded,
                "X-Forwarded-For": xff,
                "X-Real-IP": self.headers.get("X-Real-IP", client_ip)
                if trusted_upstream
                else client_ip,
            },
        )
        response = conn.getresponse()
        body = response.read()
        conn.close()
        self.send_response(response.status)
        self.send_header("Content-Type", response.getheader("Content-Type"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Lab-Route", "reverse")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class ForwardProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    origin_port = None

    def do_GET(self):
        target = urlsplit(self.path)
        conn = HTTPConnection("127.0.0.1", self.origin_port, timeout=3)
        conn.request(
            "GET",
            target.path or "/",
            headers={"Host": target.netloc, "Via": "1.1 lab-forward"},
        )
        response = conn.getresponse()
        body = response.read()
        conn.close()
        self.send_response(response.status)
        self.send_header("Content-Type", response.getheader("Content-Type"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Lab-Route", "forward")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class EdgeCacheHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    reverse_port = None
    cache = {}

    def do_GET(self):
        key = urlsplit(self.path).path or "/"
        cached = self.cache.get(key)
        now = time.time()
        if cached and now - cached["stored_at"] < 30:
            age = int(now - cached["stored_at"])
            payload = dict(cached["payload"])
            payload["edge_cache"] = "HIT"
            send_json(self, payload, {"X-Edge-Cache": "HIT", "Age": str(age)})
            return

        conn = HTTPConnection("127.0.0.1", self.reverse_port, timeout=3)
        conn.request(
            "GET",
            self.path,
            headers={
                "Host": "www.example.com",
                "Via": "1.1 lab-edge",
                "X-Forwarded-For": self.client_address[0],
                "X-Real-IP": self.client_address[0],
                # 仅为实验标记“这是受信任的边缘上游”，不是生产头部。
                "X-Lab-Upstream": "edge",
            },
        )
        response = conn.getresponse()
        body = response.read()
        conn.close()
        payload = json.loads(body)
        self.cache[key] = {"payload": dict(payload), "stored_at": now}
        payload["edge_cache"] = "MISS"
        send_json(self, payload, {"X-Edge-Cache": "MISS", "Age": "0"})

    def log_message(self, *_):
        pass


def curl(*args):
    result = subprocess.run(
        ["curl", "-sS", "--noproxy", "", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def main():
    origin = ThreadingHTTPServer(("127.0.0.1", 0), OriginHandler)
    reverse = ThreadingHTTPServer(("127.0.0.1", 0), ReverseProxyHandler)
    forward = ThreadingHTTPServer(("127.0.0.1", 0), ForwardProxyHandler)
    edge = ThreadingHTTPServer(("127.0.0.1", 0), EdgeCacheHandler)

    ReverseProxyHandler.origin_port = origin.server_port
    ForwardProxyHandler.origin_port = origin.server_port
    EdgeCacheHandler.reverse_port = reverse.server_port
    for server in (origin, reverse, forward, edge):
        start(server)

    forward_result = curl(
        "-x",
        f"http://127.0.0.1:{forward.server_port}",
        f"http://127.0.0.1:{origin.server_port}/forward",
    )
    reverse_result = curl(f"http://127.0.0.1:{reverse.server_port}/reverse")
    edge_miss = curl(f"http://127.0.0.1:{edge.server_port}/asset.js")
    edge_hit = curl(f"http://127.0.0.1:{edge.server_port}/asset.js")

    print("forward:", json.dumps(forward_result, ensure_ascii=False, sort_keys=True))
    print("reverse:", json.dumps(reverse_result, ensure_ascii=False, sort_keys=True))
    print("edge-1:", json.dumps(edge_miss, ensure_ascii=False, sort_keys=True))
    print("edge-2:", json.dumps(edge_hit, ensure_ascii=False, sort_keys=True))

    for server in (edge, forward, reverse, origin):
        server.shutdown()


if __name__ == "__main__":
    main()
