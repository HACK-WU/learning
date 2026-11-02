/**
 * 课程 4.1 机制验证脚本（一）：定义面 + 编译面 + 状态通道 + 策略层
 *
 * 一个脚本覆盖课 4 / 课 5 / 课 6 / 课 7 四条机制：
 *   ① 定义是纯数据（可序列化、可冻结、校验返回清单不抛异常）
 *   ② 编译是翻译（定义改动如何体现在编译产物上；不缓存意味着每次重编）
 *   ③ 通道各自归约（追加 vs 取新；同通道并发写的行为）
 *   ④ 策略两层拦截（中间件拦"模型越权"、执行器拦"直调"）
 *
 * 运行：npm run core   输出即为课文「4.1 机制验证」可引用的真实输出。
 */
import { StateGraph, Annotation, START, END, interrupt, Command } from "@langchain/langgraph";
import { z } from "zod";

const line = (t: string) => console.log(t);

// ───────────────────────── 课 4：声明式定义 ─────────────────────────

const AgentDefinitionSchema = z.object({
  key: z.string().min(1),
  name: z.string().min(1),
  version: z.number().int().positive(),
  prompt: z.string(),
  model: z.object({ provider: z.string(), name: z.string().optional() }),
  tools: z.array(z.string()),
  policies: z.object({ requireApprovalFor: z.array(z.string()) }).default({ requireApprovalFor: [] }),
});

type AgentDefinition = z.infer<typeof AgentDefinitionSchema>;

/** 定义 → 运行时视图：冻结 + 浅拷贝数组，运行时改不动定义 */
function toRuntime(def: AgentDefinition): Readonly<AgentDefinition> {
  return Object.freeze({ ...def, tools: [...def.tools] });
}

