// 应用实战 09 · Time-travel 回放与分叉（TypeScript 侧）
// 对照：../../应用实战/09-Time-travel 回放与分叉.md
// 运行：npm run a09
import { Annotation, END, MemorySaver, START, StateGraph } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

const Refund = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const lookup = (s: typeof Refund.State) => ({ log: [`查订单:金额${s.amount}`] });
const score = (s: typeof Refund.State) => {
  const risk = s.amount > 1000 ? 0.9 : 0.2;
  return { log: [`算风险:risk=${risk}`], risk };
};
const decide = (s: typeof Refund.State) => {
  const d = s.risk > 0.7 ? "驳回" : "批准";
  return { log: [`判定:${d}`], decision: d };
};
const notify = (s: typeof Refund.State) => ({ log: [`通知:${s.decision}`] });

const builder = new StateGraph(Refund)
  .addNode("查订单", lookup)
  .addNode("算风险", score)
  .addNode("判定", decide)
  .addNode("通知", notify)
  .addEdge(START, "查订单")
  .addEdge("查订单", "算风险")
  .addEdge("算风险", "判定")
  .addEdge("判定", "通知")
  .addEdge("通知", END);

const graph = builder.compile({ checkpointer: new MemorySaver() });
const cfg = { configurable: { thread_id: "投诉单A" } };

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：翻回看清当时为什么判驳回");
{
  const result = await graph.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, cfg);
  console.log("结果:", result.decision);
  console.log("\n历史（新 -> 旧）:");

  const hist: any[] = [];
  // ⚠️ getStateHistory 返回异步迭代器，外层还要 await
  for await (const s of await graph.getStateHistory(cfg)) hist.push(s);
  hist.forEach((s, i) => {
    const step = s.metadata?.step;
    const source = s.metadata?.source;
    console.log(
      `  [${i}] next=${JSON.stringify(s.next).padEnd(14)} step=${String(step).padStart(2)} ` +
        `source=${String(source).padEnd(6)} log=${JSON.stringify(s.values.log)}`
    );
  });

  const atDecide = hist[2];
  console.log(`\n判定前: next=${JSON.stringify(atDecide.next)}`);
  console.log(`        risk=${atDecide.values.risk} amount=${atDecide.values.amount}`);
  console.log(`        parentConfig 存在=${atDecide.parentConfig != null}`);

  const after = await graph.getState(cfg);
  console.log(`\n看完之后最新状态: next=${JSON.stringify(after.next)}（没有改变）`);
}

