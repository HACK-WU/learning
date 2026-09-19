#!/usr/bin/env python3
"""反例：能返回响应，但把多个 HTTP 问题混在一起。

只绑定本机，适合阅读对照；不要把这份实现部署到真实环境。
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
import time


class BadHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        time.sleep(0.8)  # 所有请求都无条件等待，无法区分 TTFB 与业务阶段。
        self.send_response(200)  # 认证失败也返回 200，让客户端无法按语义分支。
        self.send_header("Access-Control-Allow-Origin", "*")  # 未来带凭证时越权风险高。
        self.end_headers()  # 没有 Content-Length / 明确缓存策略 / 诊断头。
        self.wfile.write(b"maybe ok\n")

    def log_message(self, _format: str, *_args: object) -> None:
        return


if __name__ == "__main__":
    print("bad-listening=http://127.0.0.1:8766")
    HTTPServer(("127.0.0.1", 8766), BadHandler).serve_forever()
