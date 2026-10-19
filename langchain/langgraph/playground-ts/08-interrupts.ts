// 课 8 · Interrupts 人在环中（TypeScript 侧）
// 对照：../../playground/08_interrupts.py（Python 侧）
// 运行：npm run l08
import {
  StateGraph,
  Annotation,
  START,
  END,
  MemorySaver,
  interrupt,
  Command,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

// ---------------------------------------------------------------------------
// 验证一~六：基础中断、快照、历史、节点重跑、不挂 checkpointer
// ---------------------------------------------------------------------------
line("验证一～六：基础中断 / 快照 / 历史 / 节点执行次数");

const S = Annotation.Root({
  amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  approved: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

let runs = 0;
const pay = (s: typeof S.State) => {
  runs += 1;
  console.log(`  [节点执行第 ${runs} 次] 副作用发生（假设是扣款/查库）`);
  const ans = interrupt({ 问: `要付 ${s.amount} 元，批准吗？` });
  // ↓ 中断时这一行根本没跑到，所以 approved 保持原样
  return { approved: String(ans) };
};

const builder = new StateGraph(S)
  .addNode("pay", pay)
  .addEdge(START, "pay")
  .addEdge("pay", END);

const g = builder.compile({ checkpointer: new MemorySaver() });
const cfg = { configurable: { thread_id: "t1" } };

const r1: any = await g.invoke({ amount: 100, approved: "" }, cfg);
console.log("1) invoke 返回:", JSON.stringify(r1));
console.log("   __interrupt__ 是数组:", Array.isArray(r1.__interrupt__));
console.log("   __interrupt__ 内容:", JSON.stringify(r1.__interrupt__));

const st: any = await g.getState(cfg);
console.log("2) getState.next   =", JSON.stringify(st.next), "  (注意：TS 是数组，Python 是元组)");
console.log("   getState.values =", JSON.stringify(st.values));
console.log("   getState.tasks  =", JSON.stringify(st.tasks));
console.log("   getState.interrupts =", JSON.stringify(st.interrupts), "  ← TS 没有这个顶层字段");
console.log("   StateSnapshot 的键 =", Object.keys(st).join(","));
console.log("   真正的题面在 tasks[0].interrupts =", JSON.stringify(st.tasks[0].interrupts));

const hist: any[] = [];
for await (const h of await g.getStateHistory(cfg)) hist.push(h);
console.log("3) checkpoint 条数（中断后）:", hist.length);
hist.forEach((h, i) => console.log(`   [${i}] next=${JSON.stringify(h.next)} values=${JSON.stringify(h.values)}`));

console.log("4) resume 前节点执行次数:", runs);
const r2: any = await g.invoke(new Command({ resume: "批准" }), cfg);
console.log("5) resume 后返回:", JSON.stringify(r2));
console.log("   节点执行次数:", runs, "  ← 变成 2，证明整体重跑");

// 不挂 checkpointer
const gNoCp = builder.compile();
try {
  const r3 = await gNoCp.invoke({ amount: 100, approved: "" });
  console.log("6) 不挂 checkpointer 返回:", JSON.stringify(r3));
} catch (e) {
  console.log("6) 不挂 checkpointer 直接抛:", (e as Error).message.slice(0, 110));
}

// ---------------------------------------------------------------------------
// 验证七：中断期间状态冻结
// ---------------------------------------------------------------------------
line("验证七：中断期间状态是否冻结");

const FS = Annotation.Root({
  before: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  after: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});
const fg = new StateGraph(FS)
  .addNode("n", () => {
    const a = interrupt("停一下");
    return { after: String(a) };
  })
  .addEdge(START, "n")
  .addEdge("n", END)
  .compile({ checkpointer: new MemorySaver() });
const fcfg = { configurable: { thread_id: "freeze1" } };
await fg.invoke({ before: "初始值", after: "" }, fcfg);
const fst: any = await fg.getState(fcfg);
console.log("  中断时 values =", JSON.stringify(fst.values), " next =", JSON.stringify(fst.next));

// ---------------------------------------------------------------------------
// 验证八：静态中断 interruptBefore
// ---------------------------------------------------------------------------
line("验证八：静态中断 interruptBefore");

const SS = Annotation.Root({ out: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }) });
const sg = new StateGraph(SS)
  .addNode("step1", () => ({ out: "1" }))
  .addNode("step2", (s) => ({ out: s.out + "2" }))
  .addEdge(START, "step1")
  .addEdge("step1", "step2")
  .addEdge("step2", END)
  .compile({ checkpointer: new MemorySaver(), interruptBefore: ["step2"] });

const scfg = { configurable: { thread_id: "static1" } };
const s1: any = await sg.invoke({ out: "" }, scfg);
console.log("  第一次 invoke:", JSON.stringify(s1), "  ← __interrupt__ 是空数组");
const sst: any = await sg.getState(scfg);
console.log("  next =", JSON.stringify(sst.next), " values =", JSON.stringify(sst.values));
console.log("  tasks[0].interrupts =", JSON.stringify(sst.tasks[0].interrupts), "  ← 静态中断没有题面");
const s2: any = await sg.invoke(null, scfg);
console.log("  invoke(null) 放行:", JSON.stringify(s2));

// ---------------------------------------------------------------------------
// 验证九：updateState 不消中断
// ---------------------------------------------------------------------------
line("验证九：updateState 不消中断");

const US = Annotation.Root({ out: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }) });
const ug = new StateGraph(US)
  .addNode("pay", () => {
    const a = interrupt("批准吗？");
    return { out: String(a) };
  })
  .addEdge(START, "pay")
  .addEdge("pay", END)
  .compile({ checkpointer: new MemorySaver() });
