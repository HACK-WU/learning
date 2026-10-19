// 对应课 7《Streaming 流式输出》
// 运行：npm run l07
import {
  StateGraph,
  Annotation,
  START,
  END,
  MemorySaver,
  getWriter,
} from "@langchain/langgraph";

const S = Annotation.Root({
  draft: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  review: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const g = new StateGraph(S)
  .addNode("draft_node", () => ({ draft: "草稿-A" }))
  .addNode("review_node", () => ({ review: "审阅-草稿-A" }))
  .addEdge(START, "draft_node")
  .addEdge("draft_node", "review_node")
  .addEdge("review_node", END)
  .compile({ checkpointer: new MemorySaver() });

const cfg = (t: string) => ({ configurable: { thread_id: t } });

// ── 1. values：全量（含输入初态，节点数 + 1 个 chunk）
console.log("--- values ---");
const vs: unknown[] = [];
for await (const c of await g.stream({}, { streamMode: "values", ...cfg("v") })) vs.push(c);
vs.forEach((c, i) => console.log(` [${i}]`, JSON.stringify(c)));
console.log(" values chunk 数:", vs.length);

// ── 2. updates：只给改动，一个节点一个
console.log("--- updates ---");
for await (const c of await g.stream({}, { streamMode: "updates", ...cfg("u") })) {
  console.log(" ", JSON.stringify(c));
}

// ── 3. 多模式同时开 → [模式, 数据] 且交错
console.log("--- 多模式 ---");
for await (const [mode, chunk] of await g.stream({}, { streamMode: ["updates", "values"], ...cfg("m") })) {
  console.log(` ${mode}:`, JSON.stringify(chunk));
}

// ── 4. custom：必须声明 custom 才收得到
console.log("--- custom ---");
const withWriter = new StateGraph(S)
  .addNode("n", () => {
    const w = getWriter()!; // 等价写法：节点第二参数 config.writer
    w({ progress: 0.1, msg: "开始" });
    w({ progress: 0.5, msg: "一半" });
    w({ progress: 1.0, msg: "完成" });
    return { draft: "done" };
  })
  .addEdge(START, "n")
  .addEdge("n", END)
  .compile();

const underValues: unknown[] = [];
for await (const c of await withWriter.stream({}, { streamMode: "values" })) underValues.push(c);
console.log(" values 下（自定义数据被丢）:", JSON.stringify(underValues));
for await (const c of await withWriter.stream({}, { streamMode: "custom" })) {
  console.log(" custom 下:", JSON.stringify(c));
}

// ── 5. messages：无 LLM 时 0 条
let msgCount = 0;
for await (const _ of await g.stream({}, { streamMode: "messages", ...cfg("msg") })) msgCount++;
console.log("--- messages（无大模型）chunk 数:", msgCount);

// ── 6. 另三种模式：checkpoints / tasks / debug
let ck = 0;
for await (const _ of await g.stream({}, { streamMode: "checkpoints", ...cfg("ck") })) ck++;
console.log("--- checkpoints 次数:", ck);

for await (const t of await g.stream({}, { streamMode: "tasks", ...cfg("tk") })) {
  const task = t as unknown as Record<string, unknown>;
  console.log(` task name=${task.name} ${task.result ? "result" : "start"}`, JSON.stringify(task.result ?? task.input));
}

for await (const d of await g.stream({}, { streamMode: "debug", ...cfg("dbg") })) {
  const item = d as { type: string; payload: Record<string, unknown> };
  console.log(` debug type=${item.type} payload=${JSON.stringify(Object.keys(item.payload))}`);
}

// ── 7. 写错模式名：0 条，不报错
let bad = 0;
for await (const _ of await g.stream({}, { streamMode: "不存在的模式" as never, ...cfg("bad") })) bad++;
console.log("--- 写错模式名输出:", bad, "条");

// ── 8. 事件流：streamEvents（不是 astreamEvents）
console.log("--- 事件流 ---");
const names: string[] = [];
for await (const ev of g.streamEvents({}, { version: "v2", ...cfg("ev") })) {
  names.push(`${ev.event}:${ev.name ?? ""}`);
}
console.log(" 事件总数:", names.length);
console.log(" 顺序:", names.join(" -> "));

// ── 9. 筛选参数在第三个参数里（放第二个不报错也不生效）
let c1 = 0;
for await (const _ of (g as any).streamEvents({}, { version: "v2", ...cfg("f1") }, { includeNames: ["draft_node"] })) c1++;
let c2 = 0;
for await (const _ of (g as any).streamEvents({}, { version: "v2", includeNames: ["draft_node"], ...cfg("f2") })) c2++;
let c3 = 0;
for await (const _ of (g as any).streamEvents({}, { version: "v2", ...cfg("f3") })) c3++;
console.log(" includeNames(第三参数):", c1, "| 放第二参数:", c2, "| 不筛选:", c3);

// ── 10. 子图：默认不可见，subgraphs 才露出
const Sub = Annotation.Root({ text: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }) });
const sub = new StateGraph(Sub)
  .addNode("inner", () => ({ text: "起+子图" }))
  .addEdge(START, "inner")
  .addEdge("inner", END)
  .compile();

const parent = new StateGraph(Sub)
  .addNode("call_sub", sub as never)
  .addEdge(START, "call_sub")
  .addEdge("call_sub", END)
  .compile();

console.log("--- 子图默认 ---");
for await (const c of await parent.stream({ text: "起" }, { streamMode: "values" })) {
  console.log(" ", JSON.stringify(c));
}
console.log("--- 子图 subgraphs: true ---");
for await (const [ns, c] of await parent.stream({ text: "起" }, { streamMode: "values", subgraphs: true })) {
  console.log(" ", JSON.stringify(ns), JSON.stringify(c));
}

// ── 11. custom 跨子图（TS 侧默认就能收到，subgraphs 只多给来源路径）
const Sub2 = Annotation.Root({ n: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }) });
const sub2 = new StateGraph(Sub2)
  .addNode("emit", () => {
    getWriter()!({ 来自: "子图内部", 进度: 50 });
    return { n: 1 };
  })
  .addEdge(START, "emit")
  .addEdge("emit", END)
  .compile();
const parent2 = new StateGraph(Sub2)
  .addNode("sub", sub2 as never)
  .addEdge(START, "sub")
  .addEdge("sub", END)
  .compile();

console.log("--- custom 跨子图：默认 ---");
for await (const c of await parent2.stream({ n: 0 }, { streamMode: "custom" })) {
  console.log(" ", JSON.stringify(c));
}
console.log("--- custom 跨子图：subgraphs ---");
for await (const c of await parent2.stream({ n: 0 }, { streamMode: "custom", subgraphs: true })) {
  console.log(" ", JSON.stringify(c));
}

// ── 12. version 对 stream 无效（只对 streamEvents 有意义）
console.log("--- stream 的 version ---");
for await (const c of await g.stream({}, { streamMode: "values", ...cfg("v1"), version: "v1" } as any)) {
  console.log(" v1:", JSON.stringify(c));
  break;
}
for await (const c of await g.stream({}, { streamMode: "values", ...cfg("v2"), version: "v2" } as any)) {
  console.log(" v2:", JSON.stringify(c));
  break;
}
