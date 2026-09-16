"""第 4 课 · 补充实验：MCP 协议实测（裸链 / 适配器）与 headless 工具现状。

运行（在 playground 目录内）：

    uv run python lesson-04-mcp-lab.py

说明：
- A 部分只用 httpx 直连公共 MCP 服务器（docs.langchain.com/mcp），展示协议裸链，无需额外依赖。
- B 部分需要 langchain[mcp]（fastmcp）；未安装时自动跳过并提示安装命令。
"""

import asyncio
import json
import os

import httpx
from dotenv import load_dotenv

load_dotenv()

MCP_URL = "https://docs.langchain.com/mcp"
HEADERS_BASE = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
}


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}")


def parse_body(resp: httpx.Response):
    """兼容 JSON 与 SSE 两种响应体，抽出 JSON-RPC 对象。"""
    ct = resp.headers.get("content-type", "")
    text = resp.text.strip()
    if "text/event-stream" in ct:
        data_lines = [ln[5:].strip() for ln in text.splitlines() if ln.startswith("data:")]
        if not data_lines:
            return None
        return json.loads(data_lines[-1])
    return json.loads(text) if text else None


def main_raw():
    section("A. 裸链实测：手写 JSON-RPC 直连 MCP 服务器")
    with httpx.Client(timeout=40) as client:
        r = client.post(
            MCP_URL,
            headers=HEADERS_BASE,
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "lesson04-raw", "version": "0.1"},
                },
            },
        )
        sid = r.headers.get("mcp-session-id")
        print("1) initialize ->", r.status_code, "| session:", (sid or "（无）")[:24])
        body = parse_body(r)
        if body and "result" in body:
            info = body.get("result", {})
            print("   服务器:", json.dumps(info.get("serverInfo", {}), ensure_ascii=False))
            print("   协议版本:", info.get("protocolVersion"))
        else:
            print("   响应:", json.dumps(body, ensure_ascii=False)[:300] if body else "（无）")

        headers = dict(HEADERS_BASE)
        if sid:
            headers["Mcp-Session-Id"] = sid

        client.post(
            MCP_URL,
            headers=headers,
            json={"jsonrpc": "2.0", "method": "notifications/initialized"},
        )

        r = client.post(MCP_URL, headers=headers, json={"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        body = parse_body(r)
        tools = body.get("result", {}).get("tools", []) if body else []
        print(f"\n2) tools/list -> {len(tools)} 个工具:")
        for t in tools:
            print(f"   - {t['name']}: {t.get('description', '')[:70]}")

        r = client.post(
            MCP_URL,
            headers=headers,
            json={
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "search_docs_by_lang_chain",
                    "arguments": {"query": "how to create a tool"},
                },
            },
        )
        body = parse_body(r)
        if body and "result" in body:
            content = body["result"].get("content", [])
            text = content[0].get("text", "") if content else ""
            print(f"\n3) tools/call(search_docs_by_lang_chain) -> 返回 {len(text)} 字符，节选:")
            print("   " + text[:300].replace(chr(10), " / "))
        else:
            print("\n3) tools/call ->", json.dumps(body, ensure_ascii=False)[:300] if body else "（无响应体）")


def main_adapter():
    section("B. LangChain MCPAdapter 实测（需要 langchain[mcp]）")
    try:
        from langchain.mcp import MCPAdapter
    except ImportError as e:
        print("跳过：langchain[mcp] 未安装（", str(e)[:60], "）")
        print('需要时安装：uv add "langchain[mcp]"')
        return

    from langchain.agents import create_agent
    from langchain.chat_models import init_chat_model

    model = init_chat_model(
        "qwen3.8-flash",
        model_provider="openai",
        api_key=os.environ["BAILIAN_API_KEY"],
        base_url=os.environ["BAILIAN_BASE_URL"],
        max_retries=2,
        timeout=60,
    )

    async def run():
        async with MCPAdapter(MCP_URL) as adapter:
            tools = await adapter.list_tools()
            print(f"适配器把服务器工具转成了 {len(tools)} 个 LangChain 工具:")
            for t in tools:
                print(f"   - {t.name}")

            agent = create_agent(model, tools)
            res = await agent.ainvoke(
                {"messages": [{"role": "user", "content": "用一句话说明：在 LangChain 里给工具写描述的最佳实践是什么？"}]}
            )
            for m in reversed(res["messages"]):
                if getattr(m, "type", "") == "ai" and getattr(m, "content", ""):
                    print("agent（经 MCP 工具）回答:", str(m.content)[:200])
                    break

    asyncio.run(run())


def main_headless():
    section("C. headless 工具：当前版本支持现状")
    from langchain.tools import tool as make_tool

    result = make_tool("browser_zoom", description="调整浏览器缩放比例；仅在客户端执行。")
    print("tool('name', description=...) 返回:", type(result).__name__)

    try:
        r2 = make_tool(name="browser_zoom", description="x")
        print("tool(name=...) 返回:", type(r2).__name__)
    except Exception as e:
        print("tool(name=...) 报错:", type(e).__name__, "|", str(e)[:100])


if __name__ == "__main__":
    main_raw()
    main_adapter()
    main_headless()
