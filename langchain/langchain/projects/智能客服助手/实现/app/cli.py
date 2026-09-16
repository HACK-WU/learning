"""交互式命令行入口（课 6：流式输出 + 课 10：审批交互）。

运行：uv run python -m app.cli

- 回复以打字机方式流式输出（课 6：stream_mode="messages" 逐 token）
- 遇到退款审批中断时，在命令行做 approve / reject 决策（课 10）
"""
import json

from langgraph.types import Command

from app.agent import build_agent
from app.config import UserProfile


def _stream_turn(agent, payload, cfg, profile):
    """流式执行一轮（payload 为消息输入或 Command），打印文本增量。

    返回：若发生审批中断则返回中断列表，否则 None。
    课 6：混合模式 stream_mode=["messages", "updates"]——token 逐字 + 进度事件。
    """
    interrupt = None
    for chunk in agent.stream(
        payload,
        cfg,
        context=profile,
        stream_mode=["messages", "updates"],
        version="v2",
    ):
        if chunk["type"] == "messages":
            token, metadata = chunk["data"]
            if metadata.get("langgraph_node") != "model":
                continue
            if hasattr(token, "content_blocks") and token.content_blocks:
                for block in token.content_blocks:
                    if block.get("type") == "text" and block["text"]:
                        print(block["text"], end="", flush=True)
        elif chunk["type"] == "updates":
            data = chunk["data"]
            if isinstance(data, dict) and "__interrupt__" in data:
                interrupt = data["__interrupt__"]
    print()
    return interrupt


def _handle_approval(agent, intr, cfg, profile):
    """处理一次审批中断（批准 / 拒绝）；返回延续的中断（若有）。"""
    request = intr[0].value
    for ar in request["action_requests"]:
        print(
            f"\n[审批请求] 操作={ar['name']}｜参数={json.dumps(ar['args'], ensure_ascii=False)}"
        )
    decision = input("批准 / 拒绝？(y/n) > ").strip().lower()
    if decision == "y":
        payload = Command(resume={"decisions": [{"type": "approve"}]})
    else:
        message = input("拒绝理由（可留空）> ").strip() or "人工审核未通过"
        payload = Command(resume={"decisions": [{"type": "reject", "message": message}]})

    print("小云: ", end="", flush=True)
    return _stream_turn(agent, payload, cfg, profile)


def main() -> None:
    agent = build_agent()
    profile = UserProfile(user_id="u-cli", name="命令行用户", member_level="V2")
    cfg = {"configurable": {"thread_id": "cli-session"}}

    print("星云商城智能客服「小云」已上线（输入 exit 退出）\n")
    while True:
        text = input("你 > ").strip()
        if text.lower() in {"exit", "quit"}:
            print("再见！")
            break
        if not text:
            continue

        print("小云: ", end="", flush=True)
        intr = _stream_turn(
            agent,
            {"messages": [{"role": "user", "content": text}]},
            cfg,
            profile,
        )
        # 审批中断可能连续发生（如多次高风险操作），循环处理
        while intr:
            intr = _handle_approval(agent, intr, cfg, profile)


if __name__ == "__main__":
    main()