const ucfg = { configurable: { thread_id: "upd1" } };
await ug.invoke({ out: "" }, ucfg);
for (let i = 1; i <= 3; i += 1) {
  await ug.updateState(ucfg, { out: `改${i}` });
  const r: any = await ug.invoke(null, ucfg);
  console.log(`  第 ${i} 轮 updateState + invoke(null) -> 又中断:`, Array.isArray(r.__interrupt__), " out =", r.out);
}

// ---------------------------------------------------------------------------
// 验证十：流里能看到 interrupt
// ---------------------------------------------------------------------------
line("验证十：流里能看到 interrupt");

console.log("  --- updates 流 ---");
for await (const c of await ug.stream({ out: "" }, { ...{ configurable: { thread_id: "s-upd" } }, streamMode: "updates" })) {
  console.log("   ", JSON.stringify(c));
}
console.log("  --- values 流 ---");
for await (const c of await ug.stream({ out: "" }, { ...{ configurable: { thread_id: "s-val" } }, streamMode: "values" })) {
  const keys = Object.keys(c as object).join(",");
  const itr = (c as any).__interrupt__;
  console.log("    keys =", keys, " __interrupt__ =", JSON.stringify(itr));
}

// ---------------------------------------------------------------------------
// 验证十一：resume 类型透传 + 假值被拒
// ---------------------------------------------------------------------------
line("验证十一：resume 类型透传 / 假值被拒");

const TS = Annotation.Root({
  out: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  kind: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});
const tg = new StateGraph(TS)
  .addNode("ask", () => {
    const a: any = interrupt("给个值");
    return { out: JSON.stringify(a), kind: Array.isArray(a) ? "array" : typeof a };
  })
  .addEdge(START, "ask")
  .addEdge("ask", END)
  .compile({ checkpointer: new MemorySaver() });

let n = 0;
for (const v of ["字符串", 123, { a: 1 }, ["x", "y"], true]) {
  n += 1;
  const tcfg = { configurable: { thread_id: `type-${n}` } };
  await tg.invoke({ out: "", kind: "" }, tcfg);
  const r: any = await tg.invoke(new Command({ resume: v }), tcfg);
  console.log(`  resume=${JSON.stringify(v)} -> out=${r.out} kind=${r.kind}`);
}
for (const v of ["", 0, false, null]) {
  const tcfg = { configurable: { thread_id: `falsy-${String(v)}` } };
  await tg.invoke({ out: "", kind: "" }, tcfg);
  try {
    const r: any = await tg.invoke(new Command({ resume: v as any }), tcfg);
    console.log(`  resume=${JSON.stringify(v)} -> 成功 out=${r.out}`);
  } catch (e) {
    console.log(`  resume=${JSON.stringify(v)} -> 报错: ${(e as Error).message.slice(0, 70)}`);
  }
}

// ---------------------------------------------------------------------------
// 验证十二：循环内多次 interrupt
// ---------------------------------------------------------------------------
line("验证十二：同一个节点里循环审批");

const LS = Annotation.Root({
  items: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  done: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});
const lg = new StateGraph(LS)
  .addNode("loop", (s: typeof LS.State) => {
    const done: string[] = [];
    for (const it of s.items) {
      const ans = interrupt(`处理 ${it}?`);
      done.push(`${it}:${ans}`);
    }
    return { done };
  })
  .addEdge(START, "loop")
  .addEdge("loop", END)
  .compile({ checkpointer: new MemorySaver() });

