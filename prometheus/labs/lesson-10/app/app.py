import os, random, time, threading
from prometheus_client import Counter, Gauge, Histogram, Summary, generate_latest, CONTENT_TYPE_LATEST
from http.server import BaseHTTPRequestHandler, HTTPServer

# ① 基线：低基数（正确示范）
GOOD = Gauge("card_good_total", "low cardinality baseline", ["route", "status"])
# ② 标签值失控：把 user_id / url 塞进标签（教科书级错误）
BAD_USER  = Gauge("card_bad_by_user", "HIGH CARDINALITY: user_id in label", ["user_id"])
BAD_URL   = Gauge("card_bad_by_url",  "HIGH CARDINALITY: url path in label", ["url"])
BAD_REQ   = Gauge("card_bad_by_reqid","HIGH CARDINALITY: request_id in label", ["request_id"])
# ③ 直方图桶 / Summary 分位数 的放大效应
HIST = Histogram("card_hist_seconds", "histogram buckets", ["route"],
                 buckets=[0.005,0.01,0.025,0.05,0.1,0.25,0.5,1,2.5,5,10])
SUMM = Summary("card_summ_seconds", "summary quantiles", ["route"])
# ④ churn：模拟实例反复创建销毁（带 pod 名标签）
CHURN = Gauge("card_churn_total", "instance churn simulation", ["pod"])

N_USERS   = int(os.environ.get("N_USERS", "0"))
VAL_LEN   = int(os.environ.get("VAL_LEN", "8"))
N_URLS    = int(os.environ.get("N_URLS", "0"))
N_REQIDS  = int(os.environ.get("N_REQIDS", "0"))
N_PODS    = int(os.environ.get("N_PODS", "0"))
CHURN_SEC = int(os.environ.get("CHURN_SEC", "0"))
ROUTES = ["/", "/api/list", "/api/detail"]

def mkval(i):
    return f"u{i:06d}".ljust(VAL_LEN, "x")[:VAL_LEN]

def init():
    if N_USERS:
        for i in range(N_USERS):
            BAD_USER.labels(user_id=mkval(i)).set(0)
    if N_URLS:
        for i in range(N_URLS):
            BAD_URL.labels(url=f"/resource/{i}/detail").set(0)
    if N_REQIDS:
        for i in range(N_REQIDS):
            BAD_REQ.labels(request_id=f"{i:036x}").set(0)
    if N_PODS:
        for i in range(N_PODS):
            CHURN.labels(pod=f"pod-{i:05d}").set(0)

def gen(churn_gen=0):
    for r in ROUTES:
        GOOD.labels(route=r, status="200").set(random.randint(1,100))
        with HIST.labels(route=r).time():
            time.sleep(0.001)
        SUMM.labels(route=r).observe(random.uniform(0.001, 0.5))
    if N_USERS:
        for i in range(N_USERS):
            BAD_USER.labels(user_id=mkval(i)).set(float(random.randint(1,1000)))
    if N_URLS:
        for i in range(N_URLS):
            BAD_URL.labels(url=f"/resource/{i}/detail").set(float(random.randint(1,1000)))
    if N_REQIDS:
        for i in range(N_REQIDS):
            BAD_REQ.labels(request_id=f"{i:036x}").set(float(random.randint(1,1000)))
    if N_PODS:
        for i in range(N_PODS):
            CHURN.labels(pod=f"pod-{i:05d}").set(float(churn_gen*1000+i))

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass

if __name__ == "__main__":
    init()

    def loop():
        g = 0
        while True:
            gen(g)
            g += 1
            time.sleep(1)

    threading.Thread(target=loop, daemon=True).start()
    HTTPServer(("0.0.0.0", 8000), H).serve_forever()
