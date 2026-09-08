import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BODY = (
    "# HELP echo_scrape_info 每次抓取恒为 1，用于观察抓取行为\n"
    "# TYPE echo_scrape_info gauge\n"
    'echo_scrape_info{app="echo"} 1\n'
).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        print("--- incoming scrape ---", flush=True)
        print("path: %s" % self.path, flush=True)
        for name, value in sorted(self.headers.items()):
            low = name.lower()
            if low in ("accept", "accept-encoding", "user-agent", "x-prometheus-scrape-timeout-seconds"):
                print("%s: %s" % (name, value), flush=True)
        print("--- end ---", flush=True)

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("echo-header app listening on :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
