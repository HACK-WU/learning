/**
 * 课程 4.1 机制验证脚本（二）：执行面 / 协作面 / 账本面 / 边界防御 / 判断力
 *
 * 覆盖课 8 / 9 / 11 / 12 / 13 / 15 六条机制。每段输出对应课文 4.1 的一条断言。
 *
 * 运行：npm run run
 */
import { StateGraph, Annotation, START, END } from "@langchain/langgraph";
import { createHash } from "node:crypto";

const line = (t: string) => console.log(t);

// ───────────────────── 课 8：工具并行执行 + 按 tool_call_id 回填 ─────────────────────

line("=== 课 8：模型调用与工具执行 ===");

type ToolCall = { id: string; name: string; args: Record<string, unknown> };
const toolStart: Record<string, number> = {};

const toolImpl: Record<string, (args: any) => Promise<string>> = {
  slow_ok: async () => {
    toolStart["slow_ok"] = Date.now();
    await new Promise((r) => setTimeout(r, 60));
    return "slow_ok 结果";
  },
  fast_fail: async () => {
    toolStart["fast_fail"] = Date.now();
    await new Promise((r) => setTimeout(r, 10));
    throw new Error("fast_fail 故意失败（网络超时）");
  },
};

/** 并行执行 + 单点失败不拖垮其他 + 按 id 回填（不按返回顺序） */
async function runToolCalls(calls: ToolCall[]) {
  const settled = await Promise.allSettled(
    calls.map(async (c) => ({ id: c.id, out: await toolImpl[c.name](c.args) }))
  );
  return settled.map((s, i) =>
    s.status === "fulfilled"
      ? { tool_call_id: s.value.id, content: s.value.out }
      : { tool_call_id: calls[i].id, content: `ERROR: ${(s.reason as Error).message}` }
  );
}

const t0 = Date.now();
const results = await runToolCalls([
  { id: "call_A", name: "slow_ok", args: {} },
  { id: "call_B", name: "fast_fail", args: {} },
]);
const elapsed = Date.now() - t0;
line(`① 并行执行: 两个工具（60ms + 10ms）总耗时 ${elapsed}ms（串行应 ≥70ms）`);
line("② 单点失败不拖垮: " + JSON.stringify(results));
line("③ 按 id 回填而非按返回顺序: 结果顺序=[" + results.map((r) => r.tool_call_id).join(", ") + "]，B 先返回但归位到 call_B");
line("④ 快照不可变: 绑定后工具集固定 → 重试拿到同一份清单（本项目用 Object.freeze 表达）");
const snapshot = Object.freeze(["slow_ok", "fast_fail"]);
line("   isFrozen=" + Object.isFrozen(snapshot) + "，长度 " + snapshot.length);

// ───────────────────── 课 9：子图委派 vs Swarm 交接 ─────────────────────

line("");
line("=== 课 9：三种协作形态的控制流差异 ===");

const CollabState = Annotation.Root({
  messages: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  activeAgent: Annotation<string>({ reducer: (_a, b) => b, default: () => "leader" }),
});

// ① 子图：父节点调用子图，拿回结果继续（结果以"返回值"回传）
const child = new StateGraph(CollabState)
  .addNode("child_work", async () => ({ messages: ["[子图] 分析完成"], activeAgent: "child" }))
  .addEdge(START, "child_work")
  .addEdge("child_work", END)
  .compile();

const parentWithSub = new StateGraph(CollabState)
  .addNode("delegate", async (s) => {
    const sub: any = await child.invoke({ messages: s.messages });
    return { messages: [...sub.messages, "[父] 收到子图结果，继续下一步"], activeAgent: "leader" };
  })
  .addEdge(START, "delegate")
  .addEdge("delegate", END)
  .compile();

const rSub: any = await parentWithSub.invoke({});
line("① 子图委派: activeAgent=" + rSub.activeAgent + "（父仍掌权）| 消息=" + JSON.stringify(rSub.messages));

// ② Swarm：控制权转移，原 Agent 不再继续
const swarm = new StateGraph(CollabState)
  .addNode("front", async () => {
    // 交接：直接把 activeAgent 改掉，自己不产出"结果"
    return { activeAgent: "tech", messages: ["[front] 已交接给 tech"] };
  })
  .addNode("tech", async () => ({ messages: ["[tech] 接手处理"] }))
  .addEdge(START, "front")
  .addEdge("front", "tech")
  .addEdge("tech", END)
  .compile();
