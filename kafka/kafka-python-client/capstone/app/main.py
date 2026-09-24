"""课 13 —— FastAPI 服务入口（课 11 asyncio 判据落地）。

对应课程：
  - 课 11：async 框架该用哪个库 —— 本课用 **confluent-kafka + 后台线程**，不用 aiokafka
    理由（课 11 实测）：confluent 的 AIOConsumer/AIOProducer 是「同步客户端 +
    ThreadPoolExecutor(max_workers=2)」包装，不是真 async IO；而 librdkafka 本身
    就有后台线程。**再包一层线程池只是多一次线程切换**，没有收益。
  - 课 12：/metrics + /health 可观测端点

架构：
    FastAPI (async 事件循环)
        ├── POST /orders   -> 投递到 Kafka（同步 produce，不 await）
        ├── GET  /metrics  -> Prometheus 文本格式
        ├── GET  /health   -> 健康检查（就绪/存活分离）
        └── 后台线程 OrderWorker -> 消费 + 手动提交 + DLQ
"""

from __future__ import annotations

import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel, Field

from . import config, metrics
from .kafka_client import OrderProducer, ensure_topics
from .schema import OrderEvent, ValidationError, validate_order
from .worker import OrderWorker, install_signal_handlers

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
)
log = logging.getLogger("capstone")

_START_TS = time.time()

# 全局单例（生产里用依赖注入，这里为教学可读性简化）
_producer: OrderProducer | None = None
_worker: OrderWorker | None = None


# ---------- 生命周期 ----------


@asynccontextmanager
async def lifespan(app: FastAPI):
    """启动/关闭钩子。

    启动顺序有讲究：**先建 topic，再起消费者**。
    反过来的话消费者会因为 topic 不存在而报 UNKNOWN_TOPIC_OR_PART。
    """
    global _producer, _worker
    log.info("启动中… brokers=%s", config.BROKERS)

    topics = ensure_topics()
    log.info("topic 就绪状态: %s", topics)

    _producer = OrderProducer()
    _producer.start()

    _worker = OrderWorker(producer=_producer._p)
    _worker.start()
    install_signal_handlers(_worker)

    log.info("服务就绪")
    yield

    # ---- 关闭：顺序与启动相反 ----
    log.info("关闭中…")
    if _worker:
        _worker.stop(timeout=30)
    if _producer:
        _producer.close()
    log.info("已关闭")


app = FastAPI(title="Kafka Capstone Service", version="1.0.0", lifespan=lifespan)


# ---------- 请求/响应模型 ----------


class OrderIn(BaseModel):
    order_id: str = Field(..., min_length=1, max_length=64)
    user_id: str = Field(..., min_length=1, max_length=64)
    amount: float = Field(..., gt=0, le=10_000_000)
    currency: str = Field(default="CNY")
    items: list[dict] | None = None


class OrderOut(BaseModel):
    accepted: bool
    order_id: str
    topic: str
    partition: int | None = None


# ---------- 端点 ----------


@app.post("/orders", response_model=OrderOut)
async def create_order(o: OrderIn) -> OrderOut:
    """投递一条订单。

    ⚠️ 刻意不 await Kafka：produce() 是**非阻塞入队**，真正投递由后台线程完成。
    这是 confluent-kafka 的正确用法 —— 如果这里 await 一个假的 async 包装，
    只是把线程切换开销加上去（课 11 结论）。
    """
    if _producer is None:
        raise HTTPException(status_code=503, detail="生产者未就绪")

    # 用与消费者同一套契约校验，保证入口拦截的坏消息不会进 topic
    try:
        validate_order(o.model_dump())
    except ValidationError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e

    ev = OrderEvent(
        order_id=o.order_id, user_id=o.user_id,
        amount=o.amount, currency=o.currency, items=o.items,
    )
    try:
        _producer.produce(key=o.order_id, value=ev.to_json())
    except Exception as e:  # noqa: BLE001
        log.exception("投递失败")
        raise HTTPException(status_code=500, detail=f"投递失败: {e}") from e

    metrics.PRODUCED.inc(1, result="accepted")
    return OrderOut(accepted=True, order_id=o.order_id, topic=config.TOPIC_ORDERS)


@app.post("/orders/batch")
async def create_orders_batch(orders: list[OrderIn]) -> dict:
    """批量投递 —— 演示吞吐优势（课 7）。

    单条 produce 也走同样的攒批（linger.ms=5），但**减少 HTTP 往返**是主要收益。
    """
    if _producer is None:
        raise HTTPException(status_code=503, detail="生产者未就绪")
    if len(orders) > 1000:
        raise HTTPException(status_code=413, detail="单批最多 1000 条")

    accepted, rejected = 0, []
    for o in orders:
        try:
            validate_order(o.model_dump())
        except ValidationError as e:
            rejected.append({"order_id": o.order_id, "reason": str(e)})
            continue
        ev = OrderEvent(order_id=o.order_id, user_id=o.user_id,
                        amount=o.amount, currency=o.currency, items=o.items)
        _producer.produce(key=o.order_id, value=ev.to_json())
        accepted += 1

    return {"accepted": accepted, "rejected": rejected}


@app.get("/metrics")
async def get_metrics() -> Response:
    """Prometheus 抓取端点（课 12）。

    lag 从 worker 快照读 —— 不在这里实时算，避免 scrape 请求打到 Kafka。
    """
    lag = _worker.lag_snapshot() if _worker else {}
    body = metrics.render_metrics(lag)
    return Response(content=body, media_type="text/plain; version=0.0.4; charset=utf-8")


@app.get("/health")
async def health() -> dict:
    """存活探针：进程活着就 True。**

    **不要在这里检查 Kafka** —— k8s liveness 失败会重启容器，
    Kafka 抖动导致全量重启是典型雪崩（课 12 健康检查原则）。
    """
    return {"status": "alive", "uptime_seconds": round(time.time() - _START_TS, 1)}


@app.get("/ready")
async def ready() -> dict:
    """就绪探针：能服务才 True。**

    与 /health 分离是刻意的：Kafka 短暂不可用时应**摘流量**而不是**重启**。
    """
    if _worker is None or _producer is None:
        raise HTTPException(status_code=503, detail="未就绪")
    ok, reason = _worker.is_healthy()
    if not ok:
        raise HTTPException(status_code=503, detail=reason)
    return {"status": "ready", "group": config.GROUP_ID, "reason": reason}


@app.get("/stats")
async def stats() -> dict:
    """内部状态（调试用，非 Prometheus 格式）。"""
    if _worker is None:
        return {}
    s = _worker.stats
    return {
        "consumed_ok": s.ok,
        "validation_error": s.validation_error,
        "processing_error": s.processing_error,
        "dlq": s.dlq,
        "committed": s.committed,
        "rebalances": s.rebalances,
        "partitions_revoked": s.partitions_revoked,
        "lag_total": _worker.lag_total(),
        "lag_by_partition": {str(p): v for (_, p), v in _worker.lag_snapshot().items()},
    }


@app.post("/admin/flush")
async def admin_flush(timeout: float = 10.0) -> dict:
    """等待在途消息全部确认（课 6：确认语义的可观测入口）。"""
    if _producer is None:
        raise HTTPException(status_code=503, detail="生产者未就绪")
    remaining = _producer.flush(timeout)
    return {
        "remaining": remaining,
        "delivered": _producer.delivered,
        "failed": _producer.failed,
    }
