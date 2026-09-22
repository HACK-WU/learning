"""课 6 实操：真调 API，实测长上下文的真实代价。

诚实说明（2026-09-21）：
  1. lost in the middle 本实验【未复现】。v1(8段)/v2(20段同句式)/v3(跨文档计数)
     三轮全部满分。原因：这些任务都是"可精确定位"的，现代模型不受位置影响。
     该效应在【超长上下文 + 需要跨段落语义整合】时才显著，本课如实说明未能复现。
  2. 延迟测量必须先预热：首次请求含连接建立，不预热会得出"8条比32条慢"的错误结论。
"""
import os
import time

import dotenv

dotenv.load_dotenv()
from openai import OpenAI  # noqa: E402

c = OpenAI(api_key=os.getenv("BAILIAN_API_KEY"), base_url=os.getenv("BAILIAN_BASE_URL"))
MODEL = "qwen3.8-flash"


def filler(i):
    return (f"[条目{i + 1}] 常规记录 {i + 1}：本条目为日常运营流水，"
            f"涉及若干例行事务的处理与归档，不含任何需要特别关注的事项。")


def ask(prompt, max_tokens=20):
    r = c.chat.completions.create(
        model=MODEL, messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens, temperature=0,
    )
    return r.content if hasattr(r, "content") else r.choices[0].message.content


print("=== 0. 预热：先发一个无关请求，排除连接建立开销 ===")
ask("说：ok", max_tokens=5)
print("  预热完成")

print("\n=== A. 长上下文的真实代价：耗时与输入长度 ===")
print(f"  {'条目数':<8}{'输入字符':<10}{'首字耗时(秒)':<14}{'总耗时(秒)':<12}")
rows = []
for n in (8, 32, 128, 512):
    ctx = "\n".join(filler(i) for i in range(n))
    prompt = f"{ctx}\n\n问题：以上有多少条目？只回答数字。"
    t0 = time.time()
    stream = c.chat.completions.create(
        model=MODEL, messages=[{"role": "user", "content": prompt}],
        max_tokens=20, temperature=0, stream=True,
    )
    first = None
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            first = time.time() - t0
            break
    total = time.time() - t0
    rows.append((n, len(ctx), first, total))
    print(f"  {n:<8}{len(ctx):<10}{first:<14.2f}{total:<12.2f}")

print(f"\n  条目数 8 → 512（{512 // 8} 倍），首字耗时 {rows[0][2]:.2f}s → {rows[-1][2]:.2f}s"
      f"（{rows[-1][2] / rows[0][2]:.1f} 倍）")
print("  ↑ 输入越长，模型要「读完」才开始回答，首字延迟明显上升")
print("    且输入 token 每次请求都要付；多轮会话每轮重发，成本会累积")

print("\n=== B. 位置效应实测：三轮实验均未复现 ===")
N, FLAGS = 20, 3
print(f"  共 {N} 条，其中 {FLAGS} 条例外，改变例外条目所在位置")
print(f"  {'例外位置':<16}{'模型回答':<12}{'正确?':<8}")
for label, positions in [("集中在开头", [0, 1, 2]),
                         ("集中在中间", [9, 10, 11]),
                         ("分散在全程", [0, 10, 19])]:
    ctx = "\n".join(
        f"[条目{i + 1}] " + ("例外事项：本条目标记为需要特别关注。"
                            if i in positions else "常规记录：例行事务处理与归档，无特别事项。")
        for i in range(N)
    )
    out = ask(f"{ctx}\n\n问题：以上条目中，标记为例外的有多少条？只回答数字。").strip()
    print(f"  {label:<16}{out[:10]:<12}{'是' if str(FLAGS) in out else '否':<8}")
print("  ↑ 三种位置全部答对——本实验【未复现】lost in the middle")
print("    这不代表该效应不存在，而是说明：在可精确定位的任务上，")
print("    现代模型能稳定找到信息，位置不成为瓶颈")

print("\n=== C. 输入 vs 输出：谁更值得省 ===")
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    inp = "请总结这份报告的核心观点。"
    outp = ("本报告的核心观点是：第一，市场增速放缓，主要受宏观环境影响；"
            "第二，竞争格局趋于集中，头部厂商份额提升；第三，成本控制成为关键能力。")
    it, ot = len(enc.encode(inp)), len(enc.encode(outp))
    print(f"  输入：{len(inp)} 字 → {it} tokens")
    print(f"  输出：{len(outp)} 字 → {ot} tokens")
    print(f"  输出 / 输入 = {ot / it:.1f} 倍")
    print("  ↑ 输出单价通常高于输入，但输入【每轮都要重发】")
    print("    多轮会话下，输入才是累积的大头——详见实战 2《把 token 账单算明白》")
except ImportError:
    print("  （tiktoken 未安装，跳过）")
