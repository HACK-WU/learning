/**
 * 流式事件协议（模拟）+ CLI 主入口
 *
 * 知识点覆盖：课 3「流式回传」、课 10「interrupt 等人工」「为什么不轮询」
 *
 * 为什么这里模拟 SSE 而不起 HTTP 服务：本项目的重点是"挂起与恢复"，
 * 起服务会引入端口、连接保活等与知识点无关的噪声。事件格式与真实 SSE 一致，
 * 换成 HTTP 只需把 emit 换成 res.write(`data: ${json}\n\n`)。
 */
import { parse as parseYaml } from "yaml";
import fs from "node:fs/promises";
import path from "node:path";
import { Command } from "@langchain/langgraph";

import { AgentDefinitionSchema, validateDefinition, toRuntime, type AgentDefinition } from "./definition/agent-definition.js";
import { FakeDatabase, ToolProvider, mergeProviders } from "./execute/tools.js";
import { compileAgent, type CompileContext } from "./compile/compiler.js";
import { FileSaver } from "./account/file-saver.js";
import { InvocationRuntime, BudgetGuard } from "./account/runtime.js";

/** 事件必须是"带类型"的，前端才能分派；错误也走事件（状态码早已发出） */
export type StreamEvent =
  | { type: "started"; invocationId: string }
  | { type: "token"; text: string }
  | { type: "tool"; name: string; output: string }
  | { type: "interrupt"; payload: unknown }
  | { type: "done"; status: string; output?: string[] }
  | { type: "error"; message: string };

export function formatEvent(e: StreamEvent): string {
  // 真实 SSE：data: {...}\n\n；这里打印成一行便于阅读
  return `event: ${e.type}\ndata: ${JSON.stringify(e)}\n`;
}

const ROOT = path.resolve(import.meta.dirname, "..");

async function loadDefinition(): Promise<AgentDefinition> {
  const raw = parseYaml(await fs.readFile(path.join(ROOT, "config/agent.yaml"), "utf8"));
  const problems = validateDefinition(raw);
  if (problems.length > 0) {
    // 校验前置：一次报出全部问题，而不是改一个跑一次
    throw new Error(`定义校验未通过：\n- ${problems.join("\n- ")}`);
  }
  return AgentDefinitionSchema.parse(raw);
}

async function main() {
  const mode = process.argv[2] ?? "demo";
  const db = new FakeDatabase();
  const provider = mergeProviders(ToolProvider.builtin(db), ToolProvider.remote());
  const definition = await loadDefinition();
  const runtime = new InvocationRuntime();
  const guard = new BudgetGuard(20_000);

  const saver = new FileSaver(path.join(ROOT, ".checkpoints"));
  const ctx: CompileContext = { definition, db, provider };
  const compiled = compileAgent(ctx, saver);

  // 编译四参数：checkpointer 已挂上（挂起/恢复的前提）；name 用作图身份
  const graph = compiled.graph;

  const threadId = "thread-demo-1";
  const requestId = mode === "reject" ? "req-reject-1" : "req-demo-1";
  const userText =
    mode === "reject"
      ? "请在 orders 表加列 audit_flag"
      : "请在 orders 表加列 note";

  const emit = (e: StreamEvent) => process.stdout.write(formatEvent(e));

  if (mode === "resume") {
    // ---------- 恢复路径：只带 threadId，不带业务参数 ----------
    // 这正是"挂起"的价值：等待期间进程可以退出，恢复时无需重放历史。
    // 判断"是否挂着"要用 getState().next —— pendingWrites 是框架内部字段，不可依赖。
    const snap: any = await graph.getState({ configurable: { thread_id: threadId } });
    const suspended = Array.isArray(snap?.next) && snap.next.length > 0;
    if (!suspended) {
      console.log("没有待恢复的流程（先跑 npm run demo）");
      return;
    }
    const ledger = runtime.findByRequest(requestId) ?? runtime.create(requestId, { t: "resume" }).ledger;
    emit({ type: "started", invocationId: ledger.invocationId });

    const out = await graph.invoke(new Command({ resume: "approve" }), {
      configurable: { thread_id: threadId },
    });
    for (const line of out.result ?? []) emit({ type: "tool", name: "executeSql", output: line });
    runtime.finish(ledger.invocationId, "succeeded", { sql: out.pendingSql });
    emit({ type: "done", status: "succeeded", output: out.result });
    return;
  }

  // ---------- 新请求路径 ----------
  const { ledger, duplicated } = runtime.create(requestId, { text: userText });
  emit({ type: "started", invocationId: ledger.invocationId });
  if (duplicated) {
    // 幂等命中：直接返回旧结论，不重复执行（否则 SQL 会跑两次）
    const prev = runtime.get(ledger.invocationId)!;
    emit({ type: "done", status: prev.status, output: prev.outcome?.sql ? [prev.outcome.sql] : [] });
    console.log(`(幂等命中：requestId=${requestId} 已有结论 ${prev.status})`);
    return;
  }

  const budget = guard.check(ledger);
  if (!budget.ok) {
    runtime.finish(ledger.invocationId, "failed", undefined, budget.reason);
    emit({ type: "error", message: budget.reason! });
    return;
  }

  // 清掉上一轮的挂起，保证 demo 可重复
  await saver.clear(threadId);
  runtime.addUsage(ledger.invocationId, { inputTokens: userText.length, outputTokens: 40, toolCalls: 1 });

  try {
    const out = await graph.invoke({ messages: [userText] }, { configurable: { thread_id: threadId } });

    const interrupts = (out as any).__interrupt__;
    if (Array.isArray(interrupts) && interrupts.length > 0) {
      // 挂起：落账本为 waiting_approval（非终态），进程可以退出了
      runtime.finish(ledger.invocationId, "waiting_approval");
      emit({ type: "interrupt", payload: interrupts[0].value });
      console.log("\n⏸  已挂起等待审批。进程可以退出，恢复请执行：npm run resume");
      return;
    }

    for (const line of out.result ?? []) emit({ type: "tool", name: "executeSql", output: line });
    if (mode === "reject") {
      runtime.finish(ledger.invocationId, "rejected", { sql: out.pendingSql });
      emit({ type: "done", status: "rejected", output: out.result });
    } else {
      runtime.finish(ledger.invocationId, "succeeded", { sql: out.pendingSql });
      emit({ type: "done", status: "succeeded", output: out.result });
    }
  } catch (e) {
    // 异常路径也必须落账本，否则留下永远 RUNNING 的僵尸记录
    runtime.finish(ledger.invocationId, "failed", undefined, (e as Error).message);
    emit({ type: "error", message: (e as Error).message });
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
