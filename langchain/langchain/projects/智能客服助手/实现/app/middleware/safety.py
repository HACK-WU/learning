"""安全护栏与审计（课 8：自定义中间件 / 课 10：PII 自定义 detector）。

本模块落地两件事：
1. 手机号脱敏：PIIMiddleware 内置类型不含中国手机号，用「自定义 detector」注册
   （课 10 实测：detector 返回 PIIMatch{type,value,start,end} 列表）
2. 审计中间件：自定义 AgentMiddleware，记录每次工具调用的完整轨迹
   （课 8 知识点：自定义中间件的 wrap_tool_call 钩子；呼应课 13 可观测性）
"""
import re
import time

from langchain.agents.middleware import AgentMiddleware, PIIMatch, PIIMiddleware

# 审计轨迹（模块级账本，演示与测试断言用；生产应写日志系统）
AUDIT_LOG: list[dict] = []


def phone_detector(text: str) -> list[PIIMatch]:
    """检测中国大陆手机号（课 10：PIIMiddleware 的自定义 detector）。"""
    matches: list[PIIMatch] = []
    for m in re.finditer(r"1[3-9]\d{9}", text):
        matches.append(
            PIIMatch(type="phone", value=m.group(0), start=m.start(), end=m.end())
        )
    return matches


def build_pii_middleware() -> list:
    """PII 脱敏中间件组（课 8 内置中间件 + 课 10 PII 策略）。

    - 手机号：自定义 detector + mask（138****5678）
    - 邮箱：内置类型 + mask
    - apply_to_input=True：进入模型前处理（用户输入侧防护）
    """
    return [
        PIIMiddleware(
            "phone", detector=phone_detector, strategy="mask", apply_to_input=True
        ),
        PIIMiddleware("email", strategy="mask", apply_to_input=True),
    ]


class AuditMiddleware(AgentMiddleware):
    """自定义中间件（课 8）：把每一次**实际执行**的工具调用记录进审计轨迹。

    记录字段：工具名 / 参数 / 耗时 / 结果摘要（或失败标记）。
    注意：被 HITL 拦截（等待审批中）的工具尚未执行，不会出现在审计里——
    审计记录的是"发生了什么"，不是"尝试过什么"（每次执行成功/失败都留痕）。
    """

    def wrap_tool_call(self, request, handler):
        name = request.tool_call["name"]
        args = request.tool_call["args"]
        t0 = time.time()

        try:
            result = handler(request)
        except Exception:
            # 工具失败 / 被中间件拦截（如 HITL 中断）：记录后继续抛给上层
            AUDIT_LOG.append(
                {
                    "tool": name,
                    "args": args,
                    "seconds": round(time.time() - t0, 3),
                    "result": "(blocked or error)",
                }
            )
            raise

        AUDIT_LOG.append(
            {
                "tool": name,
                "args": args,
                "seconds": round(time.time() - t0, 3),
                "result": str(getattr(result, "content", result))[:90],
            }
        )
        return result
