/**
 * 第 10 课 · 人机协同与护栏（HITL & Guardrails）实验（TypeScript 版）
 *
 * 对应 playground/10-hitl-lab.py，脚本输出即讲义引用的实测证据。
 * 模型侧经本地 OpenAI 兼容 mock 端点（config/mock-server.mjs 的同一服务）回放固定剧本。
 *
 * 运行（在 playground-ts 目录内）：
 *
 *     npx tsx 10-hitl-lab.ts
 *
 * 设计 4 大板块（与 Python 侧一一对应）：
 * 1. 为什么需要人在环中：中断提案全貌 + approve 全流程 + 直通（不设闸门）对照
 * 2. 中断机制：reject / edit / respond / 批量决策 / 条件中断 / v2 形态 + 无 checkpointer / 流式 / 决策数不匹配
 * 3. 护栏体系：PII 四策略（redact/mask/hash）+ 自定义 detector + apply_to_output
 * 4. 自定义护栏：before_agent 拦截 + after_agent 输出审查（确定性 + 模型审查双版本）
 *
 * TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *   - 装饰器式（@before_agent / @after_agent）→ createMiddleware({ beforeAgent / afterAgent: { canJumpTo, hook } }) 工厂（无装饰器）
 *   - 类式（HumanInTheLoopMiddleware / PIIMiddleware）→ humanInTheLoopMiddleware / piiMiddleware 工厂函数
 *   - 参数驼峰化：interrupt_on → interruptOn、allowed_decisions → allowedDecisions、apply_to_input → applyToInput、apply_to_output → applyToOutput
 *   - 决策编辑动作：edited_action → editedAction
 *   - 中断输出统一为 dict（result.__interrupt__），TS 无 Python 侧 v2 的 .interrupts 对象形态（TS 的 version 是图结构版本，HITL 返回形态一致）
 *   - 决策恢复：new Command({ resume: { decisions } })，Command 来自 @langchain/langgraph
 */
import * as z from "zod";
import dotenv from "dotenv";
import {
  tool,
  createAgent,
  createMiddleware,
  initChatModel,
  humanInTheLoopMiddleware,
  piiMiddleware,
  type ToolCallRequest,
} from "langchain";
import { MemorySaver, Command } from "@langchain/langgraph";

dotenv.config({ path: [".env", "../playground/.env"] });

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: process.env.BAILIAN_API_KEY,
  baseUrl: process.env.BAILIAN_BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
  modelKwargs: { enable_thinking: false },
});

const EXECUTED: Array<[string, ...unknown[]]> = []; // 副作用账本：工具真正执行时才记账

