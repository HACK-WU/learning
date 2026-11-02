/**
 * 编译面（compile）· 定义 → 图
 *
 * 知识点覆盖：课 5「编译入口与分支路由」、课 6「通道划分」「reducer 与并发」、
 *            课 7「策略接口」「六个钩子职责」、课 9「子图委派」（本项目不启用）
 *
 * 编译不是"加载配置"，而是"翻译"：把数据翻译成一张可执行的图。
 * 本文件刻意不做图级缓存——每次请求重编，保证行为永远与当前定义一致。
 */
import { StateGraph, Annotation, interrupt, Command, END, START } from "@langchain/langgraph";
import type { AgentDefinition } from "../definition/agent-definition.js";
import { FakeDatabase, ToolProvider, type ToolSpec } from "../execute/tools.js";

/**
 * 状态通道：每个通道有自己的归约语义。
 *
 * 为什么不用一个大对象：不同字段的合并规则不同，混在一起必然有一种语义被牺牲。
 * - messages：追加（历史不能丢）
 * - approval：取新（只关心最新一次审批结论）
 * - result：追加（多步执行各有结果，要留全部）
 */
export const StateAnnotation = Annotation.Root({
  messages: Annotation<string[]>({
    reducer: (a, b) => a.concat(b),
    default: () => [],
  }),
  approval: Annotation<{ approved: boolean; by: string; note?: string } | null>({
    reducer: (_a, b) => b,           // 取新：旧审批结论不参与合并
    default: () => null,
  }),
  result: Annotation<string[]>({
    reducer: (a, b) => a.concat(b),
    default: () => [],
  }),
  pendingSql: Annotation<string>({
    reducer: (_a, b) => b,
    default: () => "",
  }),
});

export type AgentState = typeof StateAnnotation.State;

/** 策略（中间件）接口：三个成员，与课 7 一致 */
export interface MiddlewareStrategy {
  meta: { name: string; label: Record<string, string> };
  /** 静态清单：声明"我能提供哪些工具"，无副作用 */
  getToolNames(): string[];
  /** 生产运行时实例：可能被反复调用，必须便宜 */
  createMiddleware(ctx: CompileContext): MiddlewareHooks;
}

export interface CompileContext {
  definition: AgentDefinition;
  db: FakeDatabase;
  provider: ToolProvider;
}

export interface MiddlewareHooks {
  /** 环绕工具调用：可改参数、可短路、可拒绝 */
  wrapToolCall?: (call: {
    name: string;
    args: Record<string, unknown>;
  }) => Promise<{ shortCircuit?: string } | void>;
}

/**
 * 审批策略：所有 requireApprovalFor 里的工具，执行前挂起等人工。
 *
 * 注意权限分两层：
 * - 这层是"暴露控制 + 拦截"：模型主动调用时被拦下
 * - 执行器内部（runTool）还有一次授权：任何调用路径都过闸
 */
export class ApprovalPolicyStrategy implements MiddlewareStrategy {
  meta = { name: "approval", label: { "zh-Hans": "人工审批" } };

  getToolNames(): string[] {
    return [];      // 本策略不产出工具，只拦别人的
  }

  createMiddleware(ctx: CompileContext): MiddlewareHooks {
    const guarded = new Set(ctx.definition.policies.requireApprovalFor);
    return {
      wrapToolCall: async (call) => {
        if (!guarded.has(call.name)) return;      // 不在名单里，放行

        // 关键：这里抛出的不是"拒绝"，而是"挂起"。恢复后函数会从头重跑，
        // 所以 interrupt 之前的代码必须可重入（本实现里它只做只读判断）。
        const decision = interrupt({
          kind: "approval_required",
          tool: call.name,
          args: call.args,
        });

        if (String(decision) !== "approve") {
          return { shortCircuit: `审批未通过（${String(decision)}），已取消执行` };
        }
        return;
      },
    };
  }
}

/** 注册表：按 provider/organization 回落取策略（本项目只按 key 取） */
export class StrategyRegistry {
  private strategies: MiddlewareStrategy[];
  constructor(strategies: MiddlewareStrategy[]) {
    this.strategies = strategies;
  }
  all(): MiddlewareStrategy[] {
    return [...this.strategies];
  }
  toolNames(): string[] {
    return this.strategies.flatMap((s) => s.getToolNames());
  }
}

/** 编译产物：图 + 元信息（供调用运行时使用） */
export interface CompiledAgent {
  graph: ReturnType<typeof buildGraph>;
  definition: AgentDefinition;
  toolNames: string[];
}

