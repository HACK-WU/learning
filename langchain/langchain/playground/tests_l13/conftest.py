# -*- coding: utf-8 -*-
"""课 13 测试套件共用配置：密钥加载与跳过逻辑。

官方推荐在 conftest.py 中统一校验凭据；本套件采用「显式 fixture」变体：
纯离线测试（单元 / 轨迹匹配）不依赖密钥、也不应被跳过，只有真调 API 的
测试才要求 require_api_key。
"""
import os
from pathlib import Path

import pytest
from dotenv import load_dotenv

# playground/.env（真实密钥只存在这里，不入库；仓库内只保留 .env.example）
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


@pytest.fixture
def require_api_key():
    """真调 API 的测试入口：缺密钥时 skip（而非报错失败）。"""
    if not os.environ.get("BAILIAN_API_KEY"):
        pytest.skip("BAILIAN_API_KEY not set")


def _scrub_uri(request):
    """录制前把真实接入端点替换为文档占位符（cassette 会随课程入库）。"""
    if request.uri and "://" in request.uri:
        scheme, rest = request.uri.split("://", 1)
        _, _, path = rest.partition("/")
        request.uri = f"{scheme}://api.example.com/{path}"
    return request


@pytest.fixture(scope="session")
def vcr_config():
    """录制回放的脱敏与匹配配置。

    - 凭据（authorization / api_key）替换为占位符后才写入 cassette
    - 真实接入端点替换为 api.example.com（cassette 会随课程入库）
    - 匹配规则忽略 host：回放不依赖真实端点，只看请求方法 / 路径 / 内容
    """
    return {
        "filter_headers": [
            ("authorization", "Bearer <REDACTED>"),
            ("x-api-key", "<REDACTED>"),
            ("host", "api.example.com"),
        ],
        "filter_query_parameters": [
            ("api_key", "<REDACTED>"),
            ("key", "<REDACTED>"),
        ],
        "before_record_request": _scrub_uri,
        "match_on": ["method", "scheme", "path", "query", "body"],
    }