/** 校验返回"问题清单"而非抛异常：一次报全 */
function validateDefinition(raw: unknown): string[] {
  const parsed = AgentDefinitionSchema.safeParse(raw);
  if (!parsed.success) {
    return parsed.error.issues.map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`);
  }
  const def = parsed.data;
  const problems: string[] = [];
  for (const t of def.policies.requireApprovalFor) {
    if (!def.tools.includes(t)) problems.push(`审批策略引用了未声明的工具：「${t}」`);
  }
  return problems;
}

line("=== 课 4：声明式定义 ===");

const goodDef = AgentDefinitionSchema.parse({
  key: "db-change",
  name: "数据库变更助手",
  version: 1,
  prompt: "你是数据库变更助手",
  model: { provider: "fake" },
  tools: ["querySql", "executeSql"],
  policies: { requireApprovalFor: ["executeSql"] },
});

// ① 定义是数据：能序列化、能存库、能发消息
line("① 定义可序列化: " + JSON.stringify(JSON.parse(JSON.stringify(goodDef))).length + " 字节 JSON，不报错");

// ② 定义与运行时分离：冻结后写入静默失败（非严格模式）或抛错（严格模式）
const runtimeDef = toRuntime(goodDef);
line("② toRuntime 冻结: isFrozen=" + Object.isFrozen(runtimeDef) + " | 数组是同引用=" + (runtimeDef.tools === goodDef.tools));
line("   运行时副本改 tools 不影响定义: " + (() => {
  (runtimeDef.tools as string[]).push("__hack__");
  return !goodDef.tools.includes("__hack__");
})());

// ③ 校验返回清单：一次拿到多个问题，而不是"修一个报下一个"
const badProblems = validateDefinition({
  key: "",
  name: "x",
  version: 0,
  tools: ["querySql"],
  policies: { requireApprovalFor: ["executeSql"] },
});
line("③ 非法定义一次报出 " + badProblems.length + " 条问题：");
for (const p of badProblems) line("   - " + p);

// ④ 校验查不到的东西：跨定义的语义冲突（本例：审批名单指向不存在的工具，schema 层查不出）
line("④ 语义校验（schema 通过但业务不成立）: " + validateDefinition({
  ...goodDef,
  policies: { requireApprovalFor: ["dropTable"] },
}).join(" | "));

// ───────────────────────── 课 5：编译器 ─────────────────────────

line("");
line("=== 课 5：编译即翻译 ===");

const S = Annotation.Root({
  messages: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

/** 编译：把定义翻译成图。钩子数量决定节点数量。 */
function compile(def: AgentDefinition, hooks: string[]) {
  let g: any = new StateGraph(S).addNode("model", async () => ({}));
  for (const h of hooks) g = g.addNode(h, async () => ({}));
  // 顺序：钩子 → model → END
  const chain = [...hooks, "model"];
  g = g.addEdge(START, chain[0]);
  for (let i = 0; i < chain.length - 1; i++) g = g.addEdge(chain[i], chain[i + 1]);
  g = g.addEdge(chain[chain.length - 1], END);
  return g.compile();
}

const g0 = compile(goodDef, []);
const g2 = compile(goodDef, ["injectContext", "guardOutput"]);
line("① 钩子变节点: 0 钩子→" + Object.keys((g0 as any).nodes).length + " 节点, 2 钩子→" + Object.keys((g2 as any).nodes).length + " 节点");

// ② 编译不改定义：同一份定义编译两次，定义对象不变
const before = JSON.stringify(goodDef);
compile(goodDef, ["a"]);
compile(goodDef, ["b", "c"]);
line("② 编译是纯翻译: 编译两次后定义未变=" + (JSON.stringify(goodDef) === before));

// ③ 不缓存：每次 compile 产出新图实例
line("③ 不缓存: 两次 compile 是同一实例=" + (compile(goodDef, []) === compile(goodDef, [])) + "（false = 每次重编）");

// ───────────────────────── 课 6：状态通道 ─────────────────────────

line("");
line("=== 课 6：状态通道 ===");

const Multi = Annotation.Root({
  messages: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  title: Annotation<string>({ reducer: (_a, b) => b, default: () => "" }),
  result: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

// ① 两种归约语义并存：messages 追加、title 取新
const g6 = new StateGraph(Multi)
  .addNode("w1", async () => ({ messages: ["第一句"], title: "旧标题", result: ["r1"] }))
  .addNode("w2", async () => ({ messages: ["第二句"], title: "新标题", result: ["r2"] }))
  .addEdge(START, "w1")
  .addEdge("w1", "w2")
  .addEdge("w2", END)
  .compile();

const r6: any = await g6.invoke({});
line("① messages（追加）→ " + JSON.stringify(r6.messages));
line("   title（取新）→ " + JSON.stringify(r6.title));
line("   result（追加）→ " + JSON.stringify(r6.result));

// ② 并发写同一通道：追加语义不丢数据，取新语义只留一个（后写胜）
const Parallel = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  winner: Annotation<string>({ reducer: (_a, b) => b, default: () => "" }),
});
const g6b = new StateGraph(Parallel)
  .addNode("a", async () => ({ log: ["a"], winner: "a" }))
  .addNode("b", async () => ({ log: ["b"], winner: "b" }))
  .addEdge(START, "a")
  .addEdge(START, "b")
  .addEdge("a", END)
  .addEdge("b", END)
  .compile();
const r6b: any = await g6b.invoke({});
line("② 并发写: log=" + JSON.stringify(r6b.log.sort()) + "（两条都在）| winner=" + JSON.stringify(r6b.winner) + "（只留一个）");

// ③ 环境信息不进持久化状态：用"读时投影"把只读环境拼进提示词参数
function projectParams(state: { messages: string[] }, env: { tenant: string }) {
  return { messages: state.messages.join("\n"), tenant: env.tenant };
}
const projected = projectParams({ messages: ["hi"] }, { tenant: "t-1" });
line("③ 读时投影: 状态里没有 tenant=" + !("tenant" in { messages: ["hi"] }) + "，投影后参数里有=" + ("tenant" in projected));

// ───────────────────────── 课 7：中间件策略层 ─────────────────────────

line("");
line("=== 课 7：中间件策略层（洋葱顺序 + 两层拦截）===");

type Hook = (next: () => Promise<string>) => Promise<string>;

/** 洋葱：进正序、出反序。三个策略包住同一次工具调用。 */
async function runOnion(strategies: { name: string; hook: Hook }[], core: () => Promise<string>) {
  const trace: string[] = [];
  let fn = core;
  for (let i = strategies.length - 1; i >= 0; i--) {
    const s = strategies[i];
    const inner = fn;
    fn = async () => {
      trace.push(`${s.name}:enter`);
      const out = await s.hook(inner);
      trace.push(`${s.name}:exit`);
      return out;
    };
  }
  const out = await fn();
  return { trace, out };
}

const r7 = await runOnion(
  [
    { name: "A", hook: async (n) => await n() },
    { name: "B", hook: async (n) => await n() },
    { name: "C", hook: async (n) => await n() },
  ],
  async () => "core"
);
line("① 洋葱顺序: " + JSON.stringify(r7.trace));

// ② 中间件层能拦住"模型主动越权"（返回拒绝，不进执行器）
const denied = await runOnion(
  [{ name: "deny", hook: async () => "已拒绝：策略不允许写系统目录" }],
  async () => { throw new Error("执行器不该被调用"); }
);
line("② 中间件拦截: " + denied.out + "（执行器未被调用）");

// ③ 执行器内部授权：绕过中间件直接调，仍然被拦
class GuardedFs {
  constructor(private allowedOps: Set<string>) {}
  async write(path: string) {
    if (!this.allowedOps.has("write")) throw new Error(`PermissionError: 未授权 write（${path}）`);
    return "ok";
  }
}
const fs = new GuardedFs(new Set(["read"]));
try {
  await fs.write("/data/x.txt");
  line("③ 执行器拦截: 未被拦住 ❌");
} catch (e) {
  line("③ 执行器拦截（直调也过闸）: " + (e as Error).message);
}

// ④ 静态清单 vs 运行时实例：清单是上限，实例按上下文裁剪
const declaredTools = ["read_file", "write_file", "delete_file"];
function createMiddleware(ctx: { allowOps: string[] }) {
  const map: Record<string, string> = { read: "read_file", write: "write_file", delete: "delete_file" };
  return { tools: ctx.allowOps.map((op) => map[op]).filter(Boolean) };
}
const inst = createMiddleware({ allowOps: ["read"] });
line("④ 静态清单 " + declaredTools.length + " 个，实际暴露 " + inst.tools.length + " 个: " + JSON.stringify(inst.tools));

// ───────────────────────── 课 10 预告：interrupt 形状（供课文引用） ─────────────────────────

line("");
line("=== 附：interrupt 的返回形状（课 10 用）===");

const ApprovalState = Annotation.Root({
  messages: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  approved: Annotation<boolean>({ reducer: (_a, b) => b, default: () => false }),
});

const executionLog: string[] = [];

const g10 = new StateGraph(ApprovalState)
  .addNode("approve", async () => {
    executionLog.push("节点进入（每次恢复都会重跑这一行）");
    const decision = interrupt({ kind: "approval_required", tool: "executeSql" });
    executionLog.push(`拿到决策: ${String(decision)}`);
    return { approved: String(decision) === "approve" };
  })
  .addEdge(START, "approve")
  .addEdge("approve", END)
  .compile({ checkpointer: new (await import("@langchain/langgraph")).MemorySaver() });

const cfg = { configurable: { thread_id: "demo-1" } };
const first: any = await g10.invoke({ messages: ["加列"] }, cfg);
line("① 首次 invoke 返回 __interrupt__: " + JSON.stringify(first.__interrupt__?.map((i: any) => ({ id: i.id?.slice(0, 8), value: i.value }))));
line("   挂起后 next 非空: " + JSON.stringify((await g10.getState(cfg)).next));

const resumed: any = await g10.invoke(new Command({ resume: "approve" }), cfg);
line("② resume 后 approved=" + resumed.approved + " | 节点执行轨迹=" + JSON.stringify(executionLog));
line("③ 结论: 节点进入被记录了 " + executionLog.filter((l) => l.startsWith("节点进入")).length + " 次（= 首次 + 恢复次数），interrupt 之前的代码确实重跑了");
