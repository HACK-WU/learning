/**
 * LangChain 课程（TypeScript 侧）· 接入自检脚本。
 *
 * 验证 LangChain.js 能否通过本课程的两条 API 链路调用模型：
 *   1. 阿里云百炼（课程默认，成本更低）—— qwen3.8-flash / deepseek-v4.1-flash
 *   2. DeepSeek（备用）—— deepseek-flash
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npm run conn          # 等价于 npx tsx check_connection.ts
 *
 * 凭据读取顺序：本目录 .env → ../playground/.env（与 Python 侧共用一份也可）。
 * 模板见 .env.example（不入库）。
 */

import dotenv from "dotenv";
import { initChatModel } from "langchain";

// 优先读本目录 .env；没有则回退到 Python 侧的 playground/.env
dotenv.config({ path: [".env", "../playground/.env"] });

const CASES: Array<{ name: string; model: string; keyEnv: string; urlEnv: string }> = [
  { name: "阿里云百炼 / qwen3.8-flash", model: "qwen3.8-flash", keyEnv: "BAILIAN_API_KEY", urlEnv: "BAILIAN_BASE_URL" },
  { name: "阿里云百炼 / deepseek-v4.1-flash", model: "deepseek-v4.1-flash", keyEnv: "BAILIAN_API_KEY", urlEnv: "BAILIAN_BASE_URL" },
  { name: "DeepSeek / deepseek-flash", model: "deepseek-flash", keyEnv: "DEEPSEEK_API_KEY", urlEnv: "DEEPSEEK_BASE_URL" },
];

async function main(): Promise<void> {
  let ok = 0;
  for (const { name, model, keyEnv, urlEnv } of CASES) {
    console.log(`\n--- ${name} ---`);
    try {
      const chat = await initChatModel(model, {
        modelProvider: "openai",
        apiKey: process.env[keyEnv]!,
        baseUrl: process.env[urlEnv]!,
      });
      const reply = await chat.invoke("请只回复六个字：链路连接成功");
      console.log("[OK]", String(reply.content).slice(0, 200));
      ok += 1;
    } catch (error) {
      console.log("[FAIL]");
      console.error(error);
    }
  }
  console.log(`\n===== 结果：${ok}/${CASES.length} 通过 =====`);
}

await main();