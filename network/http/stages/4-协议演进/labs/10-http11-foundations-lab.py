#!/usr/bin/env python3
"""课 10 本地实验：HTTP/1.1 持久连接、Host 虚拟主机与 chunked 分块。"""

import socket
import threading


class HTTP11LabServer:
    def __init__(self):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen()
        self.listener.settimeout(0.2)
        self.port = self.listener.getsockname()[1]
        self.stop_event = threading.Event()
        self.connection_number = 0
        self.connection_lock = threading.Lock()
        self.events = []
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        self.stop_event.set()
        self.listener.close()
        self.thread.join(timeout=2)

    def _serve(self):
        while not self.stop_event.is_set():
            try:
                conn, _ = self.listener.accept()
            except (socket.timeout, OSError):
                continue
            with self.connection_lock:
                self.connection_number += 1
                connection_id = self.connection_number
            threading.Thread(
                target=self._handle_connection,
                args=(conn, connection_id),
                daemon=True,
            ).start()

    def _handle_connection(self, conn, connection_id):
        conn.settimeout(3)
        reader = conn.makefile("rb")
        request_number = 0
        try:
            while True:
                request = self._read_request(reader)
                if request is None:
                    return
                request_number += 1
                status, body, should_close = self._route(request)
                self.events.append(
                    {
                        "connection": connection_id,
                        "request": request_number,
                        "method": request["method"],
                        "host": request["headers"].get("host", ""),
                        "transfer": request["headers"].get("transfer-encoding", ""),
                        "body": request["body"].decode("utf-8", "replace"),
                    }
                )
                reason = "OK" if status == 200 else "Bad Request"
                connection_header = "close" if should_close else "keep-alive"
                response = (
                    f"HTTP/1.1 {status} {reason}\r\n"
                    "Content-Type: text/plain; charset=utf-8\r\n"
                    f"Content-Length: {len(body)}\r\n"
                    f"Connection: {connection_header}\r\n"
                    "\r\n"
                ).encode() + body
                conn.sendall(response)
                if should_close:
                    return
        finally:
            reader.close()
            conn.close()

    @staticmethod
    def _read_request(reader):
        request_line = reader.readline()
        if not request_line:
            return None
        if not request_line.endswith(b"\r\n"):
            return {"method": "", "target": "", "version": "", "headers": {}, "body": b""}
        parts = request_line.decode("ascii", "replace").strip().split(" ")
        if len(parts) != 3:
            return {"method": "", "target": "", "version": "", "headers": {}, "body": b""}
        headers = {}
        while True:
            line = reader.readline()
            if line in (b"", b"\r\n"):
                break
            name, separator, value = line.decode("iso-8859-1").partition(":")
            if separator:
                headers.setdefault(name.lower(), []).append(value.strip())

        body = b""
        transfer = ",".join(headers.get("transfer-encoding", [])).lower()
        if transfer.endswith("chunked"):
            chunks = []
            while True:
                size_line = reader.readline().decode("ascii", "replace").strip()
                size = int(size_line.split(";", 1)[0], 16)
                if size == 0:
                    while reader.readline() not in (b"", b"\r\n"):
                        pass
                    break
                chunks.append(reader.read(size))
                reader.read(2)
            body = b"".join(chunks)
        elif headers.get("content-length"):
            body = reader.read(int(headers["content-length"][0]))

        return {
            "method": parts[0],
            "target": parts[1],
            "version": parts[2],
            "headers": {key: values[-1] for key, values in headers.items()},
            "header_values": headers,
            "body": body,
        }

    @staticmethod
    def _route(request):
        host_values = request.get("header_values", {}).get("host", [])
        if request.get("version") == "HTTP/1.1" and len(host_values) != 1:
            return 400, b"missing-or-duplicate-host", True

        host = request["headers"].get("host", "")
        if request["method"] == "GET" and request["target"] == "/who":
            site = {"alpha.test": "alpha-site", "beta.test": "beta-site"}.get(
                host, "unknown-site"
            )
            return 200, f"host={host} site={site}".encode(), request["headers"].get("connection") == "close"
        if request["method"] == "POST" and request["target"] == "/upload":
            return 200, request["body"], request["headers"].get("connection") == "close"
        return 200, b"ok", request["headers"].get("connection") == "close"


def read_response(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        data += sock.recv(4096)
    header_bytes, body = data.split(b"\r\n\r\n", 1)
    headers = {}
    lines = header_bytes.decode("iso-8859-1").split("\r\n")
    for line in lines[1:]:
        name, _, value = line.partition(":")
        headers[name.lower()] = value.strip()
    remaining = int(headers.get("content-length", "0")) - len(body)
    while remaining > 0:
        body += sock.recv(remaining)
        remaining = int(headers.get("content-length", "0")) - len(body)
    return lines[0], body


def request_over_one_connection(port):
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    first = (
        b"GET /who HTTP/1.1\r\n"
        b"Host: alpha.test\r\n"
        b"Connection: keep-alive\r\n\r\n"
    )
    second = (
        b"GET /who HTTP/1.1\r\n"
        b"Host: beta.test\r\n"
        b"Connection: close\r\n\r\n"
    )
    # 逐个发送请求，仍复用同一条 TCP 连接；这样响应读取器无需处理
    # “一次 recv 同时拿到两份响应”的额外缓冲状态，实验结果更稳定。
    sock.sendall(first)
    first_status, first_body = read_response(sock)
    sock.sendall(second)
    second_status, second_body = read_response(sock)
    sock.close()
    return first_status, first_body, second_status, second_body


def chunked_request(port):
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    request = (
        b"POST /upload HTTP/1.1\r\n"
        b"Host: upload.test\r\n"
        b"Transfer-Encoding: chunked\r\n"
        b"Connection: close\r\n\r\n"
        b"5\r\nhello\r\n"
        b"6\r\n world\r\n"
        b"0\r\n\r\n"
    )
    sock.sendall(request)
    status, body = read_response(sock)
    sock.close()
    return status, body


def missing_host_request(port):
    sock = socket.create_connection(("127.0.0.1", port), timeout=3)
    sock.sendall(b"GET /who HTTP/1.1\r\nConnection: close\r\n\r\n")
    status, body = read_response(sock)
    sock.close()
    return status, body


def main():
    server = HTTP11LabServer()
    server.start()
    try:
        first_status, first_body, second_status, second_body = request_over_one_connection(
            server.port
        )
        chunked_status, chunked_body = chunked_request(server.port)
        missing_host_status, missing_host_body = missing_host_request(server.port)
        print(
            "persistent:",
            f"statuses={first_status.split()[1]},{second_status.split()[1]} "
            f"same_connection={server.events[0]['connection'] == server.events[1]['connection']} "
            f"hosts={server.events[0]['host']}→{server.events[1]['host']} "
            f"sites={first_body.decode()}→{second_body.decode()}",
        )
        print(
            "chunked:",
            f"status={chunked_status.split()[1]} "
            f"transfer={server.events[2]['transfer']} "
            f"body={chunked_body.decode()}",
        )
        print(
            "missing-host:",
            f"status={missing_host_status.split()[1]} "
            f"body={missing_host_body.decode()}",
        )
    finally:
        server.close()


if __name__ == "__main__":
    main()
