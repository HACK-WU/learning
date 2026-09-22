"""课 8 实操：真调 API，实测三条路的效果差异。

本课不真微调（成本过高），但能真测：
  A. 无 RAG：问私域知识 -> 拒答或编造（课 7 已证）
  B. 有 RAG：把文档塞进上下文 -> 答对
  C. Prompt：改输入不改模型 -> 格式/风格受控
对比三者的成本与效果。
"""
import os

import dotenv

dotenv.load_dotenv()
from openai import OpenAI  # noqa: E402

c = OpenAI(api_key=os.getenv("BAILIAN_API_KEY"), base_url=os.getenv("BAILIAN_BASE_URL"))
MODEL = "qwen3.8-flash"

# 私域文档：模型【不可能】在训练数据里见过
PRIVATE_DOC = """
《云枢科技内部研发规范 v3.2》
第 12 条 代码评审：所有合并请求必须至少 2 名 Reviewer 批准，其中至少 1 名为该模块 Owner。
第 13 条 发布窗口：生产环境发布仅限每周二、周四 14:00-16:00，节假日前后三天禁止发布。
第 14 条 故障响应：P0 故障须在 15 分钟内响应，2 小时内给出止损方案。
第 15 条 年假计算：年假天数 = 司龄年数 + 5，上限 15 天，当年未休年假可顺延至次年 3 月 31 日。
"""

Q = "云枢科技的生产环境发布窗口是什么时间？"
QF = "一名司龄 6 年的员工，年假有多少天？"


def ask(prompt, max_tokens=120, temperature=0):
    r = c.chat.completions.create(
        model=MODEL, messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens, temperature=temperature,
    )
    return (r.content if hasattr(r, "content") else r.choices[0].message.content).strip()


print("=== A. 无 RAG：直接问私域知识 ===")
print(f"  问题：{Q}")
print(f"  回答：{ask(Q)[:160]}")
print("  ↑ 模型没见过这份内部规范")

print("\n=== B. 有 RAG：把文档放进上下文再问 ===")
rag_prompt = f"请仅根据以下文档回答问题，不要使用文档外的信息。\n\n{PRIVATE_DOC}\n\n问题：{Q}"
print(f"  回答：{ask(rag_prompt)[:160]}")
print("  ↑ 同一模型、同一问题，只因上下文多了文档 → 答对")

print("\n=== C. RAG 还能做计算型私域问题 ===")
rag2 = f"请仅根据以下文档回答，并说明计算过程。\n\n{PRIVATE_DOC}\n\n问题：{QF}"
print(f"  问题：{QF}")
print(f"  回答：{ask(rag2)[:200]}")
print("  ↑ 正确答案是 6+5=11 天")

print("\n=== D. Prompt 路：不改模型，只改输入格式 ===")
print("  同一个问题，三种 prompt，看输出格式差异")
base = "解释一下什么是向量数据库。"
for label, p in [
    ("裸问题", base),
    ("加角色", f"你是一名面向初学者的技术讲师。{base}"),
    ("加格式约束", f"{base}请严格按以下格式输出：\n一句话定义：\n一个类比：\n一个局限："),
]:
    out = ask(p, max_tokens=150)
    print(f"\n  --- {label} ---")
    print(f"  {out[:170]}")

print("\n=== E. 三条路成本对比：同一问答的 token 数 ===")
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    rows = [
        ("A 无 RAG（只有问题）", Q),
        ("B 有 RAG（文档+问题）", rag_prompt),
        ("D 加角色 prompt", f"你是一名面向初学者的技术讲师。{base}"),
    ]
    for label, s in rows:
        print(f"  {label:<24}{len(enc.encode(s)):>5} tokens")
    r_ = len(enc.encode(rag_prompt)) - len(enc.encode(Q))
    print(f"  → RAG 让本次输入多了 {r_} tokens，但换来了正确率")
    print("     这是【每次请求都要付】的成本")
except ImportError:
    print("  （tiktoken 未安装，跳过）")