function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function brief(content: unknown, limit = 110): string {
  const text = content == null ? "" : String(content);
  return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

function showChain(msgs: any[], limit = 80): void {
  msgs.forEach((m, i) => {
    const t: string = typeof m.getType === "function" ? m.getType() : (m.type ?? m.constructor?.name);
    if (t === "ai" && (m.tool_calls?.length || typeof m.tool_calls === "string")) {
      let calls = m.tool_calls;
      if (typeof calls === "string") calls = JSON.parse(calls);
      const seg = Array.isArray(calls)
        ? calls.map((tc: any) => `${tc.name}(${JSON.stringify(tc.args)})`).join("; ")
        : brief(calls, 120);
      console.log(`    [${i}] ai → 调用工具: ${seg}`);
    } else {
      console.log(`    [${i}] ${t}: ${brief(m.content, limit)}`);
    }
  });
}

// 顺序执行机制：把所有实验按声明顺序串起来（避免并发下共享 EXECUTED 账本计数失真）
const __seq: Array<() => Promise<void>> = [];
function exp(label: string, fn: () => Promise<void> | void) {
  console.log(`\n-- ${label} --`);
  __seq.push(async () => {
    try {
      await fn();
    } catch (e: any) {
      console.log(`  [失败] ${e?.constructor?.name}: ${String(e).slice(0, 300)}`);
    }
  });
}
async function runSeq(): Promise<void> {
  for (const step of __seq) await step();
}

// ---------------- 工具集 ----------------

const sendEmail = tool(({ recipient, subject }: { recipient: string; subject: string }) => {
  EXECUTED.push(["send_email", recipient, subject]);
  return `邮件已发送至 ${recipient}，主题：${subject}`;
}, {
  name: "send_email",
  description: "给指定收件人发送邮件。",
  schema: z.object({ recipient: z.string(), subject: z.string() }),
});

const readInbox = tool(() => {
  EXECUTED.push(["read_inbox"]);
  return "收件箱：3 封新邮件";
}, {
  name: "read_inbox",
  description: "读取收件箱。",
  schema: z.object({}),
});

const deleteRecords = tool(({ days }: { days: number }) => {
  EXECUTED.push(["delete_records", days]);
  return `已删除 ${days} 天前的记录`;
}, {
  name: "delete_records",
  description: "删除指定天数之前的旧记录。",
  schema: z.object({ days: z.number() }),
});

const askUser = tool(({ question }: { question: string }) => {
  EXECUTED.push(["ask_user-real-exec", question]);
  return "（本实现不应被执行）";
}, {
  name: "ask_user",
  description: "向用户提问以澄清需求（真实实现不应被执行——由人工代答）。",
  schema: z.object({ question: z.string() }),
});

function makeEmailAgent() {
  return createAgent({
    model,
    tools: [sendEmail, readInbox],
    middleware: [
      humanInTheLoopMiddleware({
        interruptOn: {
          send_email: { allowedDecisions: ["approve", "edit", "reject"] },
          read_inbox: false,
        },
        descriptionPrefix: "工具执行待审批",
      }),
    ],
    checkpointer: new MemorySaver(),
  });
}

// 读取中断提案（HITLRequest）的自定义类型
type HITLDecision = { type: string; [k: string]: unknown };

// ============================================================
section("1. 为什么需要人在环中");
// ============================================================

exp("1a. 中断提案全貌 + approve（工具先冻结、批准后执行）", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-1a" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "给 alice@corp.com 发一封邮件，主题是'周会提醒'。" }] },
    cfg,
  );
  const intr = r.__interrupt__ as any[];
  console.log("  返回 keys:", Object.keys(r)); // 含 __interrupt__
  console.log("  __interrupt__ 数量:", intr?.length);
  const v = intr?.[0]?.value ?? {};
  console.log("  ── 中断提案（HITLRequest）──");
  for (const ar of v.actionRequests ?? []) {
    console.log(`    action_request: name=${ar.name}`);
    console.log(`      args=${JSON.stringify(ar.args)}`);
    console.log(`      description=${brief(ar.description, 100)}`);
  }
  for (const rc of v.reviewConfigs ?? []) {
    console.log(`    review_config: actionName=${rc.actionName}, allowedDecisions=${JSON.stringify(rc.allowedDecisions)}`);
  }
  console.log("  工具此刻被调用过吗:", EXECUTED.length > n0, "（应为 false——等审批）");

  const r2: any = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), cfg);
  console.log("  approve 后工具执行账本:", JSON.stringify(EXECUTED.slice(n0)));
  console.log("  最终回答:", brief(r2.messages?.at(-1)?.content, 90));
  showChain(r2.messages, 85);
});

exp("1b. 判定标准：不设闸门的操作直接执行（对照）", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-1b" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "帮我看一下收件箱有几封新邮件。" }] },
    cfg,
  );
  console.log("  是否被中断:", "__interrupt__" in r, "（应为 false——read_inbox 未设闸门）");
  console.log("  工具执行账本:", JSON.stringify(EXECUTED.slice(n0)));
  console.log("  最终回答:", brief(r.messages?.at(-1)?.content, 90));
});

// ============================================================
section("2. 中断机制");
// ============================================================

exp("2a. reject：拒绝 + 理由（错误回执、工具不执行）", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-2a" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "给 spam-list@corp.com 发一封邮件，主题是'广告'。发完后告诉我结果。" }] },
    cfg,
  );
  console.log("  中断提案 args:", JSON.stringify(r.__interrupt__?.[0]?.value?.actionRequests?.[0]?.args));
  const r2: any = await agent.invoke(
    new Command({ resume: { decisions: [{ type: "reject", message: "公司政策不允许向外部列表群发。" }] } }),
    cfg,
  );
  console.log("  reject 后工具被调用过吗:", EXECUTED.length > n0, "（应为 false）");
  showChain(r2.messages, 120);
  console.log("  最终回答:", brief(r2.messages?.at(-1)?.content, 130));
});

