/**
 * 课程 4.1 机制验证脚本（三）：地图 / 旅程 / 判断力
 *
 * 覆盖课 2（依赖方向）、课 3（流式协议与账本）、课 14（迁移信号 / 约束还原 / 不变量）。
 *
 * 运行：npx tsx verify-map.ts
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const line = (t: string) => console.log(t);

// ───────────────────── 课 2：四层与依赖单向 ─────────────────────

line("=== 课 2：四层的边界与依赖方向 ===");

/** 分层规则表：目录 → 层。判定看"输入输出"，不看目录名。 */
const LAYER_OF: Record<string, string> = {
  definition: "definition",
  compile: "compile",
  execute: "execute",
  account: "account",
};

/**
 * 允许的依赖方向：单向，不允许回流。
 *
 * 编译面为什么可以依赖执行面：编译的产物是"包含工具节点的图"，它必须知道
 * 工具抽象长什么样（类型 / 接口）。这条依赖不算违规——违规的是**编译期执行 IO**
 * （见下方第 ② 条断言），以及**执行面反过来依赖编译面**（层间回流）。
 */
const ALLOWED: Record<string, string[]> = {
  definition: [],                            // 定义面不依赖任何层
  compile: ["definition", "execute"],        // 编译面吃定义 + 擦边执行面的工具抽象
  execute: ["definition"],                   // 执行面吃定义（工具边界），不吃编译面
  account: ["definition", "compile"],        // 账本面记录编译产物与执行结果
};

/** 回流检查：这些方向一旦出现，分层就已经破了 */
const FORBIDDEN_DIRECTIONS = ["execute → compile", "execute → account", "compile → account"];

/** 检查器：扫描 import 语句，找出反向依赖 */
function checkDependencyDirection(root: string) {
  const violations: string[] = [];
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (name.endsWith(".ts")) files.push(p);
    }
  };
  walk(root);

  for (const f of files) {
    const rel = relative(root, f);
    const fromLayer = LAYER_OF[rel.split("/")[0]];
    if (!fromLayer) continue;
    const src = readFileSync(f, "utf8");
    for (const m of src.matchAll(/from\s+"[^"]*?\/(\w+)\/[^"]*"/g)) {
      const toLayer = LAYER_OF[m[1]];
      if (!toLayer || toLayer === fromLayer) continue;
      if (!ALLOWED[fromLayer].includes(toLayer)) {
        violations.push(`${rel}: ${fromLayer} → ${toLayer}（不允许）`);
      }
    }
  }
  return { files: files.length, violations };
}

const dep = checkDependencyDirection("../projects/数据库变更审批助手/实现/src");
line(`① 依赖方向检查: 扫描 ${dep.files} 个文件，回流违规 ${dep.violations.length} 条`);
for (const v of dep.violations) line("   - " + v);
line("   禁止方向清单: " + FORBIDDEN_DIRECTIONS.join("；") + "（均未出现即分层成立）");

/** 编译面不碰 IO：断言源码里没有 DB / HTTP 调用 */
function assertCompileIsPure(path: string) {
  const src = readFileSync(path, "utf8");
  const forbidden = ["fetch(", "axios", "createConnection", "pg.", "redis."];
  const hits = forbidden.filter((k) => src.includes(k));
  return { pure: hits.length === 0, hits };
}
const pure = assertCompileIsPure("../projects/数据库变更审批助手/实现/src/compile/compiler.ts");
line("② 编译面是纯翻译: " + (pure.pure ? "通过（无 fetch / DB / redis 调用）" : "出现副作用：" + pure.hits.join(", ")));

// ───────────────────── 课 3：请求旅程 ─────────────────────

line("");
line("=== 课 3：一次请求的完整旅程 ===");

type StreamEvent =
  | { type: "token"; text: string }
  | { type: "tool_start"; name: string }
  | { type: "tool_end"; name: string; ok: boolean }
  | { type: "interrupt"; payload: unknown }
  | { type: "error"; message: string }
  | { type: "done"; status: "succeeded" | "failed" | "interrupted" };

/** SSE 编码：事件必须带类型；错误也走事件；必须有 done 收尾 */
function encodeSSE(e: StreamEvent) {
  return `event: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`;
}

/** 一次"请求"：四条断言各自盯住一个最容易写错的地方 */
async function runRequest(handler: (emit: (e: StreamEvent) => void) => Promise<void>) {
  const events: StreamEvent[] = [];
  try {
    await handler((e) => events.push(e));
  } catch (err) {
    events.push({ type: "error", message: (err as Error).message });
  } finally {
    if (!events.some((e) => e.type === "done")) {
      events.push({ type: "done", status: "failed" });
    }
  }
  return events;
}

