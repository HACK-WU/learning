# -*- coding: utf-8 -*-
"""课 11 微补跑：3f(b) 检索截断精确定位 + embed 非确定性三次验证。"""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

KB_DIR = Path(r'D:/projects/learning/langchain/langchain/playground/kb')

from langchain_core.documents import Document
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

emb = OpenAIEmbeddings(
    model=os.environ['SILICONFLOW_EMBEDDING_MODEL'],
    api_key=os.environ['SILICONFLOW_API_KEY'],
    base_url=os.environ['SILICONFLOW_BASE_URL'],
    check_embedding_ctx_length=False,
)

docs = [Document(page_content=p.read_text(encoding='utf-8'), metadata={'source': p.name})
        for p in sorted(KB_DIR.glob('*.md'))]
sp = RecursiveCharacterTextSplitter(chunk_size=300, chunk_overlap=60, add_start_index=True)
chunks = sp.split_documents(docs)
store = InMemoryVectorStore(emb)
store.add_documents(chunks)
print(f'知识库: {len(chunks)} 块')

print()
print('=' * 64)
print('微补跑 D1：3f(b) 精确复现（答案块 = 含「每年 5 天」的块）')
print('=' * 64)
q = '星云科技员工每年有多少天年假？'
for k in (3, 5):
    pairs = store.similarity_search_with_score(q, k=k)
    print(f'\n查询: {q}（k={k}）')
    for d, s in pairs:
        has_ans = '每年 5 天' in d.page_content
        si = d.metadata.get('start_index')
        first = d.page_content.splitlines()[0]
        print(f'  score={s:.4f} start={si:>4} 答案块={"★是" if has_ans else "否"} | {first[:42]}')

print()
print('=' * 64)
print('微补跑 D2：embed_query 三次重跑（非确定性验证）')
print('=' * 64)


def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


v1 = emb.embed_query('年假有多少天')
v2 = emb.embed_query('年假有多少天')
v3 = emb.embed_query('年假有多少天')
print(f'  第1次 vs 第2次: {diff(v1, v2):.6f}')
print(f'  第2次 vs 第3次: {diff(v2, v3):.6f}')
print(f'  第1次 vs 第3次: {diff(v1, v3):.6f}')
d1 = emb.embed_documents(['年假有多少天'])[0]
print(f'  embed_documents vs 第3次 embed_query: {diff(d1, v3):.6f}')