exp("2b. edit：改参数后批准（执行的是改后的参数）", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-2b" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "给 charlie@corp.com 发一封邮件，主题是'草稿'。完成后告诉我结果。" }] },
    cfg,
  );
  console.log("  原始提案 args:", JSON.stringify(r.__interrupt__?.[0]?.value?.actionRequests?.[0]?.args));
  const r2: any = await agent.invoke(
    new Command({
      resume: {
        decisions: [{
          type: "edit",
          editedAction: { name: "send_email", args: { recipient: "dave@corp.com", subject: "修改后的主题" } },
        }],
      },
    }),
    cfg,
  );
  console.log("  edit 后执行账本（应为改后参数）:", JSON.stringify(EXECUTED.slice(n0)));
  showChain(r2.messages.slice(-4), 120);
  console.log("  最终回答:", brief(r2.messages?.at(-1)?.content, 130));
});

exp("2c. respond：人工代答（ask_user 模式，真实实现不执行）", async () => {
  const agent = createAgent({
    model,
    tools: [askUser],
    middleware: [
      humanInTheLoopMiddleware({
        interruptOn: { ask_user: { allowedDecisions: ["respond"] } },
      }),
    ],
    checkpointer: new MemorySaver(),
  });
  const cfg = { configurable: { thread_id: "l10-2c" } };
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "帮我订一张机票，具体信息你可以问我。请先问我缺少哪些信息。" }] },
    cfg,
  );
  console.log("  中断提案（ask_user 提问）:", brief(r.__interrupt__?.[0]?.value?.actionRequests?.[0]?.args, 130));
  const n0 = EXECUTED.length;
  const r2: any = await agent.invoke(
    new Command({ resume: { decisions: [{ type: "respond", message: "下周三，北京到上海，经济舱。" }] } }),
    cfg,
  );
  console.log("  ask_user 真实实现被调用吗:", EXECUTED.length > n0, "（应为 false——人工代答）");
  showChain(r2.messages.slice(-4), 120);
  console.log("  最终回答:", brief(r2.messages?.at(-1)?.content, 130));
});

exp("2d. 批量决策：动作顺序对齐", async () => {
  const agent = createAgent({
    model,
    tools: [sendEmail],
    middleware: [
      humanInTheLoopMiddleware({
        interruptOn: {
          send_email: { allowedDecisions: ["approve", "reject"] },
        },
      }),
    ],
    checkpointer: new MemorySaver(),
  });
  const cfg = { configurable: { thread_id: "l10-2d" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "请同时给 alice@corp.com 和 bob@corp.com 各发一封主题为'批量邮件'的邮件，两封都要发。" }] },
    cfg,
  );
  const actions: Array<{ name: string; args: any }> = r.__interrupt__?.[0]?.value?.actionRequests ?? [];
  console.log("  中断中的动作顺序:", JSON.stringify(actions.map((a) => `${a.name}:${a.args?.recipient}`)));
  console.log("  allowed_decisions:", JSON.stringify(r.__interrupt__?.[0]?.value?.reviewConfigs?.[0]?.allowedDecisions));
  // 按动作顺序动态生成决策：alice→approve、bob→reject（"决策与动作顺序对齐"的演示）
  const decisions: HITLDecision[] = [];
  for (const a of actions) {
    if ((a.args as any)?.recipient === "bob@corp.com") {
      decisions.push({ type: "reject", message: "bob 本周不在审批名单，先不发。" });
    } else {
      decisions.push({ type: "approve" });
    }
  }
  console.log("  按顺序生成的决策:", JSON.stringify(decisions.map((d) => d.type)));
  const r2: any = await agent.invoke(new Command({ resume: { decisions } }), cfg);
  console.log("  执行账本:", JSON.stringify(EXECUTED.slice(n0)));
  console.log("  最终回答:", brief(r2.messages?.at(-1)?.content, 130));
  // TS 差异：当批次内存在 reject 时，同批次的 approve/edit 会被丢弃、模型被重新调用（ledger 里被拒与被丢都不执行）
  console.log("  （TS 差异：批次内含 reject 时，同批 approve 也会被丢弃，模型重调继续）");
});

