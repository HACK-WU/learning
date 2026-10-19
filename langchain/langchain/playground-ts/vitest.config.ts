import { defineConfig } from "vitest/config";

/**
 * 课 13 / 应用实战 13 的 vitest 分流配置
 *
 * 📌 TS 侧没有 pytest.ini + marker，分流靠目录：
 *   - test/unit/**        快层：fakeModel 替身，零网络零成本，每次改动跑
 *   - test/integration/** 真层：真调模型端点，交付前显式跑
 *
 * 默认只跑快层（对应 Python 的 `addopts = -m "not integration"`）：
 *   npm run test:unit
 * 集成层显式跑：
 *   npm run test:integration
 */
export default defineConfig({
  test: {
    // 默认只收快层，真层必须显式用 vitest.integration.config.ts
    include: ["test/unit/**/*.test.ts"],
    // 不把 playground 里的可执行脚本当成测试文件
    exclude: ["node_modules/**"],
    // 全局前置：载入 .env、统一环境变量读取（对应 Python conftest.py 的位置）
    setupFiles: ["test/setup.ts"],
    // 单测不依赖真实密钥；需要端点的用例自行 skipIf
    environment: "node",
    testTimeout: 30_000,
  },
});
