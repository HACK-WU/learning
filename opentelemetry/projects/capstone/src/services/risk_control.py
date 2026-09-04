"""risk-control 服务（5062）—— 风控，N+1 故障注入点。"""
import os
import sys

from flask import Flask, jsonify, request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common.otel_setup import setup_otel
from common.biz import risk_check
from common.http_client import call_downstream, downstream_url

SERVICE = "risk-control"
tracer, meter, logger = setup_otel(SERVICE, "1.0.0")
app = Flask(__name__)

check_counter = meter.create_counter(
    "risk_checks_total", description="风控检查次数", unit="1"
)
roundtrip_hist = meter.create_histogram(
    "risk_db_roundtrips", description="单次风控的数据库往返次数", unit="1"
)


@app.route("/risk/check", methods=["POST"])
def check():
    with tracer.start_as_current_span("risk-control.handle") as span:
        data = request.get_json(force=True) or {}
        user_id = data.get("user_id", "unknown")
        span.set_attribute("user.id", user_id)

        # 风控需要用户画像作为入参
        prof = call_downstream(
            downstream_url("user-profile", "/user/profile"), {"user_id": user_id}
        )
        span.set_attribute("user.level", prof.get("level", "unknown"))

        verdict = risk_check(user_id, tracer, logger)

        rt = verdict.get("db_roundtrips", 1)
        roundtrip_hist.record(rt)
        check_counter.add(1, {"risk.pass": str(verdict["risk_pass"])})

        return jsonify({**verdict, "user_level": prof.get("level")})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5062, threaded=True)