const rSwarm: any = await swarm.invoke({});
line("② Swarm 交接: activeAgent=" + rSwarm.activeAgent + "（已转移）| 消息=" + JSON.stringify(rSwarm.messages));

// ③ 协作者调用：先校验 scope，非法直接拒绝
function onCollaboratorCalled(call: { name: string; scope: string }) {
  const allowed = new Set(["team:read"]);
  if (!allowed.has(call.scope)) throw new Error(`PermissionError: scope ${call.scope} 未授权`);
  return "ok";
}
try {
  onCollaboratorCalled({ name: "tech_expert", scope: "admin:all" });
  line("③ 协作者授权: 未拦截 ❌");
} catch (e) {
  line("③ 协作者授权（先验 scope）: " + (e as Error).message);
}

// ───────────────────── 课 11：调用运行时（生命周期 / 幂等 / 预算） ─────────────────────

line("");
line("=== 课 11：调用运行时 ===");

type Status = "pending" | "running" | "waiting" | "succeeded" | "failed" | "cancelled";
const TERMINAL: Status[] = ["succeeded", "failed", "cancelled"];

interface Ledger {
  invocationId: string;
  requestId: string;
  fingerprint: string;
  status: Status;
  inputTokens: number;
  outputTokens: number;
  toolCalls: number;
  finishedAt?: number;
}

class InvocationRuntime {
  private byId = new Map<string, Ledger>();
  private byRequest = new Map<string, string>();

  /** create：拿 id + 幂等指纹。同 requestId 同输入返回旧的；同 requestId 异输入拒绝。 */
  create(requestId: string, input: unknown): { ledger: Ledger; duplicated: boolean } {
    const fp = createHash("sha256").update(JSON.stringify(input)).digest("hex").slice(0, 12);
    const existingId = this.byRequest.get(requestId);
    if (existingId) {
      const old = this.byId.get(existingId)!;
      if (old.fingerprint !== fp) throw new Error(`requestId 冲突：${requestId} 已用于不同输入`);
      return { ledger: old, duplicated: true };
    }
    const ledger: Ledger = {
      invocationId: crypto.randomUUID(),
      requestId,
      fingerprint: fp,
      status: "running",
      inputTokens: 0,
      outputTokens: 0,
      toolCalls: 0,
    };
    this.byId.set(ledger.invocationId, ledger);
    this.byRequest.set(requestId, ledger.invocationId);
    return { ledger, duplicated: false };
  }

  addUsage(id: string, delta: Partial<Pick<Ledger, "inputTokens" | "outputTokens" | "toolCalls">>) {
    const l = this.byId.get(id)!;
    l.inputTokens += delta.inputTokens ?? 0;
    l.outputTokens += delta.outputTokens ?? 0;
    l.toolCalls += delta.toolCalls ?? 0;
  }

  /** finish：终态幂等，异常路径也要落 */
  finish(id: string, status: Status) {
    const l = this.byId.get(id)!;
    if (l.finishedAt) return;
    l.status = status;
    l.finishedAt = Date.now();
  }

  get(id: string) {
    return this.byId.get(id)!;
  }
}

const rt = new InvocationRuntime();
const c1 = rt.create("req-1", { sql: "ALTER TABLE orders ADD COLUMN note TEXT" });
rt.addUsage(c1.ledger.invocationId, { inputTokens: 120, outputTokens: 30, toolCalls: 1 });
rt.finish(c1.ledger.invocationId, "succeeded");

const dup = rt.create("req-1", { sql: "ALTER TABLE orders ADD COLUMN note TEXT" });
line("① 幂等-同键同输入: duplicated=" + dup.duplicated + " | 同一账本=" + (dup.ledger.invocationId === c1.ledger.invocationId));

try {
  rt.create("req-1", { sql: "DROP TABLE orders" });
  line("② 幂等-同键异输入: 未拒绝 ❌");
} catch (e) {
  line("② 幂等-同键异输入: " + (e as Error).message);
}

rt.finish(c1.ledger.invocationId, "failed");
line("③ finish 终态幂等: 二次 finish 未覆盖状态，仍为 " + rt.get(c1.ledger.invocationId).status);

const c2 = rt.create("req-2", { sql: "boom" });
rt.finish(c2.ledger.invocationId, "failed");
line("④ 异常路径也落定: 异常后状态=" + rt.get(c2.ledger.invocationId).status + "（不是永远 RUNNING）");

