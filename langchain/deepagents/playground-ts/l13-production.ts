/**
 * 课 13 · TypeScript 侧探针：容错、流式、上线清单。
 *
 * 全部离线：用自造的 BaseChatModel 子类当"会按剧本失败的模型"，
 * 不读 API key、不打网络。对应 Python 侧探针 1-8。
 *
 * 运行：npx tsx l13-production.ts
 */

import { createDeepAgent } from "deepagents";
import {
  createAgent,
  modelRetryMiddleware,
  modelFallbackMiddleware,
  modelCallLimitMiddleware,
  toolCallLimitMiddleware,
  toolRetryMiddleware,
} from "langchain";
import { BaseChatModel } from "@langchain/core/language_models/chat_models";
import { AIMessage, BaseMessage } from "@langchain/core/messages";
import { stampRetryable, getRetryable } from "@langchain/core/errors";
import { tool } from "@langchain/core/tools";
import { MemorySaver, Command } from "@langchain/langgraph";
import { z } from "zod";

const section = (t: string) => console.log(`\n====== ${t} ======`);

/**
 * 探针里大量用 `as never` 关掉参数校验（为了塞假模型、假 middleware），
 * 但这会让 createDeepAgent 的泛型推断退化：`middleware` 被推成 never，
 * 状态 schema 跟着塌，`invoke({ messages })` 就只剩 `Command` 那一条重载，
 * 于是 tsc 报 "Object literal may only specify known properties, and 'messages'
 * does not exist in type 'Command'"。运行时完全正常——纯类型噪音。
 *
 * 统一从 deepAgent() 拿，返回一个刻意宽松的 AnyAgent，探针只关心运行时行为。
 */
type AnyAgent = {
  options: { middleware?: readonly unknown[] };
  invoke: (input: unknown, config?: unknown) => Promise<Record<string, any>>;
  streamEvents: (input: unknown, config?: unknown) => Promise<Record<string, any>>;
};

const deepAgent = (params: unknown): AnyAgent =>
  createDeepAgent(params as never) as unknown as AnyAgent;

const asAgent = (a: unknown): AnyAgent => a as AnyAgent;

/* ---------------------------------------------------------------- *
 * 计数与被控模型
 * ---------------------------------------------------------------- */

const tally: Record<string, number> = {};
const bump = (k: string) => {
  tally[k] = (tally[k] ?? 0) + 1;
};
const resetTally = () => {
  for (const k of Object.keys(tally)) delete tally[k];
};

const withStatus = (status: number): Error => {
  const e = new Error(`http ${status}`) as Error & { status: number };
  e.status = status;
  return e;
};

/** 按剧本抛错的模型：先失败 failTimes 次，之后成功。 */
class FlakyModel extends BaseChatModel {
  calls = 0;
  failTimes: number;
  err: Error;
  constructor(err: Error, failTimes = Number.POSITIVE_INFINITY) {
    super({});
    this.err = err;
    this.failTimes = failTimes;
  }
  _llmType() {
    return "flaky";
  }
  bindTools() {
    return this;
  }
  async _generate() {
    this.calls += 1;
    if (this.calls <= this.failTimes) throw this.err;
    return { generations: [{ text: "ok", message: new AIMessage("ok") }] };
  }
}

/** 记名模型：用来观察"谁被调了几次"，用于降级顺序验证。 */
class NamedModel extends BaseChatModel {
  tag: string;
  err?: Error;
  constructor(tag: string, err?: Error) {
    super({});
    this.tag = tag;
    this.err = err;
  }
  _llmType() {
    return this.tag;
  }
  bindTools() {
    return this;
  }
  async _generate() {
    bump(this.tag);
    if (this.err) throw this.err;
    return { generations: [{ text: `from ${this.tag}`, message: new AIMessage(`from ${this.tag}`) }] };
  }
}

/** 会重复调同一个工具 N 轮的模型，用于上限验证。 */
class LoopModel extends BaseChatModel {
  rounds = 0;
  maxRounds: number;
  toolName: string;
  constructor(maxRounds: number, toolName = "echo") {
    super({});
    this.maxRounds = maxRounds;
    this.toolName = toolName;
  }
  _llmType() {
    return "loop";
  }
  bindTools() {
    return this;
  }
  async _generate() {
    bump("loop");
    this.rounds += 1;
    if (this.rounds <= this.maxRounds) {
      return {
        generations: [{
          text: "",
          message: new AIMessage({
            content: "",
            tool_calls: [{ id: `c${this.rounds}`, name: this.toolName, args: {} }],
          }),
        }],
      };
    }
    return { generations: [{ text: "done", message: new AIMessage("done") }] };
  }
}

