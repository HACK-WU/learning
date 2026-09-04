"""结构化日志 formatter（课 18 的落点）。

为什么必须自己写：默认的日志格式是人类可读的多行文本，
日志采集 agent（Filebeat / Fluent Bit）按行读取时会把它切碎。
"""
import json
import logging

# 标准库 LogRecord 自带的属性。排除它们，剩下的就是 extra 里传进来的自定义字段。
_STD_ATTRS = {
    "args", "asctime", "created", "exc_info", "exc_text", "filename",
    "funcName", "levelname", "levelno", "lineno", "module", "msecs",
    "message", "msg", "name", "pathname", "process", "processName",
    "relativeCreated", "stack_info", "thread", "threadName", "taskName",
}


class JsonFormatter(logging.Formatter):
    """把每条日志渲染成一行 JSON。"""

    def format(self, record):
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
            # trace_id / user_id 由 TraceIdFilter 注入
            "trace_id": getattr(record, "trace_id", "-"),
            "user_id": getattr(record, "user_id", "-"),
        }
        # extra 里的其他字段原样带出
        for key, value in record.__dict__.items():
            if key not in _STD_ATTRS and key not in payload:
                payload[key] = value
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)