// ---------------------------------------------------------------- 第 2 跳
line("第 2 跳：跨 thread 分叉会丢状态");
{
  const hist: any[] = [];
  for await (const s of await graph.getStateHistory(cfg)) hist.push(s);
  const atDecide = hist[2];

  const newThread = { configurable: { thread_id: "投诉单A-改判" } };
  const badCfg = {
    configurable: {
      ...atDecide.config.configurable,
      thread_id: "投诉单A-改判",
    },
  };

  console.log("改判前，新 thread 里有什么：");
  console.log(" ", JSON.stringify((await graph.getState(newThread)).values));

  await graph.updateState(badCfg, { decision: "批准" });
  const st = await graph.getState(newThread);
  console.log("update 之后:");
  console.log(`  next   = ${JSON.stringify(st.next)}`);
  console.log(`  values = ${JSON.stringify(st.values)}`);

  try {
    const r = await graph.invoke(null, newThread);
    console.log("跑完:", JSON.stringify(r.log));
  } catch (e: any) {
    console.log(`${e.name}: ${e.message.split("\n")[0]}`);
  }

  // 同 thread 分叉
  const same = await graph.updateState(atDecide.config, { decision: "批准" });
  const st2 = await graph.getState(same);
  console.log(`\n同 thread: next=${JSON.stringify(st2.next)}`);
  console.log(`           values=${JSON.stringify(st2.values)}`);

  console.log("\n原 thread 最新:", JSON.stringify((await graph.getState(cfg)).values.log));
  const h2: any[] = [];
  for await (const s of await graph.getStateHistory(cfg)) h2.push(s);
  console.log("历史条数:", h2.length);
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：改判 + 留住事故现场");
{
  // 重新建一个干净的图，避免受第 2 跳的同 thread 分叉影响
  const g = new StateGraph(Refund)
    .addNode("查订单", lookup)
    .addNode("算风险", score)
    .addNode("判定", decide)
    .addNode("通知", notify)
    .addEdge(START, "查订单")
    .addEdge("查订单", "算风险")
    .addEdge("算风险", "判定")
    .addEdge("判定", "通知")
    .addEdge("通知", END)
    .compile({ checkpointer: new MemorySaver() });

  const c = { configurable: { thread_id: "投诉单A" } };
  await g.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, c);

  const archive: any[] = [];
  for await (const s of await g.getStateHistory(c)) archive.push(s);
  console.log(`已归档 ${archive.length} 条快照（只读，不再改动）`);
  const atDecide = archive[2];

  // 第一步：整体搬 values
  const fork = { configurable: { thread_id: "投诉单A-改判v2" } };
  await g.updateState(fork, atDecide.values);
  console.log("搬完后:", JSON.stringify((await g.getState(fork)).values));

  // 第二步：改要改的
  await g.updateState(fork, { decision: "批准" });
  const st3 = await g.getState(fork);
  console.log(`改完后: next=${JSON.stringify(st3.next)}`);
  console.log(`        decision=${st3.values.decision} risk=${st3.values.risk}`);

  // 第三步：跑，接受会重跑
  const r3 = await g.invoke(null, fork);
  console.log("改判后结果:", JSON.stringify(r3.log));
  console.log("最终决定:", r3.decision);

  // 第四步：改最上游依据
  const fork2 = { configurable: { thread_id: "投诉单A-改判v3" } };
  await g.updateState(fork2, atDecide.values);
  await g.updateState(fork2, { amount: 500, risk: 0.1 }); // ← 改最上游依据
  const r5 = await g.invoke(null, fork2);
  console.log("改依据后:", JSON.stringify(r5.log.slice(-2)));
  console.log("最终决定:", r5.decision);

  // 事故现场
  console.log("原 thread 最新 decision:", (await g.getState(c)).values.decision);
  const ha: any[] = [];
  for await (const s of await g.getStateHistory(c)) ha.push(s);
  console.log("原 thread 历史条数:", ha.length);
  console.log("新 thread 最终 decision:", r3.decision);
}

// ---------------------------------------------------------------- 同 thread 最省事
line("只在本地试：同 thread 最省事");
{
  const g = new StateGraph(Refund)
    .addNode("查订单", lookup)
    .addNode("算风险", score)
    .addNode("判定", decide)
    .addNode("通知", notify)
    .addEdge(START, "查订单")
    .addEdge("查订单", "算风险")
    .addEdge("算风险", "判定")
    .addEdge("判定", "通知")
    .addEdge("通知", END)
    .compile({ checkpointer: new MemorySaver() });

  const c = { configurable: { thread_id: "quick" } };
  await g.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, c);
  const h: any[] = [];
  for await (const s of await g.getStateHistory(c)) h.push(s);
  const mid = h[2];

  const quick = await g.updateState(mid.config, { decision: "批准" });
  const r4 = await g.invoke(null, quick);
  console.log("同 thread 改判:", JSON.stringify(r4.log));
}

// ---------------------------------------------------------------- 计数器
line("只重跑后面：用计数器验证");
{
  const calls: string[] = [];
  const traced = (name: string) => (s: typeof Refund.State) => {
    calls.push(name);
    return { log: [name] };
  };

  const b2 = new StateGraph(Refund)
    .addNode("查订单", traced("查订单") as any)
    .addNode("算风险", traced("算风险") as any)
    .addNode("判定", traced("判定") as any)
    .addNode("通知", traced("通知") as any)
    .addEdge(START, "查订单")
    .addEdge("查订单", "算风险")
    .addEdge("算风险", "判定")
    .addEdge("判定", "通知")
    .addEdge("通知", END);
  const g2 = b2.compile({ checkpointer: new MemorySaver() });
  const c2 = { configurable: { thread_id: "计数验证" } };

  await g2.invoke({ log: [], amount: 5000, risk: 0, decision: "" }, c2);
  console.log("首次执行调用了:", JSON.stringify(calls));
  calls.length = 0;

  const h2: any[] = [];
  for await (const s of await g2.getStateHistory(c2)) h2.push(s);
  const mid = h2[2];
  const f = await g2.updateState(mid.config, { decision: "批准" });
  console.log(`分叉点 next=${JSON.stringify((await g2.getState(f)).next)}`);
  await g2.invoke(null, f);
  console.log("分叉后只调用了:", JSON.stringify(calls));
}
