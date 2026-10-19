/**
 * 第 2 课 · 实操：模型选型对比（TypeScript 版，对应 playground/compare-models.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx compare-models.ts
 *
 * 输出即讲义第四幕引用的 TS 侧证据：两平台的并发耗时与 token 账单对比。
 * 注意：TypeScript 侧没有 get_usage_metadata_callback 的对应物，
 * 账单由逐条累加响应上的 usage_metadata 得到。
 */

import dotenv from "dotenv";
import { initChatModel } from "langchain";

dotenv.config({ path: [".env", "../playground/.env"] });

const QUESTIONS = ["用一句话介绍杭州。", "用一句话解释什么是缓存。", "用一句话解释什么是索引。"];

const PLATFORMS: Record<string, Record<string, unknown>> = {
  "阿里云百炼 / qwen3.8-flash": {
    model: "qwen3.8-flash",
    apiKey: process.env.BAILIAN_API_KEY,
    baseUrl: process.env.BAILIAN_BASE_URL,
  },
  "DeepSeek / deepseek-flash": {
    model: "deepseek-flash",
    apiKey: process.env.DEEPSEEK_API_KEY,
    baseUrl: process.env.DEEPSEEK_BASE_URL,
  },
};

for (const [name, cfg] of Object.entries(PLATFORMS)) {
  const { model: modelName, ...rest } = cfg;
  const model = await initChatModel(String(modelName), { modelProvider: "openai", ...rest });

  const t0 = Date.now();
  const results = await model.batch(QUESTIONS); // 并发三条
  const elapsed = (Date.now() - t0) / 1000;

  // 账单统计：逐条累加 usage_metadata（对应 Python 侧的 get_usage_metadata_callback）
  const bill = results.reduce(
    (acc, r) => {
      const u: any = r.usage_metadata;
      if (u) {
        acc.input_tokens += u.input_tokens ?? 0;
        acc.output_tokens += u.output_tokens ?? 0;
        acc.total_tokens += u.total_tokens ?? 0;
        acc.reasoning += u.output_token_details?.reasoning ?? 0;
      }
      return acc;
    },
    { total_tokens: 0, output_tokens: 0, reasoning: 0, input_tokens: 0 },
  );

  console.log(`\n===== ${name} =====`);
  console.log(`3 条并发耗时: ${elapsed.toFixed(2)}s`);
  QUESTIONS.forEach((q, i) => {
    console.log(`  Q: ${q}`);
    console.log(`  A: ${String((results[i] as any).text).trim().slice(0, 80)}`);
  });
  console.log(`token 账单: ${JSON.stringify(bill)}`);
}