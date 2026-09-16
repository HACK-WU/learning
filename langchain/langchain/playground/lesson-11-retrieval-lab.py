"""课 11 正式实验脚本：Retrieval 检索与 RAG 全链路实测。

设计 3 大板块（对应 3 个知识点）：
1. 为什么需要检索：私有知识直问（无检索）的两种失败模式——诚实猜测与幻觉编造
2. 知识库构建链路：加载 → 切分（三档对照）→ 块结构 → 嵌入（维度/批量/截维）→ 入库
3. 检索器与 RAG 架构：三种查询方式 / Retriever 三形态 / @chain 自定义 /
   2-step RAG / Agentic RAG / 三方对照 / 跨文档复合问题

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0
- 对话模型：百炼 qwen3.8-flash（BAILIAN_*）
- 嵌入模型：SiliconFlow Qwen/Qwen3-Embedding-8B（SILICONFLOW_*，4096 维）
知识库语料：playground/kb/ 下 5 份「星云科技」虚构公司文档（Markdown）
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import os
import time
from pathlib import Path
from typing import List

from dotenv import load_dotenv

load_dotenv()

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langchain_core.documents import Document
from langchain_core.runnables import chain
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

KB_DIR = Path(__file__).parent / "kb"
EMBED_DIMS = int(os.environ.get("SILICONFLOW_EMBEDDING_DIMS", "4096"))

model = init_chat_model(
    "qwen3.8-flash", model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
    max_retries=2, timeout=60,
)

embeddings = OpenAIEmbeddings(
    model=os.environ["SILICONFLOW_EMBEDDING_MODEL"],
    api_key=os.environ["SILICONFLOW_API_KEY"],
    base_url=os.environ["SILICONFLOW_BASE_URL"],
    check_embedding_ctx_length=False,
)


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 300) -> str:
    text = str(content) if content is not None else ""
    return " ".join(text.split())[:limit]


def exp(label: str, fn) -> None:
    print(f"\n-- {label} --", flush=True)
    t0 = time.time()
    try:
        fn()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [本项耗时 {time.time() - t0:.1f}s]", flush=True)


def show_chain(msgs, limit: int = 80) -> None:
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            for tc in m.tool_calls:
                print(f"    [{i}] ai -> 调用工具 {tc['name']}({brief(tc['args'], 90)})", flush=True)
        elif t == "tool":
            print(f"    [{i}] tool 返回: {brief(m.content, limit)}", flush=True)
        elif t == "ai" and m.content:
            print(f"    [{i}] ai 最终回答: {brief(m.content, 600)}", flush=True)
        else:
            print(f"    [{i}] {t}: {brief(m.content, 70)}", flush=True)


# ============================================================
# 站一：为什么需要检索——无检索直问的两种失败模式
# ============================================================

PRIVATE_QS = [
    "星云科技（Nebula Tech）的员工年假有多少天？",
    "星云科技的 VPN 客户端叫什么？",
]


def exp_1a():
    for i, q in enumerate(PRIVATE_QS, 1):
        print(f"  [问题 {i}] {q}", flush=True)
        r = model.invoke(q)
        print(f"  [回答 {i}] {brief(r.content, 700)}", flush=True)
        print(flush=True)


# ============================================================
# 站二：知识库构建链路——加载 → 切分 → 嵌入 → 入库
# ============================================================

def load_kb_documents() -> List[Document]:
    """加载：Markdown → Document（对应官方 knowledge-base 教程 Create documents 模式）"""
    return [
        Document(page_content=p.read_text(encoding="utf-8"), metadata={"source": p.name})
        for p in sorted(KB_DIR.glob("*.md"))
    ]


def build_chunks() -> List[Document]:
    sp = RecursiveCharacterTextSplitter(
        chunk_size=300, chunk_overlap=60, add_start_index=True
    )
    return sp.split_documents(load_kb_documents())


def exp_2a():
    docs = load_kb_documents()
    print(f"  文件数: {len(docs)}", flush=True)
    for d in docs:
        print(f"    {d.metadata['source']}: {len(d.page_content)} 字符", flush=True)
    d0 = docs[0]
    print(f"  Document 字段: page_content={type(d0.page_content).__name__} / "
          f"metadata={type(d0.metadata).__name__} / id={d0.id!r}", flush=True)


def exp_2b():
    docs = load_kb_documents()
    for size, overlap in [(200, 40), (300, 60), (400, 80)]:
        sp = RecursiveCharacterTextSplitter(chunk_size=size, chunk_overlap=overlap)
        chunks = sp.split_documents(docs)
        lens = [len(c.page_content) for c in chunks]
        print(f"  chunk_size={size:4d} overlap={overlap:3d} -> {len(chunks):3d} 块 | "
              f"长度 min={min(lens)} max={max(lens)} avg={sum(lens) // len(lens)}", flush=True)
    print(f"  默认分隔符: {RecursiveCharacterTextSplitter(chunk_size=300)._separators}", flush=True)


def exp_2c():
    chunks = build_chunks()
    print(f"  共 {len(chunks)} 块；取第 2 块展示：", flush=True)
    c = chunks[1]
    print(f"  metadata: {c.metadata}", flush=True)
    print(f"  内容（{len(c.page_content)} 字符）：", flush=True)
    for line in c.page_content.splitlines()[:8]:
        print(f"    | {line}", flush=True)


def exp_2d():
    sample = [
        "年假天数按员工服务年限阶梯计算",
        "VPN 客户端为 NebulaConnect，账号为员工工号",
        "报销需在费用发生后 30 个自然日内提交",
    ]
    t0 = time.time()
    vecs = embeddings.embed_documents(sample)
    t1 = time.time()
    print(f"  embed_documents 批量 {len(sample)} 条: 每条 {len(vecs[0])} 维 | "
          f"耗时 {t1 - t0:.1f}s（平均 {(t1 - t0) / len(sample):.2f}s/条）", flush=True)
    qv = embeddings.embed_query("年假有多少天")
    head3 = [round(x, 5) for x in qv[:3]]
    print(f"  embed_query: {len(qv)} 维 | 前 3 位: {head3}", flush=True)
    same = embeddings.embed_documents(["年假有多少天"])[0]
    diff = sum(abs(a - b) for a, b in zip(qv, same))
    print(f"  embed_query 与 embed_documents 对同一文本: 向量差绝对值之和={diff:.6f}"
          f"（0 表示同一空间同一条路径）", flush=True)
    emb2 = OpenAIEmbeddings(
        model=os.environ["SILICONFLOW_EMBEDDING_MODEL"],
        api_key=os.environ["SILICONFLOW_API_KEY"],
        base_url=os.environ["SILICONFLOW_BASE_URL"],
        check_embedding_ctx_length=False,
        dimensions=1024,
    )
    v2 = emb2.embed_query("年假有多少天")
    print(f"  dimensions=1024 截维（MRL）: 实际返回 {len(v2)} 维", flush=True)


def exp_2e():
    chunks = build_chunks()
    store = InMemoryVectorStore(embeddings)
    t0 = time.time()
    ids = store.add_documents(chunks)
    t1 = time.time()
    print(f"  add_documents: {len(ids)} 块入库 | 耗时 {t1 - t0:.1f}s"
          f"（平均 {(t1 - t0) / len(ids):.2f}s/块）", flush=True)
    print(f"  返回 id 前 2 个: {ids[0][:18]}... / {ids[1][:18]}...", flush=True)
    print(f"  store 内块数: {len(store.store)}", flush=True)


# ---- 站三共用：全局 store（构建一次） ----
STORE = None
CHUNKS: List[Document] = []


def prepare_store() -> InMemoryVectorStore:
    global STORE, CHUNKS
    if STORE is None:
        CHUNKS = build_chunks()
        STORE = InMemoryVectorStore(embeddings)
        STORE.add_documents(CHUNKS)
        print(f"  [store 就绪：{len(CHUNKS)} 块]", flush=True)
    return STORE


# ============================================================
# 站三：检索器与 RAG 架构
# ============================================================

def exp_3a():
    store = prepare_store()
    q = "年假有多少天"
    print(f"  查询: {q}", flush=True)
    r1 = store.similarity_search(q, k=3)
    print(f"  [similarity_search] 返回 {len(r1)} 条:", flush=True)
    for d in r1:
        print(f"    [{d.metadata['source']}] {brief(d.page_content.splitlines()[0], 44)}", flush=True)
    print(flush=True)
    r2 = store.similarity_search_with_score(q, k=3)
    print(f"  [similarity_search_with_score] 分数方向验证:", flush=True)
    for d, s in r2:
        print(f"    score={s:.4f} | [{d.metadata['source']}] "
              f"{brief(d.page_content.splitlines()[0], 40)}", flush=True)
    selfres = store.similarity_search_with_score("年假天数按员工在公司的连续服务年限阶梯计算", k=1)
    oddres = store.similarity_search_with_score("今天天气怎么样", k=1)
    s_self, s_odd = selfres[0][1], oddres[0][1]
    print(f"  对照: 原文查询 score={s_self:.4f} vs 无关查询 score={s_odd:.4f}", flush=True)
    print(f"  -> 结论: score 为余弦相似度（越大越相似）", flush=True)
    print(flush=True)
    qv = embeddings.embed_query(q)
    r3 = store.similarity_search_by_vector(qv, k=2)
    print(f"  [similarity_search_by_vector] 用 {len(qv)} 维查询向量 -> {len(r3)} 条:", flush=True)
    for d in r3:
        print(f"    [{d.metadata['source']}] {brief(d.page_content.splitlines()[0], 40)}", flush=True)


def exp_3b():
    store = prepare_store()
    q = "远程办公"
    print(f"  查询: {q}", flush=True)
    for st, kw in [("similarity", {"k": 3}), ("mmr", {"k": 3, "fetch_k": 10, "lambda_mult": 0.5})]:
        r = store.as_retriever(search_type=st, search_kwargs=kw).invoke(q)
        print(f"  [as_retriever · {st}] 返回 {len(r)} 条:", flush=True)
        for d in r:
            print(f"    [{d.metadata['source']}] {brief(d.page_content.splitlines()[0], 42)}", flush=True)
    print(flush=True)
    try:
        r = store.as_retriever(
            search_type="similarity_score_threshold", search_kwargs={"score_threshold": 0.45}
        ).invoke(q)
        print(f"  [similarity_score_threshold] 返回 {len(r)} 条", flush=True)
    except NotImplementedError:
        print("  [similarity_score_threshold] NotImplementedError"
              "（InMemoryVectorStore 未实现 relevance scores 方法）", flush=True)
    pairs = store.similarity_search_with_score(q, k=15)
    kept = [(d, s) for d, s in pairs if s >= 0.45]
    print(f"  替代方案（手动阈值过滤）: 15 条中保留 {len(kept)} 条 ->", flush=True)
    for d, s in kept[:3]:
        print(f"    score={s:.4f} | [{d.metadata['source']}] "
              f"{brief(d.page_content.splitlines()[0], 40)}", flush=True)


def exp_3c():
    store = prepare_store()

    @chain
    def retriever(query: str) -> List[Document]:
        return store.similarity_search(query, k=2)

    res = retriever.batch(["年假", "VPN 密码"])
    print(f"  @chain 自定义 retriever | batch 返回 {len(res)} 组:", flush=True)
    for group in res:
        print(f"    组内 {len(group)} 条 | 首条: "
              f"[{group[0].metadata['source']}] {brief(group[0].page_content.splitlines()[0], 40)}",
              flush=True)


PROMPT_TEMPLATE = """你是星云科技的企业助手。请根据以下内部资料回答问题。

