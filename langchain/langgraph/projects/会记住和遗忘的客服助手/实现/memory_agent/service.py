"""服务层：对外只暴露四个动作。

知识点回指：
- 阶段 2 · 课 7「流模式」——stream_mode="updates" 给前端/SSE
- 阶段 3 · 课 8「审批流落地」——submit 后可能卡住，approve 续跑
- 阶段 3 · 课 9「历史回放」——history() 看这一轮走过哪些存档点

为什么要有服务层：
- 调用方不该关心 config 怎么拼、thread_id 怎么传
- interrupt 的"卡住 / 续跑"语义在这里收口，调用方只见 pend/approve
"""
from typing import Any, Iterator

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.base import BaseStore
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

from .graph import build_graph
from .state import empty_state


class MemoryService:
    """客服助手服务：一个用户一个 thread，跨 thread 共享 Store。"""

    def __init__(self, *, store: BaseStore | None = None, checkpointer=None):
        # Store 是跨会话共享的"柜子"——整个服务进程一份
        self.store = store if store is not None else InMemoryStore()
        self.checkpointer = checkpointer if checkpointer is not None else InMemorySaver()
        self.graph = build_graph(checkpointer=self.checkpointer, store=self.store)

    def _cfg(self, thread_id: str) -> dict[str, Any]:
        return {"configurable": {"thread_id": thread_id}}

    def chat(self, user_id: str, message: str, thread_id: str | None = None) -> dict[str, Any]:
        """发起一轮对话。返回 {"status": ..., ...}。

        status:
          - "done"   本轮走完（没有需要确认的）
          - "pend"   卡在人工确认，等 approve()
        """
        tid = thread_id or f"{user_id}-{message[:8]}"
        result = self.graph.invoke(
            empty_state(user_id, message), self._cfg(tid)
        )
        if result.get("__interrupt__"):
            return {
                "status": "pend",
                "thread_id": tid,
                "question": result["__interrupt__"][0].value,
            }
        return {
            "status": "done",
            "thread_id": tid,
            "reply": result.get("reply", ""),
            "trace": result.get("trace", []),
        }

    def approve(
        self, thread_id: str, decision: str = "confirm"
    ) -> dict[str, Any]:
        """人工裁决后续跑。

        decision: confirm=照写 / reject=丢弃 / keep=保留旧值
        """
        result = self.graph.invoke(Command(resume=decision), self._cfg(thread_id))
        if result.get("__interrupt__"):
            return {"status": "pend", "question": result["__interrupt__"][0].value}
        return {
            "status": "done",
            "reply": result.get("reply", ""),
            "trace": result.get("trace", []),
        }

    def stream(self, user_id: str, message: str, thread_id: str | None = None) -> Iterator[Any]:
        """流式输出（updates 模式）——每行一个节点的增量。"""
        tid = thread_id or f"{user_id}-{message[:8]}"
        yield from self.graph.stream(
            empty_state(user_id, message),
            self._cfg(tid),
            stream_mode="updates",
        )

    def history(self, thread_id: str) -> list[dict[str, Any]]:
        """这一轮走过的存档点（回放用）。"""
        out = []
        for st in self.graph.get_state_history(self._cfg(thread_id)):
            out.append(
                {
                    "step": len(st.values.get("trace", [])),
                    "next": list(st.next),
                    "trace": st.values.get("trace", []),
                }
            )
        return out

    def profile(self, user_id: str) -> dict[str, Any]:
        """直接看某个用户的档案（跨会话的长期记忆）。"""
        from .store import MemStore

        return MemStore(self.store).get_profile(user_id)
