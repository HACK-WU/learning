"""第 2 课 · 接入报错实验：三类最常见的接入错误，采集真实异常类型与消息。

运行（在 playground 目录内）：

    uv run python lesson-02-errors-lab.py

说明：本脚本故意使用错误的配置（假 key / 错模型名 / 错域名），演示报错形态；
脚本已把真实密钥替换为占位符，可安全分享输出。
为控制演示时长，此处设置 max_retries=1（默认值为 6，重试会成倍拉长等待）。
"""

import os

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model

load_dotenv()

REAL_KEY = os.environ["BAILIAN_API_KEY"]
REAL_URL = os.environ["BAILIAN_BASE_URL"]

CASES = [
    (
        "认证失败（无效 API key）",
        {"api_key": "sk-invalid-key-for-demo", "base_url": REAL_URL, "model": "qwen3.8-flash"},
    ),
    (
        "模型不存在（错误模型名）",
        {"api_key": REAL_KEY, "base_url": REAL_URL, "model": "no-such-model-xyz"},
    ),
    (
        "端点不可达（不存在的域名）",
        {"api_key": REAL_KEY, "base_url": "https://no-such-host.example.com/v1", "model": "qwen3.8-flash"},
    ),
]

for name, cfg in CASES:
    print(f"\n--- {name} ---")
    try:
        model = init_chat_model(model_provider="openai", max_retries=1, timeout=15, **cfg)
        model.invoke("你好")
        print("（未报错，意外情况）")
    except Exception as e:
        print(f"异常类型: {type(e).__name__}")
        msg = str(e).replace(REAL_KEY, "<YOUR_API_KEY>")
        print(f"消息摘要: {msg[:280]}")
        print(f"is_retryable: {getattr(e, 'is_retryable', '（无此属性）')}")
