"""课 5：统一错误结构。

问题：DRF 自带的异常只覆盖"它认识的"（校验失败、权限拒绝、404），
而 service 层抛的业务异常（库存不足、订单状态不对）会变成 500，
且响应体是纯文本 —— 前端拿不到稳定的字段可以判断。

目标：不管是校验错误、权限错误还是业务错误，**响应结构一致**：
    {"code": "...", "message": "...", "details": {...}, "trace_id": "..."}

⚠️ trace_id 必须回传：前端报障时给一个 id，后端能直接捞到那次请求的全部日志。
"""
import logging

from rest_framework import status
from rest_framework.views import exception_handler

from apps.common.middleware import get_trace_id

logger = logging.getLogger("shop")


class BusinessError(Exception):
    """业务异常的基类。

    带 code 与 http_status：让 service 层能精确表达"这是什么错"。
    """

    code = "business_error"
    message = "业务处理失败"
    http_status = status.HTTP_400_BAD_REQUEST

    def __init__(self, message=None, details=None, code=None, http_status=None):
        self.message = message or self.message
        self.details = details or {}
        if code:
            self.code = code
        if http_status:
            self.http_status = http_status
        super().__init__(self.message)


class OutOfStockError(BusinessError):
    code = "out_of_stock"
    message = "库存不足"
    http_status = status.HTTP_409_CONFLICT


class InvalidStatusTransition(BusinessError):
    code = "invalid_status_transition"
    message = "订单当前状态不允许该操作"
    http_status = status.HTTP_409_CONFLICT


def custom_exception_handler(exc, context):
    """DRF 的 EXCEPTION_HANDLER 钩子。"""
    # BusinessError 不是 DRF 的 APIException，DRF 默认不认识，会返回 None（→500）
    if isinstance(exc, BusinessError):
        logger.warning(
            "业务异常 code=%s message=%s", exc.code, exc.message,
            extra={"biz_code": exc.code},
        )
        return _build_response(exc.code, exc.message, exc.details, exc.http_status)

    response = exception_handler(exc, context)
    if response is None:
        # 未被处理的异常：记日志（带 trace_id），但不把堆栈泄漏给前端
        logger.exception("未处理异常: %s", exc)
        return _build_response(
            "internal_error", "服务器内部错误", {}, status.HTTP_500_INTERNAL_SERVER_ERROR
        )

    return _normalize_drf_response(response)


def _normalize_drf_response(response):
    """把 DRF 五花八门的响应体（str / list / dict）统一成一个结构。"""
    data = response.data
    code = _code_for_status(response.status_code)
    details = {}
    message = "请求失败"

    if isinstance(data, dict):
        # 校验错误：{"field": ["msg"]} → details 里保留字段级信息
        if "detail" in data:
            message = str(data["detail"])
            code = _code_for_detail(data["detail"], code)
        else:
            message = "参数校验失败"
            details = {k: _as_list(v) for k, v in data.items()}
    elif isinstance(data, list):
        message = " ".join(str(x) for x in data)

    return _build_response(code, message, details, response.status_code)


def _as_list(v):
    if isinstance(v, list):
        return [str(x) for x in v]
    return [str(v)]


def _code_for_status(status_code):
    return {
        400: "bad_request",
        401: "unauthenticated",
        403: "permission_denied",
        404: "not_found",
        405: "method_not_allowed",
        429: "throttled",
    }.get(status_code, "error")


def _code_for_detail(detail, default):
    """DRF 的 detail 里有 ErrorDetail，带 .code 时优先用它。"""
    code = getattr(detail, "code", None)
    if code:
        return str(code)
    return default


def _build_response(code, message, details, http_status):
    from rest_framework.response import Response

    payload = {
        "code": code,
        "message": message,
        "details": details,
        "trace_id": get_trace_id(),
    }
    return Response(payload, status=http_status)
