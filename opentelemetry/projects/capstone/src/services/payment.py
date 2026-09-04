"""payment 服务（5061）—— 支付，连接池故障注入点。"""
import os
import sys

from flask import Flask, jsonify, request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common.otel_setup import setup_otel
from common.biz import charge
from common.http_client import call_downstream, downstream_url

SERVICE = "payment"
tracer, meter, logger = setup_otel(SERVICE, "1.0.0")
app = Flask(__name__)

charge_counter = meter.create_counter(
    "payments_total", description="支付次数", unit="1"
)
amount_hist = meter.create_histogram(
    "payment_amount", description="支付金额分布", unit="CNY"
)


@app.route("/pay", methods=["POST"])
def pay():
    with tracer.start_as_current_span("payment.handle") as span:
        data = request.get_json(force=True) or {}
        order_id = data.get("order_id", "unknown")
        amount = float(data.get("amount", 0))
        span.set_attribute("order.id", order_id)
        span.set_attribute("payment.amount", amount)

        # 支付前先过风控
        risk = call_downstream(
            downstream_url("risk-control", "/risk/check"),
            {"user_id": data.get("user_id", "unknown")},
        )
        span.set_attribute("risk.pass", str(risk.get("risk_pass")))

        result = charge(amount, tracer, logger)

        charge_counter.add(1, {"payment.paid": str(result["paid"])})
        amount_hist.record(amount)

        if not result["paid"]:
            logger.error("payment failed order=%s reason=%s", order_id, result["reason"])
            return jsonify({**result, "order_id": order_id}), 502

        return jsonify({**result, "order_id": order_id, "risk": risk})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": SERVICE})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5061, threaded=True)
