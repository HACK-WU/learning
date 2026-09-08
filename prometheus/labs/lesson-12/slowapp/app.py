import time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            time.sleep(3)                      # 故意慢
            body = b"# HELP slow_metric demo\n# TYPE slow_metric gauge\nslow_metric 1\n"
            self.send_response(200)
            self.send_header("Content-Type","text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self,*a): pass
HTTPServer(("0.0.0.0",8000),H).serve_forever()