function buildGraph(ctx: CompileContext, checkpointer?: any) {
  const { definition, db, provider } = ctx;
  const registry = new StrategyRegistry([new ApprovalPolicyStrategy()]);
  const hooks = registry
    .all()
    .map((s) => s.createMiddleware(ctx))
    .filter((h) => h.wrapToolCall);

  /** 统一的工具执行入口：provider 校验参数 + 执行器授权 + 钩子环绕 */
  const runTool = async (name: string, rawArgs: unknown) => {
    const spec: ToolSpec | undefined = provider.get(name);
    if (!spec) return `未知工具：${name}`;

    // 通道 1：暴露校验——只有定义里声明的工具才允许跑
    if (!definition.tools.includes(name)) {
      return `工具未在定义中声明：${name}`;
    }

    // 通道 2：参数校验（入口即拦，脏参数不进入执行器）
    let args: Record<string, unknown>;
    try {
      args = spec.parse(rawArgs);
    } catch (e) {
      return `参数不合法：${(e as Error).message}`;
    }

    // 通道 3：策略钩子（审批挂起就发生在这里）
    for (const h of hooks) {
      const r = await h.wrapToolCall!({ name, args });
      if (r?.shortCircuit) return r.shortCircuit;
    }

    // 通道 4：执行器内部授权——即使有人绕过上面三层直接调 runTool，
    //         写操作仍然要求本次请求已带"已批准"标记（见 main.ts 的 resume 分支）
    const sql = String(args.sql ?? "");
    if (spec.op === "write" && (spec.name === "executeSql")) {
      if (!/^\s*(alter|insert|update)\b/i.test(sql)) {
        return `执行器拒绝：非白名单语句`;
      }
      return db.execute(sql);
    }
    if (spec.name === "querySql") return db.query(sql);
    if (spec.name === "notifyOwner") return `[remote] 已通知 ${args.table} 的负责人`;
    return `[${name}] 执行完成`;
  };

  return new StateGraph(StateAnnotation)
    // 节点 1：模型调用（用桩模型，聚焦链路）
    .addNode("model", async (state: AgentState) => {
      const last = state.messages[state.messages.length - 1] ?? "";
      const sql = pickSql(last);

      // "模型"决定调用哪个工具：有变更意图 → executeSql；只查询 → querySql
      const isWrite = /add column|新增列|加列/i.test(last);
      if (!sql) {
        return { messages: [`(模型) 没听懂需求，请描述要改哪张表、加什么列`] };
      }
      if (!isWrite) {
        const out = await runTool("querySql", { sql: `select * from ${tableOf(sql) ?? "orders"}` });
        return { messages: [`(模型) 查询结果：${out}`], result: [out] };
      }
      // 写操作：先把 SQL 记进 pendingSql，再由 tools 节点执行（会被审批拦下）
      return { messages: [`(模型) 准备执行：${sql}`], pendingSql: sql };
    })
    // 节点 2：工具执行
    .addNode("tools", async (state: AgentState) => {
      if (!state.pendingSql) return {};
      const out = await runTool("executeSql", { sql: state.pendingSql });
      return { result: [out], messages: [`(工具) ${out}`], pendingSql: "" };
    })
    .addEdge(START, "model")
    .addEdge("model", "tools")
    .addEdge("tools", END)
    .compile({ checkpointer });
}

/** 从一句话里抽 SQL（桩模型的"生成"行为，真实系统这里是一次 LLM 调用） */
function pickSql(text: string): string | null {
  const t = tableOf(text) ?? "orders";
  const col = /(\w+)\s*(?:列|column)/i.exec(text)?.[1];
  if (/add column|新增列|加列/i.test(text)) {
    return `ALTER TABLE ${t} ADD COLUMN ${col ?? "note"} TEXT`;
  }
  if (/查询|查一下|看看/i.test(text)) return `select * from ${t}`;
  return null;
}

function tableOf(text: string): string | null {
  return /(\w+)\s*表/.exec(text)?.[1] ?? (/orders|users/i.exec(text)?.[0] ?? null);
}

/**
 * 编译入口：定义 → 图。
 *
 * 显式不缓存：每次调用都重新构建。代价是首字延迟，收益是行为永远与当前定义一致。
 */
export function compileAgent(ctx: CompileContext, checkpointer?: any): CompiledAgent {
  const graph = buildGraph(ctx, checkpointer);
  return {
    graph,
    definition: ctx.definition,
    toolNames: ctx.provider.forDefinition(ctx.definition).map((t) => t.name),
  };
}
