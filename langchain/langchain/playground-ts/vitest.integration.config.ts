import { defineConfig } from "vitest/config";

/**
 * 集成层（真层）专用配置：真调模型端点，交付前显式跑
 *
 * 对应文档：应用实战/13-Testing与Observability.md
 *   `npx vitest run --config vitest.integration.config.ts`
 *
 * 与 vitest.config.ts 的关系：
 *   - vitest.config.ts          → include 只收 test/unit/**（日常快层）
 *   - vitest.integration.config.ts → include 只收 test/integration/**（交付真层）
 *
 * 为什么不用 `--dir`：vitest 的 include 与 --dir 叠加会导致匹配为空，
 * 用独立 config 做 include 白名单更可靠（也与文档给出的命令一致）。
 */
export default defineConfig({
  test: {
    include: ["test/integration/**/*.test.ts"],
    exclude: ["node_modules/**"],
    environment: "node",
    // 真调模型，给足超时
    testTimeout: 60_000,
  },
});
