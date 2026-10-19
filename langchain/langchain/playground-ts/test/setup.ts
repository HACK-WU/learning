/**
 * vitest 全局前置（对应 Python 的 conftest.py 夹具位置）
 *
 * 对应文档：应用实战/13-Testing与Observability.md（vitest.config.ts 的 setupFiles）
 *
 * 这里只做"所有层都需要"的最小准备：
 *   - 载入 .env（本地端点 / 密钥），缺失时不报错
 *   - 统一测试内的环境变量读取方式
 *
 * ⚠️ 注意：不要在这里做"真调模型"的准备。
 *    快层（test/unit）必须零网络，密钥缺失是正常状态。
 */
import "dotenv/config";

// 缺省端点：仅为让本地 mock（temp/ts-mock-server.mjs, 8931）场景可用；
// 没有 .env 也不会让单测失败（单测用 fakeModel，不发请求）。
process.env.BAILIAN_BASE_URL ??= "http://127.0.0.1:8931/v1";
process.env.BAILIAN_MODEL ??= "qwen3.8-flash";