const lcfg = { configurable: { thread_id: "loop1" } };
let lr: any = await lg.invoke({ items: ["A", "B", "C"], done: [] }, lcfg);
const answers = ["yes", "no", "maybe"];
let round = 1;
while (lr.__interrupt__?.length) {
  console.log(`  第 ${round} 次中断:`, JSON.stringify(lr.__interrupt__.map((i: any) => i.value)), " 累计 done =", JSON.stringify(lr.done));
  lr = await lg.invoke(new Command({ resume: answers[round - 1] }), lcfg);
  round += 1;
}
console.log("  循环结束:", JSON.stringify(lr));

// ---------------------------------------------------------------------------
// 验证十三：多节点依次中断
// ---------------------------------------------------------------------------
line("验证十三：多个节点各中断一次");

const MS = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
const mg = new StateGraph(MS)
  .addNode("n1", () => {
    const a = interrupt("第一步审批");
    return { log: [`n1:${a}`] };
  })
  .addNode("n2", () => {
    const a = interrupt("第二步审批");
    return { log: [`n2:${a}`] };
  })
  .addEdge(START, "n1")
  .addEdge("n1", "n2")
  .addEdge("n2", END)
  .compile({ checkpointer: new MemorySaver() });

const mcfg = { configurable: { thread_id: "multi1" } };
let mr: any = await mg.invoke({ log: [] }, mcfg);
let k = 1;
while (mr.__interrupt__?.length) {
  console.log(`  第 ${k} 次: interrupts =`, JSON.stringify(mr.__interrupt__.map((i: any) => i.value)), " log =", JSON.stringify(mr.log));
  mr = await mg.invoke(new Command({ resume: `r${k}` }), mcfg);
  k += 1;
}
console.log("  多节点结束:", JSON.stringify(mr));

// ---------------------------------------------------------------------------
// 验证十四：resume 一个没中断的线程
// ---------------------------------------------------------------------------
line("验证十四：resume 一个还没中断过的线程");

const RS = Annotation.Root({
  approved: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  tries: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});
const rg = new StateGraph(RS)
  .addNode("pay", (s: typeof RS.State) => {
    const a = interrupt("批准吗？");
    return { approved: String(a), tries: s.tries + 1 };
  })
  .addEdge(START, "pay")
  .addEdge("pay", END)
  .compile({ checkpointer: new MemorySaver() });

const freshCfg = { configurable: { thread_id: "fresh1" } };
const fresh: any = await rg.invoke(new Command({ resume: "直接答" }), freshCfg);
console.log("  结果:", JSON.stringify(fresh));
console.log("  __interrupt__:", JSON.stringify(fresh.__interrupt__), "  ← TS 直接返回初始状态，节点没跑");
const fst2: any = await rg.getState(freshCfg);
console.log("  之后 getState.next =", JSON.stringify(fst2.next), " tasks[0].interrupts =", JSON.stringify(fst2.tasks?.[0]?.interrupts));

// ---------------------------------------------------------------------------
// 验证十五：Command(resume, update) 同用
// ---------------------------------------------------------------------------
line("验证十五：Command(resume=, update=) 同用");

const R2S = Annotation.Root({
  approved: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  tries: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});
const r2g = new StateGraph(R2S)
  .addNode("pay", (s: typeof R2S.State) => {
    const a = interrupt("批准吗？");
    return { approved: String(a), tries: s.tries + 1 };
  })
  .addEdge(START, "pay")
  .addEdge("pay", END)
  .compile({ checkpointer: new MemorySaver() });
const r2cfg = { configurable: { thread_id: "ru1" } };
await r2g.invoke({ approved: "", tries: 0 }, r2cfg);
const r2r: any = await r2g.invoke(new Command({ resume: "通过", update: { tries: 99 } }), r2cfg);
console.log("  结果:", JSON.stringify(r2r), "  ← update 先应用成 99，又被节点 return 覆盖成 100");

// ---------------------------------------------------------------------------
// 验证十六：checkpoint 数量与历史（恢复后再看一次）
// ---------------------------------------------------------------------------
line("验证十六：恢复后的 checkpoint 历史");

const finalHist: any[] = [];
for await (const h of await g.getStateHistory(cfg)) finalHist.push(h);
console.log("  恢复后条数:", finalHist.length, " （中断时 2 条，恢复后 3 条）");
finalHist.forEach((h, i) => console.log(`   [${i}] next=${JSON.stringify(h.next)} values=${JSON.stringify(h.values)}`));

console.log("\n全部验证跑完。");
