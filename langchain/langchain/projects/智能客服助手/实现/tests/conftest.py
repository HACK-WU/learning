# -*- coding: utf-8 -*-
"""测试共用配置：密钥加载与跳过逻辑（课 13：集成测试的凭据管理）。"""
import os
from pathlib import Path

import pytest
from dotenv import load_dotenv

# 加载 实现/.env（真实凭据只存在这里，不入库；模板见 .env.example）
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


@pytest.fixture
def require_api_key():
    """真调 API 的测试入口：缺密钥时 skip（而非报错失败）。"""
    if not os.environ.get("BAILIAN_API_KEY"):
        pytest.skip("BAILIAN_API_KEY not set")


@pytest.fixture
def clean_ledgers():
    """清理模块级账本（审计轨迹 / 业务动作），保证测试互不影响。"""
    from app.middleware.safety import AUDIT_LOG
    from app.tools.aftersales import ACTIONS

    audit_before = len(AUDIT_LOG)
    actions_before = len(ACTIONS)
    yield
    del AUDIT_LOG[audit_before:]
    del ACTIONS[actions_before:]
