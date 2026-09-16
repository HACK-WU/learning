"""知识库检索工具（课 11：Agentic RAG——把检索做成工具，由模型决定何时检索）。

懒加载 + 单例：首次调用构建向量库（真实调用嵌入接口），之后复用。
"""
from langchain.tools import tool

from app.kb.loader import build_vector_store

_store = None

# 检索条数（课 11 实测：k=3 兼顾覆盖与噪音控制）
TOP_K = 3


def _get_store():
    """懒加载向量库（避免导入时即调用嵌入接口——单元测试可保持离线）。"""
    global _store
    if _store is None:
        _store = build_vector_store()
    return _store


@tool
def search_policies(query: str) -> str:
    """检索星云商城的政策知识库（退换货 / 配送物流 / 会员积分 / 发票支付）。
    涉及政策、规则、时效、金额标准的问题都应先检索，严禁凭记忆编造政策。"""
    results = _get_store().similarity_search_with_score(query, k=TOP_K)
    if not results:
        return "知识库中未找到相关内容。"

    lines = []
    for i, (doc, score) in enumerate(results, start=1):
        source = doc.metadata.get("source", "未知来源")
        content = " ".join(doc.page_content.split())[:260]
        lines.append(f"[{i}] 来源《{source}》（相关度 {score:.3f}）：{content}")
    return "\n".join(lines)
