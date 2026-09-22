"""课 7 实操：真调 API，实测六条固有缺陷。

每条缺陷都用一个最小实验直接暴露，不靠讲道理。
"""
import os

import dotenv

dotenv.load_dotenv()
from openai import OpenAI  # noqa: E402

c = OpenAI(api_key=os.getenv("BAILIAN_API_KEY"), base_url=os.getenv("BAILIAN_BASE_URL"))
MODEL = "qwen3.8-flash"


def ask(prompt, max_tokens=120, temperature=0.7):
    r = c.chat.completions.create(
        model=MODEL, messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens, temperature=temperature,
    )
    return (r.content if hasattr(r, "content") else r.choices[0].message.content).strip()


print("=== 缺陷 1：幻觉——自信地编造不存在的事 ===")
print("  问一个【完全虚构】的实体，看它是说不知道，还是编一个")
q1 = "请介绍一下《云枢数据治理白皮书（2024版）》的核心观点。"
print(f"  问题：{q1}")
for i in range(2):
    print(f"  第{i + 1}次：{ask(q1)[:150]}")
print("  ↑ 这本书不存在。注意它的语气——是否承认不知道？")

print("\n=== 缺陷 2：无状态——它不记得刚才说过什么 ===")
print("  第一轮：告诉它一个事实")
r1 = c.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "我叫陈默，在云枢科技的算法组工作。记住这个。"}],
    max_tokens=50, temperature=0,
)
print(f"    模型：{(r1.content if hasattr(r1, 'content') else r1.choices[0].message.content)[:60]}")
print("  第二轮：【全新请求】，不带任何上文，问它我是谁")
r2 = ask("我是谁？在哪个组工作？", max_tokens=50)
print(f"    模型：{r2[:80]}")
print("  ↑ 每次 API 调用都是独立的——不带历史，它就什么都不知道")

print("\n=== 缺陷 3：无工具——不会算数、不会查实时信息 ===")
for label, q in [
    ("大数乘法", "8934567 × 2345678 = ? 直接给出结果。"),
    ("实时信息", "今天杭州的天气怎么样？"),
]:
    print(f"  {label}：{q}")
    print(f"    模型：{ask(q, max_tokens=100)[:130]}")

print("\n=== 缺陷 4：知识截止——不知道训练数据之后的事 ===")
q4 = "2026年9月22日的新闻头条是什么？"
print(f"  问题：{q4}")
print(f"  模型：{ask(q4, max_tokens=100)[:130]}")
print("  ↑ 注意它是否会编造新闻")

print("\n=== 缺陷 5：无 grounding——不知道你公司的私域 ===")
q5 = "云枢科技的年假政策是怎样的？（提示：这是虚构公司，你不可能知道）"
print(f"  问题：{q5}")
print(f"  模型：{ask(q5, max_tokens=120)[:150]}")
print("  ↑ 它没见过这份文档，但会给出一套'看起来合理'的政策")

print("\n=== 缺陷 6：不可靠——同一个问题，两次给出冲突答案 ===")
q6 = "《云枢数据治理白皮书（2024版）》是哪一年发布的？只回答年份。"
outs = [ask(q6, max_tokens=20, temperature=1.0) for _ in range(4)]
print(f"  问题：{q6}")
for i, o in enumerate(outs, 1):
    print(f"    第{i}次：{o[:30]}")
print(f"  → 得到 {len(set(outs))} 种不同答案（针对一本不存在的书）")
