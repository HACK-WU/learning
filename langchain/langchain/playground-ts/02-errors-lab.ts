/**
 * 第 2 课 · 接入报错实验（TypeScript 版，对应 playground/02-errors-lab.py）
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 02-errors-lab.ts
 *
 * 说明：本脚本故意使用错误的配置（假 key / 错模型名 / 错域名），演示报错形态；
 * 输出中的真实密钥已替换为占位符，可安全分享。
 * 为控制演示时长，此处设置 maxRetries: 1（默认值为 6，重试会成倍拉长等待）。
 */

import dotenv from "dotenv";
import { initChatModel } from "langchain";
import { getRetryable } from "@langchain/core/errors";

dotenv.config({ path: [".env", "../playground/.env"] });

const REAL_KEY = process.env.BAILIAN_API_KEY as string;
const REAL_URL = process.env.BAILIAN_BASE_URL as string;

const CASES: Array<[string, Record<string, unknown>]> = [
  ["认证失败（无效 API key）", { apiKey: "sk-invalid-key-for-demo", baseUrl: REAL_URL, model: "qwen3.8-flash" }],
  ["模型不存在（错误模型名）", { apiKey: REAL_KEY, baseUrl: REAL_URL, model: "no-such-model-xyz" }],
  ["端点不可达（不存在的域名）", { apiKey: REAL_KEY, baseUrl: "https://no-such-host.example.com/v1", model: "qwen3.8-flash" }],
];

for (const [name, cfg] of CASES) {
  console.log(`\n--- ${name} ---`);
  const { model: modelName, ...rest } = cfg;
  try {
    const model = await initChatModel(String(modelName), {
      modelProvider: "openai",
      maxRetries: 1,
      timeout: 15_000, // 毫秒（Python 侧为秒）
      ...rest,
    });
    await model.invoke("你好");
    console.log("（未报错，意外情况）");
  } catch (e: any) {
    console.log(`异常类型: ${e.constructor.name}`);
    const msg = String(e.message).replace(REAL_KEY ?? "", "<YOUR_API_KEY>");
    console.log(`消息摘要: ${msg.split("\n")[0].slice(0, 240)}`);
    console.log(`status: ${e.status}`);
    console.log(`lc_error_code: ${e.lc_error_code}`);
    console.log(`getRetryable: ${getRetryable(e)}`);
  }
}