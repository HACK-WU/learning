// 课 9 · Time-travel 回放与分叉（TypeScript 侧）
// 对照：../../playground/09_time_travel.py（Python 侧）
// 运行：npm run l09
import { Annotation, END, MemorySaver, START, StateGraph } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

// 主图：s3 只读取 decision 写日志（不重算），与课文一致
const build = () => {
  const S = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const calls: string[] = [];
  const b = new StateGraph(S)
    .addNode("s1", () => {
      calls.push("s1");
      return { log: ["s1:查订单"] };
    })
    .addNode("s2", (s) => {
      calls.push("s2");
      return { log: [`s2:判定=${s.amount > 1000}`], risk: s.amount > 1000 ? 0.9 : 0.1 };
    })
    .addNode("s3", (s) => {
      calls.push("s3");
      return { log: [`s3:${s.decision || "驳回"}`], decision: s.decision || "驳回" };
    })
    .addEdge(START, "s1").addEdge("s1", "s2").addEdge("s2", "s3").addEdge("s3", END);
  return { graph: b.compile({ checkpointer: new MemorySaver() }), calls };
};

// 决策图：s3 按 risk 自己算结论（用于验证"改依据 vs 改结论"）
const buildDecision = () => {
  const S = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const b = new StateGraph(S)
    .addNode("算风险", (s) => ({ risk: s.amount > 1000 ? 0.9 : 0.1, log: ["算风险"] }))
    .addNode("判定", (s) => ({ decision: s.risk > 0.5 ? "驳回" : "批准", log: [`判定:${s.risk > 0.5 ? "驳回" : "批准"}`] }))
    .addNode("通知", (s) => ({ log: [`通知:${s.decision}`] }))
    .addEdge(START, "算风险").addEdge("算风险", "判定").addEdge("判定", "通知").addEdge("通知", END);
  return b.compile({ checkpointer: new MemorySaver() });
};

const histOf = async (graph: any, cfg: any, opts?: any) => {
  const out: any[] = [];
  for await (const s of await graph.getStateHistory(cfg, opts)) out.push(s);
  return out;
};

