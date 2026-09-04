"""课 18：给每个请求挂上 trace_id，并贯穿到日志与响应头。

为什么中间件要放在最后（最内层）：
  它在 __call__ 的最内层执行，能保证后续任何 view / service / ORM 调用
  都能通过 contextvars 拿到当前请求的 trace_id。

为什么用 contextvars 而不是 threading.local：
  课 16 讲过——异步视图下多个请求可能复用同一线程，threading.local 会串号。
"""
import uuid
from contextvars import ContextVar

# 当前请求的上下文。注意：ContextVar 必须在模块层定义，
# 不能每次请求新建，否则拿到的永远是默认值。
_trace_id_var: ContextVar[str] = ContextVar("trace_id", default="-")
_user_id_var: ContextVar[str] = ContextVar("user_id", default="-")

TRACE_HEADER = "X-Request-Id"
RESPONSE_HEADER = "X-Request-Id"


def get_trace_id() -> str:
    """供日志 filter、service、序列化器等任何地方读取当前 trace_id。"""
    return _trace_id_var.get()


def get_user_id() -> str:
    return _user_id_var.get()


class RequestContextMiddleware:
    """入站取 X-Request-Id（没有就生成），出站写回响应头。"""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        incoming = request.META.get("HTTP_X_REQUEST_ID", "").strip()
        # ⚠️ 不能无条件信任客户端传来的值——它可能超长或含非法字符。
        # 简单校验：只接受 8-64 位的可打印 ASCII，其余一律重新生成。
        if incoming and 8 <= len(incoming) <= 64 and incoming.isprintable():
            trace_id = incoming
        else:
            trace_id = uuid.uuid4().hex

        token = _trace_id_var.set(trace_id)

        user = getattr(request, "user", None)
        uid = getattr(user, "pk", None) if user else None
        user_token = _user_id_var.set(str(uid) if uid else "-")

        try:
            response = self.get_response(request)
        finally:
            # ⚠️ 必须 finally reset，否则 contextvar 会泄漏到下一个请求
            _trace_id_var.reset(token)
            _user_id_var.reset(user_token)

        response[RESPONSE_HEADER] = trace_id
        return response
