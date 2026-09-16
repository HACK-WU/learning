"""知识库构建（课 11：加载 → 切分 → 嵌入 → 内存向量库）。

切分参数 (chunk_size=300, chunk_overlap=60) 沿用课程实测方案：
- 切太小 → 语义不完整；切太大 → 检索噪音（课 11 三档对照结论）
- k=3 检索条数：既能覆盖答案块，又不会引入过多噪音（课 11 实测）
"""
from pathlib import Path

from langchain_core.documents import Document
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_text_splitters import RecursiveCharacterTextSplitter

from app.config import build_embeddings

# 知识库素材目录：实现/data/kb/
KB_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "kb"

CHUNK_SIZE = 300
CHUNK_OVERLAP = 60


def load_documents() -> list[Document]:
    """加载 data/kb/ 下的政策文档（课 11：加载环节）。"""
    docs: list[Document] = []
    for path in sorted(KB_DIR.glob("*.md")):
        text = path.read_text(encoding="utf-8")
        docs.append(Document(page_content=text, metadata={"source": path.name}))
    if not docs:
        raise FileNotFoundError(f"知识库目录为空：{KB_DIR}")
    return docs


def build_vector_store() -> InMemoryVectorStore:
    """构建内存向量库（课 11 全链路：切分 → 嵌入 → 入库）。

    注意：每次构建都会真实调用嵌入接口（首次约 1-3 秒），
    应用侧通过懒加载 + 单例复用（见 tools/knowledge.py）。
    """
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )
    chunks = splitter.split_documents(load_documents())

    store = InMemoryVectorStore(build_embeddings())
    store.add_documents(chunks)
    return store
