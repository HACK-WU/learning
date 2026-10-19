// 应用实战 08 · Interrupts 人在环中（TypeScript 侧）
// 对照：../../应用实战/08-Interrupts 人在环中.md
// 运行：npm run a08
import {
  Annotation,
  Command,
  END,
  interrupt,
  MemorySaver,
  START,
  StateGraph,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

// 等价于 Python 的 str(v)：字符串原样，对象转 JSON 串
const asText = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));

const Refund = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  approved: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  status: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  done: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const lookup = (s: typeof Refund.State) => ({
  status: `订单${s.order_id}金额${s.amount}`,
});

const refund = (s: typeof Refund.State) => {
  const answer = interrupt({ 问: `确认退款 ${s.amount} 元？`, order_id: s.order_id });
  return { approved: asText(answer) };
};

const graph = new StateGraph(Refund)
  .addNode("查订单", lookup)
  .addNode("退款", refund)
  .addEdge(START, "查订单")
  .addEdge("查订单", "退款")
  .addEdge("退款", END)
  .compile({ checkpointer: new MemorySaver() }); // ← 必须有

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：在付款前卡一道审批");
{
  const cfg = { configurable: { thread_id: "order-001" } };
  const result = await graph.invoke({ order_id: "A100", amount: 5000 }, cfg);
  console.log("中断返回:", JSON.stringify(result));

  const st = await graph.getState(cfg);
  console.log("next  =", JSON.stringify(st.next));
  console.log("values=", JSON.stringify(st.values));

  // 从 tasks[0].interrupts 取问题（Python 是 st.interrupts）
  console.log("tasks[0].interrupts =", JSON.stringify(st.tasks[0].interrupts));

  const r2 = await graph.invoke(new Command({ resume: "批准" }), cfg);
  console.log("恢复后:", JSON.stringify(r2));
}

// ---------------------------------------------------------------- 第 2 跳·坑 1
line("第 2 跳 坑 1：副作用放在 interrupt 之前");
{
  const charges: number[] = [];

  const refundBad = (s: typeof Refund.State) => {
    charges.push(s.amount); // ← 副作用在 interrupt 之前
    console.log(`  [真的扣款了] ${s.amount} 元，累计扣款 ${charges.length} 次`);
    const answer = interrupt("确认退款？");
    return { approved: asText(answer) };
  };

  const gBad = new StateGraph(Refund)
    .addNode("查订单", lookup)
    .addNode("退款", refundBad)
    .addEdge(START, "查订单")
    .addEdge("查订单", "退款")
    .addEdge("退款", END)
    .compile({ checkpointer: new MemorySaver() });

  const cfg = { configurable: { thread_id: "order-002" } };
  await gBad.invoke({ order_id: "A200", amount: 100 }, cfg);
  console.log("--- 人批准 ---");
  await gBad.invoke(new Command({ resume: "批准" }), cfg);
  console.log("总共扣款次数:", charges.length);
  console.log("  -> 恢复不是「接着跑」，是「从头重跑」");
}

// ---------------------------------------------------------------- 第 2 跳·坑 2
line("第 2 跳 坑 2：用 updateState 填审批");
{
  const cfg = { configurable: { thread_id: "order-003" } };
  await graph.invoke({ order_id: "A300", amount: 300 }, cfg);

  for (let i = 0; i < 3; i++) {
    await graph.updateState(cfg, { approved: `同意${i}` });
    const r: any = await graph.invoke(null, cfg);
    const n = (r.__interrupt__ ?? []).length;
    console.log(`第 ${i + 1} 轮: 又中断 ${n} 次, values=${r.approved}`);
  }
  console.log("  -> updateState 不消中断，可以无限重复");
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：多道审批 + 副作用归位");
{
  const audit: unknown[] = [];

  const Flow = Annotation.Root({
    order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    amount: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    done: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const lookup2 = (s: typeof Flow.State) => ({ log: [`查到订单${s.order_id}`] });

  const csReview = (s: typeof Flow.State) => {
    const ans = interrupt({ 问: "客服确认退款？", 金额: s.amount }); // ① 第一道
    return { log: [`客服:${asText(ans)}`] };
  };

  const mgrReview = (s: typeof Flow.State) => {
    if (s.amount <= 1000) return { log: ["主管:免审"] }; // 小额不用主管
    const ans = interrupt({ 问: "金额超 1000，主管确认？", 金额: s.amount }); // ② 第二道
    return { log: [`主管:${asText(ans)}`] };
  };

  const doRefund = (s: typeof Flow.State) => {
    audit.push({ order: s.order_id, amount: s.amount }); // ← 副作用
    return { log: ["已退款"], done: "完成" };
  };

  const notify = (s: typeof Flow.State) => {
    audit.push({ notify: s.order_id }); // ← 副作用
    return { log: ["已通知"] };
  };

  const g = new StateGraph(Flow)
    .addNode("查订单", lookup2)
    .addNode("客服审批", csReview)
    .addNode("主管审批", mgrReview)
    .addNode("执行退款", doRefund)
    .addNode("发通知", notify)
    .addEdge(START, "查订单")
    .addEdge("查订单", "客服审批")
    .addEdge("客服审批", "主管审批")
    .addEdge("主管审批", "执行退款")
    .addEdge("执行退款", "发通知")
    .addEdge("发通知", END)
    .compile({ checkpointer: new MemorySaver() });

  const cfg = { configurable: { thread_id: "order-100" } };
  // 前端交互循环：一直问到人答完
  let result: any = await g.invoke({ order_id: "B100", amount: 5000 }, cfg);
  let round = 0;
  while ((result.__interrupt__ ?? []).length > 0) {
    round++;
    const q = result.__interrupt__[0].value;
    console.log(`第 ${round} 轮 问题: ${JSON.stringify(q)}`);
    result = await g.invoke(
      new Command({ resume: { decision: "approved", by: `user${round}` } }),
      cfg
    );
  }
  console.log("最终:", JSON.stringify(result));
  console.log("副作用执行次数:", audit.length, JSON.stringify(audit));

  // 小额免审
  const cfg2 = { configurable: { thread_id: "order-200" } };
  let r: any = await g.invoke({ order_id: "B200", amount: 300 }, cfg2);
  let n = 0;
  while ((r.__interrupt__ ?? []).length > 0) {
    n++;
    r = await g.invoke(new Command({ resume: "ok" }), cfg2);
  }
  console.log(`300 元：只问了 ${n} 次 ->`, JSON.stringify(r.log));

  // 流式里看中断
  const cfg3 = { configurable: { thread_id: "order-300" } };
  for await (const chunk of await g.stream(
    { order_id: "B300", amount: 800 },
    { ...cfg3, streamMode: "updates" }
  )) {
    if ("__interrupt__" in (chunk as object)) {
      const q = ((chunk as any).__interrupt__[0]).value;
      console.log(`  [弹出审批卡片] ${JSON.stringify(q)}`);
    } else {
      console.log(`  [步骤完成] ${Object.keys(chunk as object)[0]}`);
    }
  }
}

// ---------------------------------------------------------------- 补充：空 resume
line("补充：resume 传假值会被拒");
{
  const cfg = { configurable: { thread_id: "order-400" } };
  await graph.invoke({ order_id: "A400", amount: 50 }, cfg);
  for (const v of ["", 0, false, null]) {
    try {
      await graph.invoke(new Command({ resume: v }), cfg);
      console.log(`  resume=${JSON.stringify(v)} 未报错`);
    } catch (e: any) {
      console.log(`  resume=${JSON.stringify(v)} ->`, e.name + ":", e.message.split("\n")[0]);
    }
  }
}
