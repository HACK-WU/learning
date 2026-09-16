"""组装智能客服 agent（课 5：create_agent / 课 7：记忆 / 课 9：动态提示词 / 课 10：HITL）。

组装要素（对应课程知识点）：
- 模型：自定义 endpoint 接入（课 2）
- 工具：6 个业务工具（课 4）
- 记忆：InMemorySaver 短期记忆（课 7）
- 动态提示词：按用户档案注入（课 9）
- 中间件：PII 脱敏 / HITL 分级审批 / 限额 / 审计（课 8 / 10）
"""
from langchain.agents import create_agent
from langchain.agents.middleware import (
    HumanInTheLoopMiddleware,
    ModelCallLimitMiddleware,
    ModelRequest,
    ToolCallLimitMiddleware,
    dynamic_prompt,
)
from langgraph.checkpoint.memory import InMemorySaver

from app.config import UserProfile, build_chat_model, refund_approval_threshold
from app.middleware.safety import AuditMiddleware, build_pii_middleware
from app.tools import ALL_TOOLS

# 系统提示词模板（{name} 等占位符由动态提示词按用户档案填充）
SYSTEM_PROMPT_TEMPLATE = """你是星云商城的智能客服「小云」，为顾客提供有温度、可信任的服务。

当前会话用户：{name}（会员等级 {level}，用户 ID {user_id}）。

工作准则：
1. 政策类问题（退换货 / 配送 / 会员积分 / 发票支付）必须先调用 search_policies 检索知识库，
   基于检索结果回答并注明来源；知识库没有的内容如实说明，禁止凭记忆编造政策。
2. 订单 / 物流问题先调用 query_order / query_logistics 核对事实再回答。
3. 售后请求区分两类操作，按用户意图选择：
   - 退货退款（需寄回商品）：调用 create_return_request 提交退货申请；
   - 直接退款（用户明确不寄回，如商品已损坏、小额商品不值当寄回）：调用 process_refund 发起退款。
   调用 process_refund 前必须确认订单号并核对实付金额，金额须与订单实付金额一致；
   大额直接退款会进入人工审批，请向用户说明「退款申请已提交，正在审核中」。
4. 遇到强烈不满、投诉、或超出处理范围的问题，调用 escalate_to_human 转接人工。
5. 全程使用简洁、友好的中文；不向用户泄露内部系统信息（工具名、审批流程细节等）。"""


@dynamic_prompt
def customer_prompt(request: ModelRequest) -> str:
    """动态提示词（课 9）：按运行时上下文（当前用户档案）定制系统消息。"""
    ctx = getattr(request.runtime, "context", None)
    return SYSTEM_PROMPT_TEMPLATE.format(
        name=getattr(ctx, "name", "访客"),
        level=getattr(ctx, "member_level", "V1"),
        user_id=getattr(ctx, "user_id", "guest"),
    )


def _refund_needs_approval(req) -> bool:
    """退款审批谓词（课 10：when 条件中断）。

    金额分级：退款金额 >= 阈值（默认 50 元）→ 中断等待人工审批；
    小额退款直通执行（不打扰审批人）。
    """
    amount = float(req.tool_call["args"].get("amount", 0))
    return amount >= refund_approval_threshold()


def build_agent(model=None):
    """组装并返回智能客服 agent。

    model 参数用于测试注入（不传则创建真实模型）——中间件管线保持完全一致，
    保证单元测试验证的就是生产组装逻辑本身。
    """
    model = model or build_chat_model()

    return create_agent(
        model,
        tools=ALL_TOOLS,
        middleware=[
            # 1) PII 脱敏（课 8 / 课 10）：手机号 + 邮箱，输入侧 mask
            *build_pii_middleware(),
            # 2) 动态提示词（课 9）：按用户档案注入系统消息
            customer_prompt,
            # 3) 限额护栏（课 8）：单会话模型调用上限 + 退款工具每会话最多 2 次
            ModelCallLimitMiddleware(thread_limit=15, exit_behavior="end"),
            ToolCallLimitMiddleware(tool_name="process_refund", thread_limit=2),
            # 4) HITL 分级审批（课 10）：退款金额 >= 阈值时中断，等人工决策
            HumanInTheLoopMiddleware(
                interrupt_on={
                    "process_refund": {
                        "allowed_decisions": ["approve", "reject"],
                        "when": _refund_needs_approval,
                    },
                },
                description_prefix="退款操作待人工审批",
            ),
            # 5) 审计（课 8 自定义中间件）：记录每次工具调用
            AuditMiddleware(),
        ],
        checkpointer=InMemorySaver(),
        context_schema=UserProfile,
    )