const echo = tool(async () => "executed", {
  name: "echo",
  description: "回声",
  schema: z.object({}),
});

/* ---------------------------------------------------------------- *
 * 探针 1：默认重试判定到底看什么
 * ---------------------------------------------------------------- */

section("探针 1：默认 retryOn 对 401 / 429 / 500 的态度");

const retryCfg = { maxRetries: 2, initialDelayMs: 0, backoffFactor: 2 } as const;

const probeRetry = async (label: string, err: Error, opts: { deep?: boolean; custom?: boolean } = {}) => {
  const deep = opts.deep ?? true;
  const model = new FlakyModel(err);
  const seen: unknown[] = [];
  const mw = modelRetryMiddleware({
    ...retryCfg,
    ...(opts.custom
      ? {
          retryOn: (e: unknown) => {
            // 沿 cause 链找标记：deepagents 会把模型异常包一层 MiddlewareError
            let cur: any = e;
            for (let i = 0; cur && i < 8; i += 1) {
              const mark = getRetryable(cur);
              if (mark !== undefined) {
                seen.push(mark);
                return mark;
              }
              cur = cur.cause;
            }
            seen.push("unmarked");
            return true;
          },
        }
      : {}),
  } as never);
  const cfg = { model: model as never, tools: [] as never, middleware: [mw] as never };
  const agent = deep ? deepAgent(cfg) : asAgent(createAgent(cfg as never));
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  const last = String(out.messages.at(-1)?.content ?? "");
  const attempts = model.calls;
  const tag = attempts === 1 ? "不重试" : "重试了";
  console.log(
    `  ${label.padEnd(30)} 调用 ${attempts} 次｜${tag}｜末条=${JSON.stringify(last.slice(0, 46))}${opts.custom ? `｜标记=${JSON.stringify(seen[0])}` : ""}`,
  );
};

console.log("  -- A) 默认 retryOn（只看最外层错误）--");
await probeRetry("Error.status=401", withStatus(401));
await probeRetry("Error.status=403", withStatus(403));
await probeRetry("Error.status=429", withStatus(429));
await probeRetry("Error.status=500", withStatus(500));
await probeRetry("裸 Error('unauthorized')", new Error("unauthorized"));
await probeRetry("401 打标 false", stampRetryable(withStatus(401), false) as Error);
await probeRetry("500 打标 false", stampRetryable(withStatus(500), false) as Error);
await probeRetry("500 打标 true", stampRetryable(withStatus(500), true) as Error);

console.log("  -- B) 同一批错误换 createAgent（无 deepagents 中间件链）--");
await probeRetry("401 打标 false", stampRetryable(withStatus(401), false) as Error, { deep: false });
await probeRetry("500 打标 true", stampRetryable(withStatus(500), true) as Error, { deep: false });

console.log("  -- C) 自定义 retryOn 沿 cause 链找标记 --");
await probeRetry("401 打标 false", stampRetryable(withStatus(401), false) as Error, { custom: true });
await probeRetry("500 打标 true", stampRetryable(withStatus(500), true) as Error, { custom: true });
await probeRetry("不打标", withStatus(401), { custom: true });

console.log("  ↳ 结论：getRetryable 只读最外层错误上的 Symbol 标记。createAgent 下打标立即生效，");
console.log("     但 createDeepAgent 会把模型异常包成 MiddlewareError，标记留在 .cause 上，");
console.log("     默认 retryOn 看不到 → 打标失效。要它生效，retryOn 必须自己沿 cause 链找。");

/* ---------------------------------------------------------------- *
 * 探针 2：maxRetries 与 onFailure
 * ---------------------------------------------------------------- */

section("探针 2：maxRetries 与 onFailure");