// ① 正常路径：token → tool → token → done
const okEvents = await runRequest(async (emit) => {
  emit({ type: "token", text: "我先查一下" });
  emit({ type: "tool_start", name: "querySql" });
  emit({ type: "tool_end", name: "querySql", ok: true });
  emit({ type: "token", text: "订单在运输中" });
  emit({ type: "done", status: "succeeded" });
});
line("① 正常路径事件序列: [" + okEvents.map((e) => e.type).join(", ") + "]");
line("   一定有 done 收尾: " + (okEvents[okEvents.length - 1].type === "done"));

// ② 异常路径：错误也走事件（状态码早已发出），且仍以 done 收尾
const failEvents = await runRequest(async (emit) => {
  emit({ type: "token", text: "开始" });
  throw new Error("模型返回 429 限流");
});
line("② 异常路径: [" + failEvents.map((e) => e.type).join(", ") + "]（错误不吞、done 仍存在）");
line("   错误事件内容: " + JSON.stringify(failEvents.find((e) => e.type === "error")));

// ③ 消息追加而非覆盖
const { StateGraph, Annotation, START, END } = await import("@langchain/langgraph");
const Chat = Annotation.Root({
  messages: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});
const g = new StateGraph(Chat)
  .addNode("turn1", async () => ({ messages: ["user:hi", "ai:你好"] }))
  .addNode("turn2", async () => ({ messages: ["user:查订单", "ai:在运输中"] }))
  .addEdge(START, "turn1")
  .addEdge("turn1", "turn2")
  .addEdge("turn2", END)
  .compile();
const r3: any = await g.invoke({});
line("③ 消息追加: " + r3.messages.length + " 条 → " + JSON.stringify(r3.messages));

// ④ SSE 编码形态
line("④ SSE 编码样例: " + JSON.stringify(encodeSSE({ type: "done", status: "succeeded" })));

// ───────────────────── 课 14：判断力三件工具 ─────────────────────

line("");
line("=== 课 14：设计判断力 ===");

/** ① 迁移信号表：扩展点数量 + 重复度决定要不要迁 */
function shouldMigrateMiddleware(c: { extensionPoints: number; duplicated: boolean }) {
  if (c.extensionPoints <= 3 && !c.duplicated) return [false, "扩展点少且无重复，迁移收益低于成本"] as const;
  if (c.extensionPoints >= 10 || c.duplicated) return [true, "扩展点多或已有重复，抽层能收敛改动面"] as const;
  return [false, "处在灰度区间，先观察下一次需求"] as const;
}
line("① 迁移判断:");
line("   2 个扩展点 + 无重复 → " + JSON.stringify(shouldMigrateMiddleware({ extensionPoints: 2, duplicated: false })));
line("   11 个扩展点 + 有重复 → " + JSON.stringify(shouldMigrateMiddleware({ extensionPoints: 11, duplicated: true })));

/** ② 约束还原：证据不足时必须输出"证据不足"，不许编故事 */
function reconstruct(c: { hasCommitContext: boolean; hasDesignDoc: boolean; capabilityToday: boolean }) {
  if (!c.hasCommitContext && !c.hasDesignDoc) return "证据不足：缺少当时的提交上下文与设计文档，无法还原约束";
  if (c.capabilityToday) return "当时框架能力不支持，今天已支持 → 等下一次触碰该模块时再改，不立即重写";
  return "约束仍然成立，当前写法是合理选择";
}
line("② 约束还原（无证据）: " + reconstruct({ hasCommitContext: false, hasDesignDoc: false, capabilityToday: true }));
line("   约束还原（当时做不到、今天能做）: " + reconstruct({ hasCommitContext: true, hasDesignDoc: false, capabilityToday: true }));

/** ③ 可测试性：不变量断言能检出孤儿工具结果 */
function assertNoOrphanToolMessages(msgs: { role: string; tool_call_id?: string }[], called: Set<string>) {
  for (const m of msgs) {
    if (m.role === "tool" && (!m.tool_call_id || !called.has(m.tool_call_id))) {
      throw new Error(`不变量被破坏：tool 消息 ${m.tool_call_id ?? "(无 id)"} 找不到对应的 tool_call`);
    }
  }
  return true;
}
try {
  assertNoOrphanToolMessages([{ role: "tool", tool_call_id: "call_9" }], new Set());
  line("③ 不变量检查: 未检出 ❌");
} catch (e) {
  line("③ 不变量检查（孤儿工具结果被检出）: " + (e as Error).message);
}
