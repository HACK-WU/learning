"""LangChain 课程 · 接入自检脚本。

验证 LangChain 能否通过本课程的两条 API 链路调用模型：
  1. 阿里云百炼（课程默认，成本更低）—— qwen3.8-flash / deepseek-v4.1-flash
  2. DeepSeek（备用）—— deepseek-flash

运行（在 playground 目录内）：

    uv run python check_connection.py

凭据读取自同目录 .env（不入库；模板见 .env.example）。
"""

import os
import traceback

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model

load_dotenv()

CASES = [
    ("阿里云百炼 / qwen3.8-flash", "qwen3.8-flash", "BAILIAN_API_KEY", "BAILIAN_BASE_URL"),
    ("阿里云百炼 / deepseek-v4.1-flash", "deepseek-v4.1-flash", "BAILIAN_API_KEY", "BAILIAN_BASE_URL"),
    ("DeepSeek / deepseek-flash", "deepseek-flash", "DEEPSEEK_API_KEY", "DEEPSEEK_BASE_URL"),
]


def main() -> None:
    ok = 0
    for name, model_name, key_env, url_env in CASES:
        print(f"\n--- {name} ---")
        try:
            model = init_chat_model(
                model_name,
                model_provider="openai",
                api_key=os.environ[key_env],
                base_url=os.environ[url_env],
            )
            reply = model.invoke("请只回复六个字：链路连接成功")
            print("[OK]", str(reply.content)[:200])
            ok += 1
        except Exception:
            print("[FAIL]")
            traceback.print_exc()
    print(f"\n===== 结果：{ok}/{len(CASES)} 通过 =====")


if __name__ == "__main__":
    main()
