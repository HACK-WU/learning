#!/usr/bin/env python3
"""
最小可用的 Admission Webhook Server（教学用，无外部依赖，仅标准库）

行为：
  1. 校验所有 Pod 创建请求，要求携带 label: app.kubernetes.io/name
     - 缺失 -> allowed=false，并给出明确 reason
  2. 支持三条"实验开关"（通过 URL query 或路径切换），用于演示生产事故：
     - /healthz          健康检查
     - /validate         正常校验
     - /boom             永远返回 HTTP 500（演示 failurePolicy=Fail 时的后果）
  3. 额外做一次 Mutating：给缺失 team 标签的 Pod 自动补 team=unknown
     用来演示 mutating -> validating 的执行顺序

所有决策都打到 stdout，可直接 kubectl logs 查看。
"""
import base64
import json
import ssl
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

MODE = sys.argv[1] if len(sys.argv) > 1 else "validate"   # validate | boom
PORT = 8443
REQUIRED_LABEL = "app.kubernetes.io/name"


def decision(uid, allowed, message=None, patch=None):
    """构造 AdmissionReview 响应。patch 为 None 表示这是纯校验 webhook。"""
    resp = {"uid": uid, "allowed": allowed}
    if message:
        resp["status"] = {"message": message}
    if patch is not None:
        # JSONPatch，必须 base64
        resp["patchType"] = "JSONPatch"
        resp["patch"] = base64.b64encode(json.dumps(patch).encode()).decode()
    return resp


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # 只打关键行，避免刷屏
        sys.stdout.write("[webhook] %s\n" % (fmt % args))
        sys.stdout.flush()

    def _send(self, code, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/healthz"):
            self._send(200, b'{"status":"ok"}')
        else:
            self._send(404, b'{"error":"not found"}')

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)

        # 实验开关：故意坏掉，用于演示 failurePolicy=Fail 的后果
        if path == "/boom" or MODE == "boom":
            sys.stdout.write("[webhook] MODE=boom -> 返回 500，模拟 webhook 故障\n")
            sys.stdout.flush()
            self._send(500, b'{"error":"simulated webhook failure"}')
            return

        try:
            review = json.loads(raw)
        except Exception as e:
            self._send(400, json.dumps({"error": "bad request: %s" % e}).encode())
            return

        uid = review.get("request", {}).get("uid", "")
        obj = review.get("request", {}).get("object", {}) or {}
        name = obj.get("metadata", {}).get("name", "<unnamed>")
        ns = review.get("request", {}).get("namespace", "<none>")
        labels = (obj.get("metadata", {}).get("labels") or {})

        sys.stdout.write(
            "[webhook] 收到 Pod 校验: ns=%s name=%s labels=%s\n" % (ns, name, labels)
        )
        sys.stdout.flush()

        # ---------- Mutating：补默认 team 标签 ----------
        if path == "/mutate":
            ops = []
            if "team" not in labels:
                if not labels:
                    # labels 字段整个不存在：先建对象，再加 key（两条 op）
                    ops.append({"op": "add", "path": "/metadata/labels", "value": {}})
                # 关键：labels 已存在时必须 add 到 /metadata/labels/team，
                # 若 add 整个 /metadata/labels 会被 API Server 忽略（对象已存在）
                ops.append({"op": "add", "path": "/metadata/labels/team", "value": "unknown"})
            if ops:
                sys.stdout.write("[webhook] MUTATING: 自动补 team=unknown\n")
                sys.stdout.flush()
            out = decision(uid, True, patch=ops if ops else [])
            body = json.dumps({
                "apiVersion": "admission.k8s.io/v1",
                "kind": "AdmissionReview",
                "response": out,
            }).encode()
            self._send(200, body)
            return

        # ---------- Validating：必须有 app.kubernetes.io/name ----------
        if REQUIRED_LABEL in labels:
            sys.stdout.write("[webhook] VALIDATING: 通过（有 %s）\n" % REQUIRED_LABEL)
            sys.stdout.flush()
            out = decision(uid, True)
        else:
            msg = ("拒绝：Pod 必须带 label %s（推荐 k8s 标准标签）。"
                   "例：kubectl label pod <name> %s=myapp" % (REQUIRED_LABEL, REQUIRED_LABEL))
            sys.stdout.write("[webhook] VALIDATING: 拒绝（缺 %s）\n" % REQUIRED_LABEL)
            sys.stdout.flush()
            out = decision(uid, False, msg)

        body = json.dumps({
            "apiVersion": "admission.k8s.io/v1",
            "kind": "AdmissionReview",
            "response": out,
        }).encode()
        self._send(200, body)


if __name__ == "__main__":
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("/etc/webhook/certs/tls.crt", "/etc/webhook/certs/tls.key")
    httpd = HTTPServer(("0.0.0.0", PORT), Handler)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    sys.stdout.write("[webhook] 启动 mode=%s port=%d\n" % (MODE, PORT))
    sys.stdout.flush()
    httpd.serve_forever()
