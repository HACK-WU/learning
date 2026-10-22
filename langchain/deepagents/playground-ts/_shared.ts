/**
 * 公共工具：凭据加载 + 模型工厂 + 后端打印辅助。
 *
 * 所有 lNN-*.ts 脚本都从这里取模型，保证「改一处、全课程切换」。
 * 凭据查找顺序：本目录 .env → 兄弟教程 playground/.env。
 */

import dotenv from "dotenv";
import { ChatOpenAI } from "@langchain/openai";

dotenv.config({ path: [".env", "../playground/.env"] });

/** 取环境变量，缺失时抛错并给出可操作提示（不静默用假值）。 */
export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    throw new Error(
      `缺少环境变量 ${name}。请复制 .env.example 为 .env，或确认 ../playground/.env 存在。`,
    );
  }
  return v;
}

export interface ModelOptions {
  /** 覆盖默认模型名（默认读 DEEPAGENTS_MODEL） */
  model?: string;
  temperature?: number;
}

/**
 * 构造课程默认模型。
 *
 * 注意：Deep Agents 官方默认模型是 `anthropic:claude-sonnet-4-6`，
 * 本课程对齐 LangChain 教程口径，默认走百炼 OpenAI 兼容端点以降低成本。
 * 若你要验证官方默认行为，直接传 model: "anthropic:claude-sonnet-4-6"。
 */
export function courseModel(options: ModelOptions = {}): ChatOpenAI {
  return new ChatOpenAI({
    model: options.model ?? process.env.DEEPAGENTS_MODEL ?? "qwen3.8-flash",
    temperature: options.temperature ?? 0,
    apiKey: requireEnv("BAILIAN_API_KEY"),
    configuration: { baseURL: requireEnv("BAILIAN_BASE_URL") },
  });
}

/** 小标题打印，让脚本输出在终端里可分段阅读。 */
export function section(title: string): void {
  console.log(`\n${"=".repeat(6)} ${title} ${"=".repeat(6)}`);
}

/** 安全截断长文本，避免终端被刷屏。 */
export function clip(text: unknown, max = 400): string {
  const s = typeof text === "string" ? text : JSON.stringify(text);
  return s.length > max ? `${s.slice(0, max)}…(截断)` : s;
}
