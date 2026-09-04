"""把当前请求的 trace_id / user_id 注入每条日志记录。

课 18 的结论：日志要能按请求聚合，靠的就是这个 filter。
没有它，出了问题只能在一堆日志里人肉找同一次请求。
"""
import logging

from apps.common.middleware import get_trace_id, get_user_id


class TraceIdFilter(logging.Filter):
    def filter(self, record):
        # 用 setdefault：允许调用方用 logger.info("...", extra={"trace_id": "xxx"}) 覆盖
        if not hasattr(record, "trace_id"):
            record.trace_id = get_trace_id()
        if not hasattr(record, "user_id"):
            record.user_id = get_user_id()
        return True