{
  const model = new FlakyModel(withStatus(500));
  const agent = deepAgent({
    model: model as never,
    tools: [],
    middleware: [modelRetryMiddleware({ maxRetries: 0, initialDelayMs: 0 } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  maxRetries=0      → 调用 ${model.calls} 次｜末条=${JSON.stringify(String(out.messages.at(-1)?.content).slice(0, 56))}`);
}
{
  const model = new FlakyModel(withStatus(500), 2);
  const agent = deepAgent({
    model: model as never,
    tools: [],
    middleware: [modelRetryMiddleware({ maxRetries: 3, initialDelayMs: 0 } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  失败 2 次后成功    → 调用 ${model.calls} 次｜末条=${JSON.stringify(String(out.messages.at(-1)?.content).slice(0, 40))}`);
}
{
  const model = new FlakyModel(withStatus(500));
  const agent = deepAgent({
    model: model as never,
    tools: [],
    middleware: [modelRetryMiddleware({ maxRetries: 1, initialDelayMs: 0 } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  onFailure 默认    → 没抛，末条是 AIMessage=${out.messages.at(-1)?.getType() === "ai"}｜文案=${JSON.stringify(String(out.messages.at(-1)?.content).slice(0, 70))}`);
}
{
  const model = new FlakyModel(withStatus(500));
  const agent = deepAgent({
    model: model as never,
    tools: [],
    middleware: [modelRetryMiddleware({ maxRetries: 1, initialDelayMs: 0, onFailure: "error" } as never)] as never,
  });
  try {
    await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
    console.log("  onFailure='error'  → 没抛（不符合预期）");
  } catch (e) {
    console.log(`  onFailure='error'  → 抛出 ${(e as Error).constructor.name}`);
  }
}

console.log("  ↳ 结论：重试耗尽默认不抛，而是把失败写成一条 AIMessage 继续跑；");
console.log("     要它抛必须显式 onFailure: 'error'。Python 侧同名参数叫 on_failure。");

/* ---------------------------------------------------------------- *
 * 探针 3：有没有 rate limit
 * ---------------------------------------------------------------- */

section("探针 3：导出清单里有没有 QPS 限流");

{
  const m = await import("langchain");
  const keys = Object.keys(m);
  const limitLike = keys.filter((k) => /limit/i.test(k)).sort();
  const rateLike = keys.filter((k) => /^modelRate|^rateLimit|throttle/i.test(k)).sort();
  console.log(`  带 Limit 的导出：${limitLike.join(", ")}`);
  console.log(`  带 Rate/Throttle 的中间件：${rateLike.length ? rateLike.join(", ") : "(没有)"}`);
}

/* ---------------------------------------------------------------- *
 * 探针 4：重试与降级的顺序
 * ---------------------------------------------------------------- */

section("探针 4：重试与降级的顺序");

{
  resetTally();
  const primary = new NamedModel("primary", new Error("主模型挂了"));
  const backup = new NamedModel("backup");
  const agent = deepAgent({
    model: primary as never,
    tools: [],
    middleware: [
      modelRetryMiddleware({ maxRetries: 2, initialDelayMs: 0 } as never),
      modelFallbackMiddleware(backup as never),
    ] as never,
  });
  await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  重试(外) + 降级(内) → ${JSON.stringify(tally)}`);
}
{
  resetTally();
  const primary = new NamedModel("primary", new Error("主模型挂了"));
  const backup = new NamedModel("backup");
  const agent = deepAgent({
    model: primary as never,
    tools: [],
    middleware: [
      modelFallbackMiddleware(backup as never),
      modelRetryMiddleware({ maxRetries: 2, initialDelayMs: 0 } as never),
    ] as never,
  });
  await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  降级(外) + 重试(内) → ${JSON.stringify(tally)}`);
}

console.log("  ↳ 结论：跟 Python 一致——降级必须放在里层（数组靠后），");
console.log("     放外层时重试把 primary 打满就直接失败，backup 一次没被调。");

/* ---------------------------------------------------------------- *
 * 探针 5：次数上限的默认行为
 * ---------------------------------------------------------------- */

section("探针 5：次数上限（不是限速）");

{
  const model = new LoopModel(3);
  const agent = deepAgent({
    model: model as never,
    tools: [echo],
    middleware: [modelCallLimitMiddleware({ runLimit: 1 } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  modelCallLimit runLimit=1（想跑 4 轮）→ 实际 ${model.rounds} 轮`);
  console.log(`    末条=${JSON.stringify(String(out.messages.at(-1)?.content).slice(0, 84))}`);
}
{
  const model = new LoopModel(3);
  const agent = deepAgent({
    model: model as never,
    tools: [echo],
    middleware: [modelCallLimitMiddleware({ runLimit: 1, exitBehavior: "error" } as never)] as never,
  });
  try {
    await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
    console.log("  exitBehavior='error' → 没抛（不符合预期）");
  } catch (e) {
    console.log(`  exitBehavior='error' → 抛出 ${(e as Error).constructor.name}`);
  }
}
{
  const model = new LoopModel(3);
  const agent = deepAgent({
    model: model as never,
    tools: [echo],
    middleware: [toolCallLimitMiddleware({ toolName: "echo", runLimit: 1 } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  const tools = out.messages.filter((m: BaseMessage) => m.getType() === "tool");
  console.log(`  toolCallLimit 默认 → 模型 ${model.rounds} 轮、tool 消息 ${tools.length} 条`);
  console.log(`    被拦的那条=${JSON.stringify(String(tools.at(-1)?.content).slice(0, 74))}`);
}
{
  const model = new LoopModel(3);
  const agent = deepAgent({
    model: model as never,
    tools: [echo],
    middleware: [toolCallLimitMiddleware({ toolName: "echo", runLimit: 1, exitBehavior: "end" } as never)] as never,
  });
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  console.log(`  toolCallLimit exitBehavior='end' → 模型 ${model.rounds} 轮｜末条=${JSON.stringify(String(out.messages.at(-1)?.content).slice(0, 70))}`);
}

console.log("  ↳ 结论：Model 层默认 exitBehavior='end'（正常收尾，不抛），");
console.log("     Tool 层默认 'continue'（假 ToolMessage 喂回去，模型还能继续）。");
console.log("     两侧默认值一致，但 TS 的 Tool 层多一档 'end'（Python 只有 continue/error）。");

/* ---------------------------------------------------------------- *
 * 探针 6：工具级重试
 * ---------------------------------------------------------------- */

section("探针 6：工具级重试与失败策略");

const oneCallAgent = (toolName: string, t: unknown, mw: unknown[]) =>
  deepAgent({
    model: new (class extends BaseChatModel {
      done = false;
      constructor() {
        super({});
      }
      _llmType() {
        return "one";
      }
      bindTools() {
        return this;
      }
      async _generate() {
        if (!this.done) {
          this.done = true;
          return {
            generations: [{
              text: "",
              message: new AIMessage({ content: "", tool_calls: [{ id: "c1", name: toolName, args: {} }] }),
            }],
          };
        }
        return { generations: [{ text: "done", message: new AIMessage("done") }] };
      }
    })() as never,
    tools: [t as never],
    middleware: mw as never,
  });

{
  let hits = 0;
  const flaky = tool(async () => {
    hits += 1;
    if (hits <= 2) throw new Error("net down");
    return "ok";
  }, { name: "flaky", description: "会失败两次", schema: z.object({}) });
  const agent = oneCallAgent("flaky", flaky, [toolRetryMiddleware({ maxRetries: 3, initialDelayMs: 0 } as never)]);
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  const tools = out.messages.filter((m: BaseMessage) => m.getType() === "tool");
  console.log(`  失败 2 次后成功 → 工具执行 ${hits} 次｜tool 消息=${JSON.stringify(tools.map((m: BaseMessage) => String(m.content)))}`);
}
{
  let hits = 0;
  const always = tool(async () => {
    hits += 1;
    throw new Error("always");
  }, { name: "always", description: "永远失败", schema: z.object({}) });
  const agent = oneCallAgent("always", always, [toolRetryMiddleware({ maxRetries: 2, initialDelayMs: 0 } as never)]);
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
  const tools = out.messages.filter((m: BaseMessage) => m.getType() === "tool");
  console.log(`  一直失败(默认) → 工具执行 ${hits} 次｜tool 消息=${JSON.stringify(String(tools.at(-1)?.content).slice(0, 62))}`);
}
{
  let hits = 0;
  const always = tool(async () => {
    hits += 1;
    throw new Error("always");
  }, { name: "always", description: "永远失败", schema: z.object({}) });
  const agent = oneCallAgent("always", always, [
    toolRetryMiddleware({ maxRetries: 2, initialDelayMs: 0, onFailure: "error" } as never),
  ]);
  try {
    await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
    console.log(`  onFailure='error' → 工具执行 ${hits} 次，没抛`);
  } catch (e) {
    console.log(`  onFailure='error' → 工具执行 ${hits} 次，抛出 ${(e as Error).constructor.name}`);
  }
}

/* ---------------------------------------------------------------- *
 * 探针 7：checkpointer 缺失的真实行为
 * ---------------------------------------------------------------- */

section("探针 7：不配 checkpointer 时会怎样");

{
  // 必须用"能正常发 tool_call"的模型：若用会抛错的模型，模型异常会先炸，
  // 把真正的 GraphValueError 盖掉，探针就白跑了。
  resetTally();
  const agent = deepAgent({ model: new LoopModel(1) as never, tools: [echo], interruptOn: { echo: true } as never });
  try {
    await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
    console.log("  不配 checkpointer + interruptOn → invoke 没抛（不符合预期）");
  } catch (e) {
    console.log(`  不配 checkpointer + interruptOn → invoke 直接抛 ${(e as Error).constructor.name}`);
    console.log(`    文案=${JSON.stringify((e as Error).message.split("\n")[0])}`);
    const url = ((e as Error).message.match(/https?:\/\/\S+/) ?? [])[0];
    console.log(`    排障链接=${url ?? "（无）"}`);
  }
}
{
  const saver = new MemorySaver();
  const agent = deepAgent({
    model: new LoopModel(1) as never,
    tools: [echo],
    interruptOn: { echo: true } as never,
    checkpointer: saver,
  });
  const cfg = { configurable: { thread_id: "t-1" } };
  const out = await agent.invoke({ messages: [{ role: "user", content: "hi" }] }, cfg);
  const n = Array.isArray(out.__interrupt__) ? out.__interrupt__.length : 0;
  console.log(`  配了 checkpointer → 中断条数 ${n}`);
  const out2 = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }) as never, cfg);
  const tools = out2.messages.filter((m: BaseMessage) => m.getType() === "tool");
  console.log(`    恢复后 tool 消息=${JSON.stringify(tools.map((m: BaseMessage) => String(m.content)))}`);
}

console.log("  ↳ 结论：这里两侧行为完全相反。Python 不配 checkpointer 也能触发中断、");
console.log("     恢复时才炸；TS 连第一次 invoke 都不给过，直接 GraphValueError: No checkpointer set。");

/* ---------------------------------------------------------------- *
 * 探针 8：流式入口
 * ---------------------------------------------------------------- */

section("探针 8：子代理流式的入口与句柄");

{
  class MainModel extends BaseChatModel {
    step = 0;
    constructor() {
      super({});
    }
    _llmType() {
      return "main";
    }
    bindTools() {
      return this;
    }
    async _generate() {
      this.step += 1;
      if (this.step === 1) {
        return {
          generations: [{
            text: "",
            message: new AIMessage({
              content: "",
              tool_calls: [{ id: "t1", name: "task", args: { description: "处理 A", subagent_type: "worker" } }],
            }),
          }],
        };
      }
      return { generations: [{ text: "done", message: new AIMessage("done") }] };
    }
  }
  class WorkerModel extends BaseChatModel {
    constructor() {
      super({});
    }
    _llmType() {
      return "worker";
    }
    bindTools() {
      return this;
    }
    async _generate() {
      return { generations: [{ text: "worker 干完了", message: new AIMessage("worker 干完了") }] };
    }
  }

  const agent = deepAgent({
    model: new MainModel() as never,
    tools: [],
    subagents: [{ name: "worker", description: "干活", model: new WorkerModel() as never, tools: [] }] as never,
  });

  console.log(`  agent.stream 上有没有 subagents: ${"subagents" in (agent as object)}`);
  const p = agent.streamEvents({ messages: [{ role: "user", content: "hi" }] }, { version: "v3" });
  console.log(`  streamEvents 返回的是 Promise: ${p instanceof Promise}（要 await）`);
  const run = await p;
  console.log(`  await 后是 ${run.constructor.name}`);
  console.log(`  投影：subgraphs=${typeof run.subgraphs}｜subagents=${typeof run.subagents}｜messages=${typeof run.messages}｜values=${typeof run.values}｜output=${typeof run.output}`);
  console.log(`  subagents 是 StreamChannel: ${run.subagents?.constructor?.name === "StreamChannel"}`);

  const names: string[] = [];
  for await (const h of run.subagents as AsyncIterable<{ name?: string }>) {
    names.push(String(h.name));
    const handle = h as unknown as Record<string, unknown>;
    console.log(`  句柄 name=${JSON.stringify(handle.name)}`);
    console.log(`    字段类型：output=${typeof handle.output}（Promise）｜messages=${typeof handle.messages}｜toolCalls=${typeof handle.toolCalls}｜subagents=${typeof handle.subagents}`);
    const out = (await (handle.output as Promise<{ messages?: unknown[] }>)) ?? {};
    console.log(`    output 里 messages 条数=${Array.isArray(out.messages) ? out.messages.length : "N/A"}`);
  }
  console.log(`  收到的子代理：${JSON.stringify(names)}`);

  const second: string[] = [];
  for await (const h of run.subagents as AsyncIterable<{ name?: string }>) second.push(String(h.name));
  console.log(`  第二次遍历 → ${JSON.stringify(second)}（TS 侧没抛，跟 Python 的单订阅限制不同）`);
  const ch = run.subagents as unknown as { atee?: unknown; iterate?: unknown };
  console.log(`  有没有 atee: ${typeof ch.atee}｜有没有 iterate: ${typeof ch.iterate}`);
}

console.log("\n  ↳ 结论：TS 侧入口同样是 streamEvents + version:'v3'，也需要 await；");
console.log("     subagents 是 StreamChannel 可多次订阅（不像 Python 单订阅要 atee）；");
console.log("     句柄上 name/output 是自有属性，没有 status/path/messages 的 Python 式形态。");

/* ---------------------------------------------------------------- *
 * 探针 9：子代理容错是否继承
 * ---------------------------------------------------------------- */

section("探针 9：子代理不继承主代理的容错");

{
  resetTally();
  class MainModel extends BaseChatModel {
    step = 0;
    constructor() {
      super({});
    }
    _llmType() {
      return "main";
    }
    bindTools() {
      return this;
    }
    async _generate() {
      bump("main");
      this.step += 1;
      if (this.step === 1) {
        return {
          generations: [{
            text: "",
            message: new AIMessage({
              content: "",
              tool_calls: [{ id: "t1", name: "task", args: { description: "处理 A", subagent_type: "worker" } }],
            }),
          }],
        };
      }
      return { generations: [{ text: "done", message: new AIMessage("done") }] };
    }
  }
  class FailWorker extends BaseChatModel {
    constructor() {
      super({});
    }
    _llmType() {
      return "worker";
    }
    bindTools() {
      return this;
    }
    async _generate(): Promise<never> {
      bump("worker");
      throw new Error("worker 内部炸了");
    }
  }

  const agent = deepAgent({
    model: new MainModel() as never,
    tools: [],
    middleware: [modelRetryMiddleware({ maxRetries: 2, initialDelayMs: 0 } as never)] as never,
    subagents: [{ name: "worker", description: "干活", model: new FailWorker() as never, tools: [] }] as never,
  });
  try {
    await agent.invoke({ messages: [{ role: "user", content: "hi" }] });
    console.log("  整体没抛（不符合预期）");
  } catch (e) {
    console.log(`  主代理配了 retry → 整体仍抛 ${(e as Error).constructor.name}`);
  }
  console.log(`    主模型调用 ${tally.main ?? 0} 次｜子代理模型调用 ${tally.worker ?? 0} 次（没有重试）`);
}

console.log("  ↳ 结论：跟 Python 一致，子代理不继承主代理中间件。");
console.log("     TS 侧更干脆——Python 至少把异常包成 ToolMessage 还给模型，");
console.log("     TS 是直接 MiddlewareError 抛穿整个 invoke。");

/* ---------------------------------------------------------------- *
 * 探针 10：版本与依赖约束
 * ---------------------------------------------------------------- */

section("探针 10：版本锁定要看什么");

{
  const pkg = await import("deepagents/package.json", { with: { type: "json" } }).then((m) => m.default as Record<string, unknown>).catch(() => null);
  const { readFileSync } = await import("node:fs");
  const raw = JSON.parse(readFileSync(new URL("./node_modules/deepagents/package.json", import.meta.url), "utf8")) as {
    version: string;
    peerDependencies?: Record<string, string>;
  };
  console.log(`  deepagents ${raw.version}`);
  console.log(`  peerDependencies:`);
  for (const [k, v] of Object.entries(raw.peerDependencies ?? {})) console.log(`    ${k}: ${v}`);
  if (!pkg) console.log("  （import JSON 方式不可用，已改用 readFileSync）");
}
