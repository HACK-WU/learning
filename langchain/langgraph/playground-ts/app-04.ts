// 应用实战 04 · Pregel 执行模型（TypeScript 侧）
// 对照：../../应用实战/04-Pregel 执行模型.md
// 运行：npm run a04
import { Annotation, Command, END, START, Send, StateGraph } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

const DOCS: Record<string, string> = {
  doc1: "退款政策：签收后 7 天内可申请，商品需未使用。",
  doc2: "发票政策：电子发票在订单完成后 24 小时内开出。",
  doc3: "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
};

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：固定三份，串行处理");
{
  const State = Annotation.Root({
    docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
    summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const g = new StateGraph(State)
    .addNode("summarize", (s) => ({
      summaries: Object.entries(s.docs).map(([name, text]) => `[${name}] ${text.split("：")[0]}`),
    }))
    .addNode("merge", (s) => ({ report: s.summaries.join(" / ") }))
    .addEdge(START, "summarize")
    .addEdge("summarize", "merge")
    .addEdge("merge", END)
    .compile();

  const r = await g.invoke({ docs: DOCS, summaries: [], report: "" });
  console.log("报告：", r.report);
  console.log("摘要份数：", r.summaries.length);
}

// ---------------------------------------------------------------- 第 2 跳
line("第 2 跳：份数不定，用 Send 扇出");
{
  const State = Annotation.Root({
    docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
    doc_name: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    doc_text: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const fanOut = (s: typeof State.State) =>
    Object.entries(s.docs).map(
      ([name, text]) => new Send("summarize", { doc_name: name, doc_text: text })
    );

  const g = new StateGraph(State)
    .addNode("summarize", (s) => ({
      summaries: [`[${s.doc_name}] ${s.doc_text.split("：")[0]}`],
    }))
    .addNode("merge", (s) => ({ report: [...s.summaries].sort().join(" / ") }))
    .addConditionalEdges(START, fanOut, ["summarize"])
    .addEdge("summarize", "merge")
    .addEdge("merge", END)
    .compile();

  const MORE_DOCS = { ...DOCS, doc4: "会员政策：...", doc5: "售后政策：..." };
  for (const docs of [DOCS, MORE_DOCS]) {
    const r = await g.invoke({ docs, summaries: [], report: "" });
    console.log(`${Object.keys(docs).length} 份 ->`, r.report);
  }
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：合并后总检，用 Command 一次干两件事");
{
  const MIN_SUMMARIES = 3;
  const MAX_ROUNDS = 2;

  const State = Annotation.Root({
    docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
    doc_name: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    doc_text: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    rounds: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const fanOut = (s: typeof State.State) => {
    if (s.rounds.length >= MAX_ROUNDS) return "review";
    return Object.entries(s.docs).map(
      ([k, v]) => new Send("summarize", { doc_name: k, doc_text: v })
    );
  };

  const review = (s: typeof State.State) => {
    const ok = s.summaries.length >= MIN_SUMMARIES;
    if (ok || s.rounds.length >= MAX_ROUNDS) {
      return new Command({
        update: { report: [...s.summaries].sort().join(" / ") },
        goto: END,
      });
    }
    return new Command({ update: { rounds: ["重做一轮"] }, goto: "fan_out_again" });
  };

  const g = new StateGraph(State)
    .addNode("fan_out_again", (s) =>
      Object.entries(s.docs).map(
        ([k, v]) => new Send("summarize", { doc_name: k, doc_text: v })
      )
    )
    .addNode("summarize", (s) => ({
      summaries: s.doc_name ? [`[${s.doc_name}] ${s.doc_text.split("：")[0]}`] : [],
    }))
    // TS 侧节点返回 Command 跳转时，必须用 ends 声明所有可能目标
    .addNode("review", review, { ends: ["fan_out_again", END] })
    .addConditionalEdges(START, fanOut, ["summarize", "review"])
    .addEdge("summarize", "review")
    .addEdge("fan_out_again", "summarize")
    .compile();

  const r = await g.invoke(
    { docs: DOCS, doc_name: "", doc_text: "", summaries: [], rounds: [], report: "" },
    { recursionLimit: 50 }
  );
  console.log("报告：", r.report);
  console.log("摘要份数：", r.summaries.length);
}

// ---------------------------------------------------------------- goto 拼错
line("把 Command 的 goto 拼错（不带 ends 声明）");
{
  const State = Annotation.Root({
    report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    rounds: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });

  const review = (_s: typeof State.State) =>
    new Command({ update: { report: "..." }, goto: "ende" });

  try {
    const g = new StateGraph(State)
      .addNode("review", review)
      .addEdge(START, "review")
      .compile();
    console.log("  编译通过（TS 侧不用 ends 也能过）");
    const r = await g.invoke({});
    console.log("  invoke 返回：", JSON.stringify(r));
  } catch (e: any) {
    console.log("  报错:", e.name, "-", String(e.message).split("\n")[0]);
  }
  console.log("  -> 与 Python 一致：不带 ends 声明时，拼错的目标被静默忽略，invoke 正常返回");
}

// ------------------------------------------- ends 写错（对应课文第 3 跳的护栏）
line('给 Command 节点写 ends: ["fan_out_again", "ende"]（ende 是拼错的）');
{
  const State = Annotation.Root({
    docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
    summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    rounds: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const review = (_s: typeof State.State) =>
    new Command({ update: { report: "..." }, goto: "ende" });

  try {
    new StateGraph(State)
      .addNode("fan_out_again", () => ({}))
      .addNode("summarize", () => ({}))
      // ends 里的节点名会被校验
      .addNode("review", review, { ends: ["fan_out_again", "ende"] })
      .addEdge(START, "review")
      .addEdge("summarize", "review")
      .addEdge("fan_out_again", "summarize")
      .compile();
    console.log("  没有报错（不符合预期）");
  } catch (e: any) {
    console.log("  编译期报错:", e.name + ":", String(e.message).split("\n")[0]);
  }
  console.log("  -> ends 里的节点名会被校验，相当于 Python 的 Literal 护栏");
}
