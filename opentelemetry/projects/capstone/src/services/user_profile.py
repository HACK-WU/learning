"""user-profile 服务（5063）—— 链路最下游，慢 SQL 根因所在。"""
import os
import sys

from flask import Flask, jsonify, request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common.otel_setup import setup_otel
from common.biz import query_user_profile

SERVICE = "user-profile"
tracer, meter, logger = setup_otel(SERVICE, "1.0.0")
app = Flask(__name__)

# 指标：请求计数 + 查询耗时直方图（课 7 的 histogram）
query_counter = meter.create_counter(
    "user_profile_queries_total", description="用户资料查询次数", unit="1"
)
query_hist = meter.create_histogram(
    "user_profile_query_duration_ms",
    description="用户资料查询耗时",
    unit="ms",
)


@app.route("/user/profile", methods=["POST"])
def profile():
    with tracer.start_as_current_span("user-profile.handle") as span:
        data = request.get_json(force=True) or {}
        user_id = data.get("user_id", "unknown")
        span.set_attribute("user.id", user_id)

        result = query_user_profile(user_id, tracer, logger)

        dur = result.get("duration_ms")
        if dur is None:
            dur = 4200 if os.getenv("CAP_FAULT") == "slowsql" else 8
        query_hist.record(dur, {"user.level": result["level"]})
        query_counter.add(1, {"user.level": result["level"]})

        result["duration_ms"] = dur
        return jsonify(result)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5063, threaded=True)