exp("2e. 条件中断：when 谓词直通（内部域名不打扰审批人）", async () => {
  const onlyExternal = (request: ToolCallRequest) => {
    const recipient = String((request.toolCall.args as any)?.recipient ?? "");
    return !recipient.endsWith("@internal.com");
  };
  const agent = createAgent({
    model,
    tools: [sendEmail],
    middleware: [
      humanInTheLoopMiddleware({
        interruptOn: {
          send_email: { allowedDecisions: ["approve", "reject"], when: onlyExternal },
        },
      }),
    ],
    checkpointer: new MemorySaver(),
  });
  const cfg = { configurable: { thread_id: "l10-2e" } };
  const n0 = EXECUTED.length;
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "给 teammate@internal.com 发一封邮件，主题是'内部同步'。请直接发送。" }] },
    cfg,
  );
  console.log("  是否被中断:", "__interrupt__" in r, "（应为 false——when 返回 false 直通）");
  console.log("  执行账本:", JSON.stringify(EXECUTED.slice(n0)));
  console.log("  最终回答:", brief(r.messages?.at(-1)?.content, 80));
});

exp("2f. v2 形态 + 无 checkpointer 报错", async () => {
  console.log("  【v1/v2 说明】Python 侧 v1→dict、v2→GraphOutput；TS 侧 createAgent 的 version 是图结构版本，" +
              "HITL 返回形态统一为 dict（result.__interrupt__），两种 version 下访问方式一致。");
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-2f" } };
  const r: any = await agent.invoke(
    { messages: [{ role: "user", content: "给 v2test@corp.com 发一封邮件，主题是'v2 形态'。" }] },
    cfg,
  );
  console.log("  【v1/v2】返回是 dict，__interrupt__ 数量:", r.__interrupt__?.length);
  console.log("  【v1/v2】value keys:", JSON.stringify(Object.keys(r.__interrupt__?.[0]?.value ?? {})));
  const r2: any = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), cfg);
  console.log("  恢复后最终回答:", brief(r2.messages?.at(-1)?.content, 80));

// 无 checkpointer：Python 侧中断依赖检查点落盘 → 首次中断即报错；TS 侧实测无 checkpointer 时首次 invoke 不报错（返回内存态 __interrupt__），仅在 resume 恢复时才需要 checkpointer/thread_id
  const agentNocp = createAgent({
    model,
    tools: [sendEmail],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { send_email: true } })],
  });
  try {
    const r3: any = await agentNocp.invoke(
      { messages: [{ role: "user", content: "给 x@corp.com 发一封邮件，主题是'无检查点'。" }] },
      { configurable: { thread_id: "l10-2f-nocp" } },
    );
    console.log("  无 checkpointer 首次中断返回 __interrupt__ 数量:", r3.__interrupt__?.length);
    console.log("  （TS 差异：无 checkpointer 首次 invoke 不报错，恢复时才需要 thread_id）");
  } catch (e: any) {
    console.log(`  无 checkpointer 报错类型: ${e?.constructor?.name}`);
    console.log(`  报错原文: ${brief(String(e), 200)}`);
  }
});

exp("2g. 流式配合：中断前文本流 + 恢复后继续", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-2g" } };
// step 1：发起请求，收集中断前文本流（TS 的 streamEvents 返回带 .messages / .text 投影）
const step1: any = await agent.streamEvents(
    { messages: [{ role: "user", content: "先简短说明你打算做什么，然后给 eve@corp.com 发一封主题为'流式测试'的邮件。" }] } as any,
    { ...cfg, version: "v3" } as any,
  );
  let text1 = "";
  for await (const message of step1.messages) {
    if (message.text) for await (const token of message.text) text1 += token;
  }
  console.log("  中断前累计文本:", brief(text1, 100));
  console.log("  stream.interrupted:", step1.interrupted);
  if (step1.interrupted) {
    console.log("  interrupts[0] 动作:", step1.interrupts?.[0]?.value?.actionRequests?.[0]?.name);
  }

  // 恢复：approve
const step2: any = await agent.streamEvents(new Command({ resume: { decisions: [{ type: "approve" }] } }) as any, {
    ...cfg,
    version: "v3",
  } as any);
  let text2 = "";
  for await (const message of step2.messages) {
    if (message.text) for await (const token of message.text) text2 += token;
  }
  console.log("  恢复后文本:", brief(text2, 100));
  console.log("  恢复后 stream.interrupted:", step2.interrupted);
});

