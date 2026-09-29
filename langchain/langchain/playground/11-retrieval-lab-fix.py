# -*- coding: utf-8 -*-
"""课 11 补跑：3f(b) 检索细节核查 + embed 稳定性对照 + k 值影响。"""
import os
import time
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


def show(q, k):
    print(f'\n查询: {q}（k={k}）')
    pairs = store.similarity_search_with_score(q, k=k)
    for d, s in pairs:
        first = d.page_content.splitlines()[0]
        hit = '  <== 含答案的块' if '阶梯计算' in d.page_content else ''
        print(f'  score={s:.4f} | [{d.metadata["source"]}] {first[:46]}{hit}')


print('=' * 64)
print('补跑 A：3f(b) 检索细节核查（top-5 看"年假"答案块排第几）')
print('=' * 64)
show('星云科技员工每年有多少天年假？', 5)
show('年假有多少天', 5)
show('员工年假天数 政策', 5)

print()
print('=' * 64)
print('补跑 B：k 值影响（k=3 与 k=5 的命中差异）')
print('=' * 64)
q = '星云科技员工每年有多少天年假？'
for k in (1, 2, 3, 4, 5):
    pairs = store.similarity_search_with_score(q, k=k)
    hit = any('阶梯计算' in d.page_content for d, _ in pairs)
    print(f'  k={k}: 含答案块命中={hit}')

print()
print('=' * 64)
print('补跑 C：embed 稳定性对照（同路径两次 vs 跨路径）')
print('=' * 64)
t0 = time.time()
q1 = emb.embed_query('年假有多少天')
q2 = emb.embed_query('年假有多少天')
d1 = emb.embed_documents(['年假有多少天'])[0]
d2 = emb.embed_documents(['年假有多少天'])[0]
t1 = time.time()


def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


print(f'  embed_query 两次（同路径）:         差值 = {diff(q1, q2):.6f}')
print(f'  embed_documents 两次（同路径）:     差值 = {diff(d1, d2):.6f}')
print(f'  embed_query vs embed_documents:     差值 = {diff(q1, d1):.6f}')
print(f'  （4 次调用耗时 {t1 - t0:.1f}s）')