// 验证一：历史条数与内容
line("验证一：历史条数与内容");
{
  const { graph, calls } = build();
  const cfg = { configurable: { thread_id: "tt1" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  console.log("  历史条数:", h.length, "（3 节点 → 5 条）");
  console.log("  首次执行调用:", JSON.stringify(calls));
  h.forEach((s: any, i: number) =>
    console.log(`  [${i}] next=${JSON.stringify(s.next)} step=${s.metadata?.step} source=${s.metadata?.source} log=${JSON.stringify(s.values.log)}`),
  );
}

// 验证二：只读回看
line("验证二：只读回看（getState 不改图）");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt2" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  const snap = await graph.getState(h[2].config);
  console.log("  getState(old.config) -> next:", JSON.stringify(snap.next), " log:", JSON.stringify(snap.values.log));
  console.log("  当前最新仍是 next:", JSON.stringify((await graph.getState(cfg)).next), "  ← 图没动");
}

// 验证三/四：同 thread 分叉 + 历史变长 + 重跑范围
line("验证三/四：同 thread 分叉 / 历史变长 / 重跑范围");
{
  const { graph, calls } = build();
  const cfg = { configurable: { thread_id: "tt3" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  const before = calls.length;
  const forkCfg: any = await graph.updateState(h[2].config, { decision: "批准" });
  console.log("  updateState 返回 keys:", Object.keys(forkCfg).join(","), " config:", JSON.stringify(forkCfg.configurable));
  const forked = await graph.getState(forkCfg);
  console.log("  分叉后 next:", JSON.stringify(forked.next), " log:", JSON.stringify(forked.values.log), " decision:", forked.values.decision);
  console.log("  分叉后历史条数:", (await histOf(graph, cfg)).length, "（5 → 6）");
  const res: any = await graph.invoke(null, forkCfg);
  console.log("  跑完 log:", JSON.stringify(res.log));
  console.log("  重跑调用:", JSON.stringify(calls.slice(before)), "  ← s1 没重跑");
}

// 验证五：跨 thread 分叉（第二幕的答案）
line("验证五：跨 thread 分叉");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt5" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  const oldCfg = h[2].config;
  const fork = { configurable: { ...oldCfg.configurable, thread_id: "fork1" } };
  const ret: any = await graph.updateState(fork, { decision: "批准" });
  console.log("  updateState 返回的 config:", JSON.stringify(ret.configurable));
  const byOld = await graph.getState(fork);
  console.log("  用旧 config（带旧 checkpoint_id）查: values=", JSON.stringify(byOld.values), " next=", JSON.stringify(byOld.next));
  const onlyTid = { configurable: { thread_id: "fork1" } };
  const byTid = await graph.getState(onlyTid);
  console.log("  仅 thread_id 查: values=", JSON.stringify(byTid.values), " next=", JSON.stringify(byTid.next));
  console.log("  原 thread 仍完好:", JSON.stringify((await graph.getState(cfg)).values.log));
}

// 验证六：跨 thread 正确写法（先搬 values）
line("验证六：跨 thread + 先搬 values");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt6" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  const nt = { configurable: { thread_id: "fk2" } };
  await graph.updateState(nt, h[2].values);
  const moved = await graph.getState(nt);
  console.log("  搬 values 后 next:", JSON.stringify(moved.next), " log:", JSON.stringify(moved.values.log));
  await graph.updateState(nt, { decision: "批准" });
  const done: any = await graph.invoke(null, nt);
  console.log("  跑完 log:", JSON.stringify(done.log), "  ← s1 出现两次");
}

// 验证七：asNode 三态
line("验证七：asNode 决定从哪继续");
{
  for (const node of [undefined, "s1", "s2", "s3"]) {
    const { graph } = build();
    const cfg = { configurable: { thread_id: `n-${node ?? "none"}` } };
    await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
    const h = await histOf(graph, cfg);
    const r: any = node
      ? await graph.updateState(h[2].config, { decision: "批准" }, node as any)
      : await graph.updateState(h[2].config, { decision: "批准" });
    console.log(`  asNode=${String(node)} -> next:`, JSON.stringify((await graph.getState(r)).next));
  }
  const { graph } = build();
  const cfg = { configurable: { thread_id: "bad" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  try {
    await graph.updateState(h[2].config, { decision: "x" }, "no_such_node" as any);
  } catch (e) {
    console.log("  asNode 不存在:", (e as Error).message.slice(0, 60));
  }
}

// 验证八：无 checkpointer
line("验证八：没有 checkpointer 就没有历史");
{
  const S = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const g = new StateGraph(S).addNode("x", () => ({ log: ["x"] })).addEdge(START, "x").addEdge("x", END).compile();
  const cfg = { configurable: { thread_id: "no-cp" } };
  try {
    for await (const _ of await g.getStateHistory(cfg)) { /* noop */ }
  } catch (e) {
    console.log("  getStateHistory:", (e as Error).message.split("\n")[0].slice(0, 60));
  }
  try {
    await g.updateState(cfg, { log: ["y"] });
  } catch (e) {
    console.log("  updateState:  ", (e as Error).message.split("\n")[0].slice(0, 60));
  }
}

// 验证九：假 checkpoint_id
line("验证九：手工拼 checkpoint_id（不校验）");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt9" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const s = await graph.getState({ configurable: { thread_id: "tt9", checkpoint_id: "not-exist" } });
  console.log("  values:", JSON.stringify(s.values), " next:", JSON.stringify(s.next), "  ← 不报错！");
}

// 验证十：翻页参数
line("验证十：翻页参数");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt10" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const all = await histOf(graph, cfg);
  const limited = await histOf(graph, cfg, { limit: 2 });
  const before = await histOf(graph, cfg, { before: all[0].config });
  console.log("  默认:", all.length, " limit=2:", limited.length, " before=第0条:", before.length);
}

// 验证十一：改结论无效 / 改依据生效
line("验证十一：改的是依据，不是结论");
{
  const graph = buildDecision();
  const cfg = { configurable: { thread_id: "tt11" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const h = await histOf(graph, cfg);
  const r1: any = await graph.updateState(h[2].config, { decision: "批准" });
  const o1: any = await graph.invoke(null, r1);
  console.log("  只改 decision:", JSON.stringify(o1.log), " 最终决定:", o1.decision, "  ← 被判定节点重算覆盖");

  const graph2 = buildDecision();
  const cfg2 = { configurable: { thread_id: "tt11b" } };
  await graph2.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg2);
  const h2 = await histOf(graph2, cfg2);
  const r2: any = await graph2.updateState(h2[3].config, { risk: 0.1 }); // 从「算风险」之前分叉
  const o2: any = await graph2.invoke(null, r2);
  console.log("  改 risk=0.1（从算风险前分叉）:", " 最终决定:", o2.decision, "  ← 算风险又按 amount 重算回 0.9");

  const graph3 = buildDecision();
  const cfg3 = { configurable: { thread_id: "tt11c" } };
  await graph3.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg3);
  const h3 = await histOf(graph3, cfg3);
  const r3: any = await graph3.updateState(h3[3].config, { amount: 500 });
  const o3: any = await graph3.invoke(null, r3);
  console.log("  改 amount=500:", JSON.stringify(o3.log), " 最终决定:", o3.decision, "  ← 生效");
}

// 验证十二：分叉后再分叉
line("验证十二：分叉后再分叉");
{
  const { graph } = build();
  const cfg = { configurable: { thread_id: "tt12" } };
  await graph.invoke({ log: [], amount: 5000, decision: "驳回" }, cfg);
  const n0 = (await histOf(graph, cfg)).length;
  const h = await histOf(graph, cfg);
  const f1: any = await graph.updateState(h[2].config, { decision: "批准" });
  const n1 = (await histOf(graph, cfg)).length;
  const f2: any = await graph.updateState(f1, { decision: "再改" });
  const n2 = (await histOf(graph, cfg)).length;
  console.log(`  历史条数: ${n0} -> ${n1} -> ${n2}`);
  console.log("  最新 values.decision:", (await graph.getState(f2)).values.decision);
}

console.log("\n全部验证跑完。");