exp("2h. 决策数量不匹配（错误复现）", async () => {
  const agent = makeEmailAgent();
  const cfg = { configurable: { thread_id: "l10-2h" } };
  await agent.invoke(
    { messages: [{ role: "user", content: "给 count@corp.com 发一封邮件，主题是'数量核对'。" }] },
    cfg,
  );
  try {
    await agent.invoke(
      new Command({
        resume: { decisions: [{ type: "approve" }, { type: "reject" }] }, // 多给了一个
      }),
      cfg,
    );
    console.log("  未报错（与预期不符）");
  } catch (e: any) {
    console.log(`  报错类型: ${e?.constructor?.name}`);
    console.log(`  报错原文: ${brief(String(e), 160)}`);
  }
});

// ============================================================
section("3. 护栏体系：内置护栏（PII 检测）");
// ============================================================

exp("3a. PII 三策略输入侧对照（redact/mask/hash，写入状态）", async () => {
  const agent = createAgent({
    model,
    tools: [],
    middleware: [
      piiMiddleware("email", { strategy: "redact", applyToInput: true }),
      piiMiddleware("credit_card", { strategy: "mask", applyToInput: true }),
      piiMiddleware("ip", { strategy: "hash", applyToInput: true }),
    ],
  });
  const userText = "我的邮箱是 john.doe@example.com，卡号 5105-1051-0510-5100，服务器 IP 是 192.168.1.100。请原样复述你收到的这三项内容。";
  const r: any = await agent.invoke({ messages: [{ role: "user", content: userText }] });
  console.log("  原始输入:", brief(userText, 130));
  console.log("  状态里的 user 消息:", brief(r.messages?.[0]?.content, 130));
  console.log("  （对照：脱敏结果已写入状态——不是瞬时视图）");
  console.log("  模型实际看到的（它就复述这个）:", brief(r.messages?.at(-1)?.content, 130));
});

exp("3b. PII block 拒收 + 自定义 detector", async () => {
  // block：api_key 检测到即拒（抛错，不调用模型）
  const agentBlock = createAgent({
    model,
    tools: [],
    middleware: [
      piiMiddleware("api_key", {
        detector: "sk-[a-zA-Z0-9]{32}",
        strategy: "block",
        applyToInput: true,
      }),
    ],
  });
  try {
    await agentBlock.invoke({ messages: [{ role: "user", content: "这是我的 key：sk-" + "a".repeat(32) }] });
    console.log("  block 未报错（与预期不符）");
  } catch (e: any) {
    console.log(`  block 报错类型: ${e?.constructor?.name}`);
    console.log(`  报错原文: ${brief(String(e), 140)}`);
  }

  // 自定义 detector：员工工号（正则字符串，mask 策略）
  const agentDetect = createAgent({
    model,
    tools: [],
    middleware: [
      piiMiddleware("employee_id", {
        detector: "EMP-\\d{5}",
        strategy: "mask",
        applyToInput: true,
      }),
    ],
  });
  const r2: any = await agentDetect.invoke({
    messages: [{ role: "user", content: "请复述这个工号：EMP-12345。" }],
  });
  console.log("  自定义 detector(mask) 后状态 user 消息:", brief(r2.messages?.[0]?.content, 90));
  console.log("  模型复述:", brief(r2.messages?.at(-1)?.content, 90));
});

