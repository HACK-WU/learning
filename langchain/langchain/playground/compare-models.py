"""第 2 课 · 实操：模型选型对比（同一份代码，跑两个平台）。

运行（在 playground 目录内）：

    uv run python compare-models.py

输出即讲义第四幕引用的实测证据：两平台的并发耗时与 token 账单对比。
"""

import os
import time

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model
from langchain_core.callbacks import get_usage_metadata_callback

load_dotenv()

QUESTIONS = [
    "用一句话介绍杭州。",
    "用一句话解释什么是缓存。",
    "用一句话解释什么是索引。",
]

PLATFORMS = {
    "阿里云百炼 / qwen3.8-flash": dict(
        model="qwen3.8-flash",
        api_key=os.environ["BAILIAN_API_KEY"],
        base_url=os.environ["BAILIAN_BASE_URL"],
    ),
    "DeepSeek / deepseek-flash": dict(
        model="deepseek-flash",
        api_key=os.environ["DEEPSEEK_API_KEY"],
        base_url=os.environ["DEEPSEEK_BASE_URL"],
    ),
}

for name, cfg in PLATFORMS.items():
    model = init_chat_model(model_provider="openai", **cfg)
    with get_usage_metadata_callback() as cb:
        t0 = time.time()
        results = model.batch(QUESTIONS)
        elapsed = time.time() - t0
    print(f"\n===== {name} =====")
    print(f"3 条并发耗时: {elapsed:.2f}s")
    for q, r in zip(QUESTIONS, results):
        print(f"  Q: {q}")
        print(f"  A: {r.content.strip()[:80]}")
    print(f"token 账单: {cb.usage_metadata}")