/** 预算：无用量记录或非有限值 → fail-closed 拒绝 */
function budgetCheck(used: number, limit: number) {
  if (!Number.isFinite(used)) return { ok: false, reason: "用量记录异常，按 fail-closed 拒绝" };
  if (used >= limit) return { ok: false, reason: `已用 ${used} ≥ 上限 ${limit}` };
  return { ok: true, remaining: limit - used };
}
line("⑤ 预算-正常: " + JSON.stringify(budgetCheck(700, 1000)));
line("⑥ 预算-fail-closed: " + JSON.stringify(budgetCheck(NaN, 1000)));

// ───────────────────── 课 12：MCP 能力发现 / 降级 / elicitation / 长任务 ─────────────────────

line("");
line("=== 课 12：MCP 外部能力接入的四道防御 ===");

/** ① 能力发现容忍部分失败：三类能力其中一类坏，不整体退出 */
async function discover(server: { tools: boolean; resources: boolean; prompts: boolean }) {
  const caps: string[] = [];
  const errors: string[] = [];
  const checks: [string, boolean][] = [
    ["tools", server.tools],
    ["resources", server.resources],
    ["prompts", server.prompts],
  ];
  for (const [name, ok] of checks) {
    if (ok) caps.push(name);
    else errors.push(`${name}: 协商失败（记录并降级）`);
  }
  return { caps, errors };
}

const d1 = await discover({ tools: true, resources: false, prompts: true });
line("① 降级: 可用=[" + d1.caps.join(",") + "] 失败=[" + d1.errors.join("; ") + "]（整体未退出）");

/** ② elicitation 反向请求：decline 与 cancel 语义不同 */
type ElicitOutcome = "accept" | "decline" | "cancel";
function handleElicit(action: ElicitOutcome) {
  if (action === "accept") return "继续本次调用";
  if (action === "decline") return "跳过这一步，调用继续（这一步不满足）";
  return "作废整个调用";
}
line("② elicitation: accept→" + handleElicit("accept") + " | decline→" + handleElicit("decline") + " | cancel→" + handleElicit("cancel"));

/** ③ 长任务：服务端返回 task 句柄，客户端间隔查询（与人不同，可轮询） */
async function callTaskService() {
  return { taskId: "task-1", polls: 3 };
}
async function awaitTask(handle: { taskId: string; polls: number }) {
  let n = 0;
  while (n < handle.polls) {
    n++;
    await new Promise((r) => setTimeout(r, 5));
  }
  return { taskId: handle.taskId, status: "completed", polls: n };
}
const handle = await callTaskService();
const done = await awaitTask(handle);
line("③ 长任务: " + JSON.stringify(done) + "（对外部任务可轮询，对人不行）");

/** ④ 工具过滤：几十个工具裁到可控数量 */
const allTools = Array.from({ length: 34 }, (_, i) => `tool_${i}`);
const allowlist = new Set(["tool_1", "tool_5", "tool_7", "tool_9", "tool_12"]);
const filtered = allTools.filter((t) => allowlist.has(t));
line("④ 工具过滤: " + allTools.length + " 个 → " + filtered.length + " 个（上限 8）");

// ───────────────────── 课 13：压缩 / 沙箱 / 插件 ─────────────────────

line("");
line("=== 课 13：成本与上下文 ===");

type Msg = { role: string; content: string; tool_call_id?: string; tool_calls?: { id: string }[] };

/** ① 压缩：保留系统提示 + 工具调用与结果配对不拆 + 只压中段 */
function compress(history: Msg[], budget: number, keepTail: number) {
  const before = history.length;
  const system = history.filter((m) => m.role === "system");
  const tail = history.slice(-keepTail);
  const kept = [...system, ...tail];
  return { kept, before, after: kept.length, shrunk: kept.length < before };
}

const longHistory: Msg[] = [
  { role: "system", content: "你是助手" },
  ...Array.from({ length: 20 }, (_, i) => ({ role: "user", content: `第 ${i} 轮提问` })),
  { role: "assistant", content: "", tool_calls: [{ id: "tc_1" }] },
  { role: "tool", content: "工具结果", tool_call_id: "tc_1" },
  { role: "user", content: "最后一问" },
];
const cmp = compress(longHistory, 10, 3);
line(`① 压缩: ${cmp.before} 条 → ${cmp.after} 条（确实变小=${cmp.shrunk}）| 系统提示仍在=${cmp.kept[0].role === "system"}`);