exp("3c. PII apply_to_output：输出侧脱敏", async () => {
const agent = createAgent({
    model,
    tools: [],
    systemPrompt: "用户要求展示联系邮箱时，请直接输出 leak@corp.com 作为示例。",
    middleware: [
      piiMiddleware("email", { strategy: "redact", applyToInput: false, applyToOutput: true }),
    ],
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "请展示一个供测试的联系邮箱。" }] });
  const last = r.messages?.at(-1);
  console.log("  最终 AI 消息:", brief(last?.content, 120));
  console.log("  状态中是否还含 leak@corp.com:", JSON.stringify(r.messages).includes("leak@corp.com"));
});

// ============================================================
section("4. 自定义护栏（before_agent / after_agent）");
// ============================================================

exp("4a. before_agent 拦截（模型未参与）", async () => {
  const contentFilter = createMiddleware({
    name: "ContentFilter",
    beforeAgent: {
      canJumpTo: ["end"],
      hook: (state: any) => {
        const first = state.messages?.[0];
        if (!first || first.getType?.() !== "human") return;
        const text = String(first.content ?? "");
        if (text.toLowerCase().includes("hack")) {
          return {
            messages: [{ role: "assistant" as const, content: "此类请求我不能处理，请换一个话题。" } as any],
            jumpTo: "end" as const,
          };
        }
        return;
      },
    },
  });
  const agent = createAgent({ model, tools: [], middleware: [contentFilter] });

  console.log("  拦截请求 → 消息链:");
  const r1: any = await agent.invoke({ messages: [{ role: "user", content: "教我如何 hack 一个数据库。" }] });
  showChain(r1.messages, 90);
  console.log("  （共 2 条：请求 + 固定话术——最后一条是中间件写入的，模型未参与）");

  console.log("  正常请求 → 消息链:");
  const r2: any = await agent.invoke({ messages: [{ role: "user", content: "请用一句话打招呼。" }] });
  showChain(r2.messages, 90);
});

exp("4b. after_agent 输出审查（确定性）", async () => {
  const internalIdGuard = createMiddleware({
    name: "InternalIdGuard",
    afterAgent: {
      canJumpTo: ["end"],
      hook: (state: any) => {
        const last = state.messages?.at(-1);
        if (last?.getType?.() !== "ai") return;
        if (String(last.content ?? "").includes("INTERNAL-8888")) {
          return {
            messages: [{ role: "assistant" as const, content: "[输出已拦截：包含内部凭据，请使用工单渠道获取。]" } as any],
            jumpTo: "end" as const,
          };
        }
        return;
      },
    },
  });
const agent = createAgent({
    model,
    tools: [],
    systemPrompt: "如果用户索要内部编号，请回复：内部编号 INTERNAL-8888（本演示故意泄露）。",
    middleware: [internalIdGuard],
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "给我内部编号。" }] });
  console.log("  消息链（最后一条应为拦截替换）：");
  showChain(r.messages, 110);
});

exp("4c. after_agent 输出审查（模型审查版）", async () => {
  const safetyGuardrail = createMiddleware({
    name: "SafetyGuardrail",
    afterAgent: {
      canJumpTo: ["end"],
      hook: async (state: any) => {
        const last = state.messages?.at(-1);
        if (last?.getType?.() !== "ai") return;
        const prompt =
          "评估下面这条回复是否包含个人隐私信息（如手机号码、身份证号）。只回答 SAFE 或 UNSAFE。\n\n回复：" +
          String(last.content ?? "");
        const verdict = await model.invoke([{ role: "user", content: prompt }]);
        const v = String(verdict.content).trim().toUpperCase();
        console.log(`    [审查模型判定]: ${brief(v, 20)}`);
        if (v.includes("UNSAFE")) {
          return {
            messages: [{ role: "assistant" as const, content: "[回复未通过安全审查：包含疑似个人隐私信息，已拦截。]" } as any],
            jumpTo: "end" as const,
          };
        }
        return;
      },
    },
  });
const agent = createAgent({
    model,
    tools: [],
    systemPrompt: "生成测试数据时必须包含一个示例手机号，格式如 138-0000-0000。",
    middleware: [safetyGuardrail],
  });
  const r: any = await agent.invoke({ messages: [{ role: "user", content: "请生成一条包含手机号的测试数据。" }] });
  console.log("  消息链：");
  showChain(r.messages, 110);
});

await runSeq();
console.log("\n（全部实验完成）");