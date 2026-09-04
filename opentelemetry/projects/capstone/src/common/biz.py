"""故障注入与业务模拟。

课 1 场景复刻：下单链路 checkout → payment → risk-control → user-profile → 慢 SQL。
根因是 user-profile 里一条缺索引的 SQL（db.index_used=false，全表扫描 482 万行）。

故障开关通过环境变量 CAP_FAULT 控制：
  off       —— 正常
  slowsql   —— user-profile 慢查询（课 1 根因）
  nplus1    —— risk-control N+1 查询
  pool      —— payment 下游超时

注意：这是演示用的故障注入，真实项目绝不能把这种开关带进生产。
"""
import os
import random
import time

# 模拟数据集规模。刻意设为 10 万级，用于暴露「循环里做数据库操作」的写法问题
# （见评审必查项 #28：示例数据量要小到能跑，但写法必须大到 10 万行也不炸）。
USER_TABLE_ROWS = 4_820_000
PAGE_SIZE = 200


def fault_mode():
    return os.getenv("CAP_FAULT", "off")


def _sleep(base, jitter=0.02):
    time.sleep(base + random.uniform(0, jitter))


def query_user_profile(user_id, tracer, logger):
    """user-profile 的核心查询。

    正常路径：命中索引，~8ms。
    慢 SQL 故障路径：全表扫描 482 万行，~4.2s —— 课 1 的真实根因。
    """
    mode = fault_mode()
    with tracer.start_as_current_span("db.query.user_profile") as span:
        span.set_attribute("db.system", "mysql")
        span.set_attribute("db.namespace", "shop")
        span.set_attribute("db.query.text", "SELECT * FROM users WHERE id = ?")
        span.set_attribute("db.rows_scanned", USER_TABLE_ROWS if mode == "slowsql" else 1)

        if mode == "slowsql":
            span.set_attribute("db.index_used", False)
            span.set_attribute("db.query.duration_ms", 4200)
            logger.warning(
                "slow query detected rows_scanned=%d index_used=false",
                USER_TABLE_ROWS,
            )
            _sleep(4.2, 0.1)
        else:
            span.set_attribute("db.index_used", True)
            span.set_attribute("db.query.duration_ms", 8)
            logger.info("query ok rows_scanned=1 index_used=true")
            _sleep(0.008)

    return {"user_id": user_id, "level": "gold", "credit_score": 742}


def risk_check(user_id, tracer, logger):
    """风控检查。

    正常：一次批量查询。
    nplus1 故障：循环里逐条查库 —— 200 次数据库往返。
    """
    mode = fault_mode()
    with tracer.start_as_current_span("risk.evaluate") as span:
        span.set_attribute("risk.user_id", user_id)

        if mode == "nplus1":
            # 反例：循环体内逐条查询，O(N) 次数据库往返。
            # N=200 时已经 0.6s；N=10 万时会是 300s+，直接拖垮服务。
            span.set_attribute("risk.mode", "nplus1")
            hit = 0
            for i in range(PAGE_SIZE):
                with tracer.start_as_current_span("db.query.rule") as sub:
                    sub.set_attribute("db.system", "mysql")
                    sub.set_attribute("rule.index", i)
                    _sleep(0.003)
                    hit += 1
            span.set_attribute("risk.rules_checked", hit)
            span.set_attribute("risk.db_roundtrips", PAGE_SIZE)
            logger.warning("nplus1 pattern: %d db roundtrips for one request", PAGE_SIZE)
        else:
            # 正例：一次批量查询拿到全部规则，循环体内只有内存计算。
            # 即使规则数放大到 10 万，也只是多一次批量分页，不是多 10 万次往返。
            span.set_attribute("risk.mode", "batch")
            with tracer.start_as_current_span("db.query.rules_batch") as sub:
                sub.set_attribute("db.system", "mysql")
                sub.set_attribute("db.rows_scanned", PAGE_SIZE)
                _sleep(0.05)
            span.set_attribute("risk.rules_checked", PAGE_SIZE)
            span.set_attribute("risk.db_roundtrips", 1)
            logger.info("batch query ok roundtrips=1")

    return {"risk_pass": True, "score": 12}


def charge(amount, tracer, logger):
    """支付扣款。pool 故障下模拟下游连接池耗尽导致超时。"""
    mode = fault_mode()
    with tracer.start_as_current_span("payment.charge") as span:
        span.set_attribute("payment.amount", amount)
        span.set_attribute("payment.currency", "CNY")

        if mode == "pool":
            span.set_attribute("payment.pool_exhausted", True)
            span.set_attribute("error.type", "TimeoutError")
            logger.error("connection pool exhausted, waited 3000ms then timeout")
            _sleep(3.0)
            return {"paid": False, "reason": "pool exhausted"}
        span.set_attribute("payment.pool_exhausted", False)
        _sleep(0.04)
        return {"paid": True, "txn_id": "txn-%08d" % random.randint(1, 99_999_999)}
