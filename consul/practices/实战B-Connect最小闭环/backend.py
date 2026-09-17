"""实战篇 B 的被测后端：一个最简 HTTP 服务，返回自己的身份。

它是"不感知 Connect"的普通应用——不知道 mTLS 的存在，
所有加密与身份认证都由 sidecar 代理承担。这正是 Connect 的设计前提。
"""

import http.server
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9090
NAME = sys.argv[2] if len(sys.argv) > 2 else 'api'


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({
            'service': NAME,
            'path': self.path,
            'message': f'hello from {NAME}',
        }).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stdout.write(f'[{NAME}:{PORT}] {fmt % args}\n')


if __name__ == '__main__':
    print(f'{NAME} listening on {PORT}')
    http.server.HTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