<资料>
{context}
</资料>

要求：
1. 只依据资料作答，并注明来源文件名；
2. 资料中没有的信息，如实说明「资料未涵盖」，不要编造。

问题：{question}"""


def exp_3d():
    store = prepare_store()
    q = "星云科技的 VPN 客户端叫什么？怎么重置密码？"
    hits = store.similarity_search(q, k=3)
    context = "\n\n---\n\n".join(
        f"[来源: {d.metadata['source']}]\n{d.page_content}" for d in hits)
    prompt = PROMPT_TEMPLATE.format(context=context, question=q)
    srcs = [d.metadata['source'] for d in hits]
    print(f"  检索到 {len(hits)} 块: {srcs}", flush=True)
    print(f"  拼接后 prompt 总长: {len(prompt)} 字符（资料 {len(context)}）", flush=True)
    r = model.invoke(prompt)
    print(f"  回答: {brief(r.content, 600)}", flush=True)


def make_rag_agent():
    store = prepare_store()

    @tool
    def search_knowledge_base(query: str) -> str:
        """搜索星云科技公司内部知识库。当用户询问公司制度、流程、IT 服务、报销、产品政策等公司相关问题时必须使用此工具。"""
        hits = store.similarity_search(query, k=3)
        return "\n\n---\n\n".join(
            f"[来源: {h.metadata['source']}]\n{h.page_content}" for h in hits)

    return create_agent(
        model,
        tools=[search_knowledge_base],
        system_prompt="你是星云科技的企业助手。回答公司相关问题时，必须先调用 search_knowledge_base "
                      "检索内部知识库，基于资料作答并注明来源；资料中没有的内容如实说明，不要编造。",
    )


def exp_3e():
    agent = make_rag_agent()
    q = "星云科技的 VPN 客户端叫什么？怎么重置密码？"
    print(f"  问题: {q}", flush=True)
    r = agent.invoke({"messages": [{"role": "user", "content": q}]})
    show_chain(r["messages"])


def exp_3f():
    store = prepare_store()
    q = "星云科技员工每年有多少天年假？"
    print(f"  [(a) 无检索] 问: {q}", flush=True)
    ra = model.invoke(q)
    print(f"    -> {brief(ra.content, 400)}", flush=True)
    print(flush=True)
    print(f"  [(b) 2-step RAG] 问: {q}", flush=True)
    hits = store.similarity_search(q, k=3)
    context = "\n\n---\n\n".join(f"[来源: {d.metadata['source']}]\n{d.page_content}" for d in hits)
    rb = model.invoke(PROMPT_TEMPLATE.format(context=context, question=q))
    srcs = [d.metadata['source'] for d in hits]
    print(f"    检索: {srcs}", flush=True)
    print(f"    -> {brief(rb.content, 400)}", flush=True)
    print(flush=True)
    print(f"  [(c) Agentic RAG] 问: {q}", flush=True)
    agent = make_rag_agent()
    rc = agent.invoke({"messages": [{"role": "user", "content": q}]})
    show_chain(rc["messages"])


def exp_3g():
    agent = make_rag_agent()
    q = ("我下周要去北京出差，想顺便提前休 2 天年假：年假申请要提前几个工作日提交？"
         "出差住北京一晚最多能报销多少？")
    print(f"  复合问题: {q}", flush=True)
    r = agent.invoke({"messages": [{"role": "user", "content": q}]})
    show_chain(r["messages"])


# ============================================================
# 主流程
# ============================================================

if __name__ == "__main__":
    print("课 11《Retrieval 检索与 RAG》· 全流程实测")
    print(f"环境: Python {os.sys.version.split()[0]} | 对话模型 qwen3.8-flash | "
          f"嵌入模型 {os.environ['SILICONFLOW_EMBEDDING_MODEL']}（{EMBED_DIMS} 维）")
    print(f"知识库: {KB_DIR}")

    section("站一 · 1a 无检索直问私有知识")
    exp("1a 无检索直问（两种失败模式）", exp_1a)

    section("站二 · 知识库构建链路")
    exp("2a 加载：文件 → Document", exp_2a)
    exp("2b 切分：三档 chunk_size 对照", exp_2b)
    exp("2c 切分：块结构与 metadata", exp_2c)
    exp("2d 嵌入：维度 / 批量 / 截维", exp_2d)
    exp("2e 入库：add_documents", exp_2e)

    section("站三 · 检索器与 RAG 架构")
    exp("3a 查询三法", exp_3a)
    exp("3b Retriever 三形态", exp_3b)
    exp("3c @chain 自定义 retriever + batch", exp_3c)
    exp("3d 2-step RAG 全链路", exp_3d)
    exp("3e Agentic RAG（检索做工具）", exp_3e)
    exp("3f 三方对照（无检索 / 2-step / agentic）", exp_3f)
    exp("3g 跨文档复合问题", exp_3g)

    print("\n全部实验执行完毕。", flush=True)
