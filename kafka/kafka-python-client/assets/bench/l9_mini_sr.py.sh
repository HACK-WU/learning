#!/bin/bash
# 课 9 实验⑤：最小 Schema Registry 原型（兜底方案）
#
# 用途：当 Confluent SR 镜像（1.5GB）在本机网络下拉不动时的替代验证
# 目的：验证"注册时强制兼容性校验"这个核心语义，而非替代真 SR
#
# 实现：HTTP 服务 + fastavro，4 个端点
#   POST /subjects/{s}/versions          注册 schema（带兼容性校验）
#   GET  /subjects/{s}/versions/latest   取最新 schema
#   GET  /schemas/ids/{id}               按 id 取 schema
#   PUT  /config/{s}                     设兼容级别
#
# ⚠ 诚实标注：这是教学原型，不是生产实现。真 SR 还有：
#   多节点选主、_schemas topic 持久化、OAuth/SSL、多格式支持、数据脱敏规则等
set -u
cat > /tmp/mini_sr.py <<'PYEOF'
import json, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import fastavro
from fastavro.schema import SchemaParseException

# ---------- 兼容性判定（简化版，只实现 backward）----------
def check_backward(old, new):
    """backward: 用【新】schema 能读【旧】数据吗？
    返回 (是否兼容, 原因列表)"""
    reasons = []
    old_f = {f["name"]: f for f in old["fields"]}
    new_f = {f["name"]: f for f in new["fields"]}

    for name, f in new_f.items():
        if name not in old_f:
            if "default" not in f:
                reasons.append(f"新增字段 '{name}' 无默认值：旧数据没有它，读不出来")
        else:
            ot, nt = old_f[name].get("type"), f.get("type")
            if ot != nt:
                promote = (ot == "int" and nt == "long")
                if not promote:
                    reasons.append(f"字段 '{name}' 类型 {ot} -> {nt} 不允许"
                                   + ("（仅 int->long 提升合法）" if not promote else ""))
    for name in old_f:
        if name not in new_f:
            pass  # 删字段对 backward 是允许的（reader 忽略多余字段）
    return (len(reasons) == 0), reasons

# ---------- 存储 ----------
store = {"subjects": {}, "ids": {}, "config": {}}
next_id = [1]
lock = threading.Lock()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n)) if n else {}

    def do_POST(self):
        # /subjects/{subject}/versions
        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "subjects" and parts[2] == "versions":
            subj = parts[1]
            body = self._body()
            schema_str = body.get("schema")
            try:
                new = json.loads(schema_str) if isinstance(schema_str, str) else schema_str
                fastavro.parse_schema(new)      # 先验证 schema 本身合法
            except Exception as e:
                return self._json(400, {"error_code": 42201,
                                        "message": f"schema 非法: {e}"})
            with lock:
                versions = store["subjects"].setdefault(subj, [])
                level = store["config"].get(subj, "backward")
                if versions:
                    old = versions[-1]["schema_obj"]
                    if level == "backward":
                        ok, reasons = check_backward(old, new)
                        if not ok:
                            return self._json(409, {
                                "error_code": 409,
                                "message": f"注册被拒：不兼容 {level} 演进\n  - "
                                           + "\n  - ".join(reasons)})
                sid = next_id[0]; next_id[0] += 1
                versions.append({"id": sid, "schema_str": schema_str,
                                 "schema_obj": new})
                store["ids"][sid] = json.dumps(new)
            return self._json(200, {"id": sid})
        return self._json(404, {"message": "not found"})

    def do_GET(self):
        parts = self.path.strip("/").split("/")
        if len(parts) == 4 and parts[0]=="subjects" and parts[3]=="latest":
            subj = parts[1]
            vs = store["subjects"].get(subj)
            if not vs: return self._json(404, {"error_code":40401,"message":"subject not found"})
            v = vs[-1]
            return self._json(200, {"subject":subj,"version":len(vs),"id":v["id"],"schema":v["schema_str"]})
        if len(parts)==3 and parts[0]=="schemas" and parts[1]=="ids":
            sid = int(parts[2])
            if sid in store["ids"]:
                return self._json(200, {"schema": store["ids"][sid]})
            return self._json(404, {"error_code":40403,"message":"schema not found"})
        if self.path == "/subjects":
            return self._json(200, list(store["subjects"].keys()))
        return self._json(404, {"message":"not found"})

    def do_PUT(self):
        parts = self.path.strip("/").split("/")
        if len(parts)==2 and parts[0]=="config":
            body = self._body()
            store["config"][parts[1]] = body.get("compatibilityLevel","backward")
            return self._json(200, body)
        return self._json(404, {"message":"not found"})

if __name__ == "__main__":
    srv = HTTPServer(("0.0.0.0", 8081), H)
    print("mini-sr listening on 8081", flush=True)
    srv.serve_forever()
PYEOF
echo "原型已生成：/tmp/mini_sr.py"
echo "启动方式：docker run -d --network bench_kafka-net --name l9-minisr -v /tmp/mini_sr.py:/m.py kafka-pybench:3.12 /app/.venv/bin/python /m.py"
