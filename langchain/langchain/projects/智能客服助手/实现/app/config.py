"""集中配置：环境变量加载 + 模型工厂 + 用户档案（课 2 / 课 9 落地）。

- 模型工厂：init_chat_model + 自定义 endpoint（课 2：模型初始化的两种方式 / 自定义接入）
- 用户档案：作为运行时上下文（context_schema），供动态提示词读取（课 9：生命周期上下文）
"""
import os
from dataclasses import dataclass

from dotenv import load_dotenv

# 加载实现/ 目录下的 .env（凭据不入库，模板见 .env.example）
load_dotenv()


def build_chat_model():
    """创建对话模型（课 2：自定义 endpoint 接入，走 OpenAI 兼容协议）。"""
    from langchain.chat_models import init_chat_model

    return init_chat_model(
        os.environ.get("CHAT_MODEL", "qwen3.8-flash"),
        model_provider="openai",
        base_url=os.environ["BAILIAN_BASE_URL"],
        api_key=os.environ["BAILIAN_API_KEY"],
        max_retries=2,
        timeout=60,
    )


def build_embeddings():
    """创建嵌入模型（课 11：知识库向量化，SiliconFlow 链路）。"""
    from langchain_openai import OpenAIEmbeddings

    return OpenAIEmbeddings(
        model=os.environ.get("SILICONFLOW_EMBEDDING_MODEL", "Qwen/Qwen3-Embedding-8B"),
        api_key=os.environ["SILICONFLOW_API_KEY"],
        base_url=os.environ["SILICONFLOW_BASE_URL"],
        check_embedding_ctx_length=False,
    )


def refund_approval_threshold() -> float:
    """退款人工审批阈值（元）——金额分级的界线（课 10：条件中断的业务参数）。"""
    return float(os.environ.get("REFUND_APPROVAL_THRESHOLD", "50"))


@dataclass
class UserProfile:
    """当前会话的用户档案（课 9：运行时上下文 → 动态提示词按用户注入）。

    调用时通过 `context=UserProfile(...)` 传入，动态提示词据此生成系统消息。
    """

    user_id: str = "guest"
    name: str = "访客"
    member_level: str = "V1"
