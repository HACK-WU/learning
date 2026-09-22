"""课 5 实操：真调 API，实测采样带来的非确定性。

关键发现（2026-09-21 实测于阿里云百炼 qwen3.8-flash）：
  temperature=0 + seed=42 依然不能保证复现。
"""
import os

import dotenv

dotenv.load_dotenv()
from openai import OpenAI  # noqa: E402

c = OpenAI(api_key=os.getenv("BAILIAN_API_KEY"), base_url=os.getenv("BAILIAN_BASE_URL"))
MODEL = "qwen3.8-flash"
Q = "用一句话说明什么是采样"


def ask(temp, seed=None, n=3, max_tokens=40):
    outs = []
    for _ in range(n):
        kw = dict(model=MODEL, messages=[{"role": "user", "content": Q}],
                  max_tokens=max_tokens, temperature=temp)
        if seed is not None:
            kw["seed"] = seed
        r = c.chat.completions.create(**kw)
        outs.append(r.content if hasattr(r, "content") else r.choices[0].message.content)
    return outs


print("=== 1. 同一个问题问 3 次（temperature=0.9）===")
outs = ask(0.9)
for i, o in enumerate(outs, 1):
    print(f"  第{i}次：{o}")
print(f"  → 三次完全一致？{len(set(outs)) == 1}")

print("\n=== 2. temperature=0 + 固定 seed=42，能复现吗？ ===")
o0 = ask(0.0, seed=42)
for i, o in enumerate(o0, 1):
    print(f"  第{i}次：{o}")
print(f"  → 三次完全一致？{len(set(o0)) == 1}")
print("  ↑ 这就是本课的关键：即使 temperature=0 且固定 seed，也【不保证】复现")

print("\n=== 3. temperature 对分布的影响（用输出差异度定性观察）===")
for t in (0.0, 0.5, 1.0):
    os_ = ask(t, seed=42, n=4, max_tokens=30)
    uniq = len(set(os_))
    print(f"  temperature={t}: 4 次调用得到 {uniq} 种不同输出")

print("\n=== 4. 为什么不能只靠 seed：换一个提示词再看 ===")
Q2 = "1+1等于几？只回答数字"
outs2 = []
for _ in range(3):
    r = c.chat.completions.create(model=MODEL, messages=[{"role": "user", "content": Q2}],
                                  max_tokens=10, temperature=0, seed=42)
    outs2.append(r.content if hasattr(r, "content") else r.choices[0].message.content)
print(f"  极简单问题 3 次输出：{outs2}")
print(f"  → 完全一致？{len(set(outs2)) == 1}")
print("  ↑ 越简单、熵越低的问题，越容易稳定；越开放的问题越难复现")
