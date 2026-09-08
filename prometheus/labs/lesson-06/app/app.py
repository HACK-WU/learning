"""课6 app：可控基数 + 可控生死的指标源。

设计要点：
1. 基数可控：/cardinality?n=NNN 生成 NNN 条不同 label 的序列，用于成本实验。
2. 生死可控：/kill 让某 job 的序列停止暴露，用于 staleness 实验。
3. 行为可控：/wobble?mode=on 制造错误率波动，承接课4/课5 的场景。
4. 计数器语义正确：错误数单调递增（可被 rate() 正确计算）。
"""

import random
import time

from flask import Flask, Response, request

app = Flask(__name__)

START = time.time()

# 全局可变状态：由 /kill、/revive、/wobble 控制
STATE = {
    "alive": True,          # 主序列是否继续暴露
    "broken": False,        # /metrics 是否返回 500（模拟抓取失败）
    "error_rate": 0.02,     # 错误率
    "zone": "zone-a",
}

# 单调递增计数器（模拟累计请求数 / 错误数）
TOTAL = {"requests": 0, "errors": 0}

# 供 /cardinality 使用的高基数序列值
CARD_VALUES = {}


def fmt(name, labels, value):
    """输出一行 OpenMetrics 文本格式的样本。"""
    if labels:
        ls = ",".join(f'{k}="{v}"' for k, v in labels.items())
        return f"{name}{{{ls}}} {value}\n"
    return f"{name} {value}\n"


@app.route("/metrics")
def metrics():
    # 抓取失败：返回 500。Prometheus 判定 scrape 失败，
    # 不会为这些序列插入 stale marker（关键对照点）
    if STATE["broken"]:
        return Response("scrape failed on purpose\n", status=500,
                        mimetype="text/plain")

    uptime = time.time() - START
    out = []

    # --- 基础序列：始终存在（除非被 kill）---
    if STATE["alive"]:
        # 模拟请求速率与错误率
        rps = 50 + 20 * (1 + (uptime % 60) / 60)      # 50~120 之间摆动
        TOTAL["requests"] += int(rps)
        err_rate = STATE["error_rate"]
        TOTAL["errors"] += int(rps * err_rate)

        out.append("# HELP l6_requests_total Total requests.\n")
        out.append("# TYPE l6_requests_total counter\n")
        out.append(fmt("l6_requests_total", {"zone": STATE["zone"]},
                       TOTAL["requests"]))

        out.append("# HELP l6_errors_total Total errors.\n")
        out.append("# TYPE l6_errors_total counter\n")
        out.append(fmt("l6_errors_total", {"zone": STATE["zone"]},
                       TOTAL["errors"]))

        # 一个 gauge：当前并发（带抖动，便于看 staleness 断点）
        out.append("# HELP l6_concurrency Current concurrency.\n")
        out.append("# TYPE l6_concurrency gauge\n")
        out.append(fmt("l6_concurrency", {"zone": STATE["zone"]},
                       int(20 + 10 * random.random())))
    else:
        # 被 kill：不再暴露 l6_* 业务指标
        # 注意：/metrics 仍返回 200，只是没有 l6_ 序列
        # —— 这精确模拟了"进程还在、但目标指标消失"的场景
        pass

    # --- 高基数序列：受 /cardinality 控制 ---
    if CARD_VALUES:
        out.append("# HELP l6_card_metric High cardinality test metric.\n")
        out.append("# TYPE l6_card_metric gauge\n")
        for k, v in CARD_VALUES.items():
            out.append(fmt("l6_card_metric", {"idx": k}, v))

    # --- up 指标：始终暴露 ---
    out.append("# HELP l6_up Whether this target exposes business metrics.\n")
    out.append("# TYPE l6_up gauge\n")
    out.append(fmt("l6_up", {}, 1 if STATE["alive"] else 0))

    return Response("".join(out), mimetype="text/plain; version=0.0.4")


@app.route("/cardinality")
def cardinality():
    """生成 n 条高基数序列。用法：/cardinality?n=5000"""
    n = int(request.args.get("n", "1000"))
    CARD_VALUES.clear()
    for i in range(n):
        CARD_VALUES[f"{i:06d}"] = i % 100
    return {"ok": True, "series": len(CARD_VALUES)}


@app.route("/kill")
def kill():
    """停止暴露业务指标（模拟目标消失 / 指标停止上报）。"""
    STATE["alive"] = False
    return {"ok": True, "alive": STATE["alive"],
            "hint": "业务序列已停止暴露，/metrics 只返回 l6_up=0"}


@app.route("/revive")
def revive():
    """恢复暴露业务指标。"""
    STATE["alive"] = True
    return {"ok": True, "alive": STATE["alive"]}


@app.route("/wobble")
def wobble():
    """切换错误率。用法：/wobble?rate=0.35"""
    rate = request.args.get("rate")
    if rate is not None:
        STATE["error_rate"] = float(rate)
    else:
        STATE["error_rate"] = 0.35 if STATE["error_rate"] < 0.1 else 0.02
    return {"ok": True, "error_rate": STATE["error_rate"]}


@app.route("/break")
def do_break():
    """让 /metrics 返回 HTTP 500（模拟抓取失败）。

    与 /kill 的区别（本课核心对照）：
    - /kill   → 抓取成功、但序列消失 → Prometheus 插入 stale marker
    - /break  → 抓取失败           → Prometheus 不插入 stale marker
    """
    STATE["broken"] = True
    return {"ok": True, "broken": STATE["broken"],
            "hint": "/metrics 现在返回 500"}


@app.route("/unbreak")
def unbreak():
    STATE["broken"] = False
    return {"ok": True, "broken": STATE["broken"]}


@app.route("/health")
def health():
    return {"status": "ok", "alive": STATE["alive"],
            "broken": STATE["broken"],
            "error_rate": STATE["error_rate"],
            "series": len(CARD_VALUES)}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