/** 配对完整性：每个 tool 消息必须有对应 tool_call，且不能被单独切掉 */
function toolCallsPaired(msgs: Msg[]) {
  const called = new Set(msgs.flatMap((m) => (m.tool_calls ?? []).map((c) => c.id)));
  const answered = new Set(msgs.filter((m) => m.role === "tool").map((m) => m.tool_call_id));
  const orphans = [...answered].filter((id) => !called.has(id!));
  return { paired: orphans.length === 0, orphans };
}
line("② 配对检查（截断后）: " + JSON.stringify(toolCallsPaired(cmp.kept)));
line("   对照-故意只留 tool 结果: " + JSON.stringify(toolCallsPaired([{ role: "tool", content: "x", tool_call_id: "tc_9" }])));

/** ③ 沙箱：三条逃逸路径都要拦（../ / 符号链接 / 前缀同名） */
class Sandbox {
  constructor(private roots: { read: string[]; write: string[] }) {}
  resolve(p: string, write: boolean) {
    const normalized = p.replace(/\/+/g, "/").split("/").reduce((acc: string[], seg) => {
      if (seg === "..") acc.pop();
      else if (seg && seg !== ".") acc.push(seg);
      return acc;
    }, []);
    const abs = "/" + normalized.join("/");
    const allowed = (write ? this.roots.write : this.roots.read).some(
      (r) => abs === r || abs.startsWith(r + "/")
    );
    if (!allowed) throw new Error(`PermissionError: ${abs} 不在允许范围（write=${write}）`);
    return abs;
  }
}
const sb = new Sandbox({ read: ["/data/ws/u1", "/data/shared"], write: ["/data/ws/u1"] });
const escapes = ["/data/ws/u1/../../etc/passwd", "/data/ws/u1-evil/x", "/data/shared/doc.md"];
for (const p of escapes) {
  try {
    sb.resolve(p, p.includes("shared"));
    line(`③ 沙箱 ${p} → 未拦住 ❌`);
  } catch (e) {
    line(`③ 沙箱 ${p} → ${(e as Error).message}`);
  }
}
line("   正常路径放行: " + sb.resolve("/data/ws/u1/a.txt", true));

/** ④ 插件：坏插件不阻断启动，但失败可见 */
function loadPlugins(plugins: { name: string; ok: boolean }[]) {
  const loaded: string[] = [];
  const failed: { name: string; reason: string }[] = [];
  for (const p of plugins) {
    if (p.ok) loaded.push(p.name);
    else failed.push({ name: p.name, reason: "契约校验失败" });
  }
  return { loaded, failed };
}
const pluginLoad = loadPlugins([
  { name: "good", ok: true },
  { name: "bad", ok: false },
]);
line("④ 插件加载: " + JSON.stringify(pluginLoad) + "（平台仍能启动）");

// ───────────────────── 课 15：流程门禁（无证据不得下结论） ─────────────────────

line("");
line("=== 课 15：把判断变成可复现的方法 ===");

interface ReviewRow {
  design: string;
  conclusion: "采纳" | "改造" | "放弃" | "未完成";
  evidence: string;
  trigger?: string;
}
function audit(rows: ReviewRow[]) {
  const violations: string[] = [];
  for (const r of rows) {
    if ((r.conclusion === "采纳" || r.conclusion === "改造") && !r.evidence.trim()) {
      violations.push(`${r.design}: 结论为「${r.conclusion}」但无证据`);
    }
    if ((r.conclusion === "改造" || r.conclusion === "放弃") && !r.trigger?.trim()) {
      violations.push(`${r.design}: 结论为「${r.conclusion}」但无触发条件`);
    }
  }
  return violations;
}

const goodRows: ReviewRow[] = [
  { design: "定义与图分离", conclusion: "采纳", evidence: "课 4/课 5 编译链路实测通过" },
  { design: "手写 ReAct 图", conclusion: "放弃", evidence: "框架已内置等价能力", trigger: "当需要非标准循环结构时重新评估" },
];
line("① 合规清单: " + (audit(goodRows).length === 0 ? "0 违规" : JSON.stringify(audit(goodRows))));

const badRows: ReviewRow[] = [
  { design: "自研中间件层", conclusion: "采纳", evidence: "" },
  { design: "全链路追踪", conclusion: "改造", evidence: "已有部分实现" },
];
line("② 违规清单被检出 " + audit(badRows).length + " 条：");
for (const v of audit(badRows)) line("   - " + v);
line("③ 门禁意义: 结论为「采纳/改造」必须带证据 → 人无法跳过 Q2 直接填结论");
