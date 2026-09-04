"""checkout 服务（5060）—— 链路入口，模拟课 1 的下单请求。"""
import os
import random
import sys

from flask import Flask, jsonify, request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common.otel_setup import setup_otel
from common.http_client import call_downstream, downstream_url

SERVICE = "checkout"
tracer, meter, logger = setup_otel(SERVICE, "1.0.0")
app = Flask(__name__)

order_counter = meter.create_counter(
    "checkout_orders_total", description="下单请求数", unit="1"
)
latency_hist = meter.create_histogram(
    "checkout_latency_ms", description="下单端到端耗时", unit="ms"
)


@app.route("/checkout", methods=["POST"])
def checkout():
    import time

    t0 = time.time()
    with tracer.start_as_current_span("checkout.handle") as span:
        data = request.get_json(force=True) or {}
        order_id = data.get("order_id") or "ord-%08d" % random.randint(1, 99_999_999)
        user_id = data.get("user_id", "u-10086")
        amount = float(data.get("amount", 199.0))

        span.set_attribute("order.id", order_id)
        span.set_attribute("user.id", user_id)
        span.set_attribute("order.amount", amount)
        logger.info("checkout start order=%s user=%s", order_id, user_id)

        try:
            result = call_downstream(
                downstream_url("payment", "/pay"),
                {"order_id": order_id, "user_id": user_id, "amount": amount},
            )
        except Exception as exc:
            # 显式列出可预期的下游失败，不用裸 except Exception 静默跳过
            # （见评审必查项 #28：裸 except 会把支付失败变成「订单成功但没扣款」）
            span.record_exception(exc)
            span.set_attribute("error.type", type(exc).__name__)
            logger.error("checkout failed order=%s err=%s", order_id, exc)
            order_counter.add(1, {"checkout.result": "error"})
            return jsonify({"order_id": order_id, "status": "failed",
                            "reason": str(exc)}), 502

        dur_ms = (time.time() - t0) * 1000
        latency_hist.record(dur_ms)
        order_counter.add(1, {"checkout.result": "success"})
        logger.info("checkout done order=%s duration_ms=%.1f", order_id, dur_ms)

        return jsonify({"order_id": order_id, "status": "success",
                        "duration_ms": round(dur_ms, 1), "payment": result})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5060, threaded=True)
