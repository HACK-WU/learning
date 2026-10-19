import "dotenv/config";

// 测试环境统一入口：对应 Python 侧的 conftest.py
// 缺密钥时不是失败，而是让集成测试整组 skip
process.env.LANGCHAIN_TRACING_V2 ??= "false";
process.env.OPENAI_API_KEY ??= "";
