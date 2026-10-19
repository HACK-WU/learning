// 应用实战 03 · Graph API 第一个图（TypeScript 侧）
// 对照：../../应用实战/03-Graph API 第一个图.md
// 运行：npm run a03
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：一次通过");
{
  const KNOWLEDGE: Record<string, string> = {
    退款: "退款需在签收后 7 天内申请，且商品未使用。",
  };

  const State = Annotation.Root({
    question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const g = new StateGraph(State)
    // TS 侧节点名不能与状态字段同名（课 3 已记录），故用 generate 而非 answer
    .addNode("generate", (s) => ({
      answer: KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。",
    }))
    .addEdge(START, "generate")
    .addEdge("generate", END)
    .compile();

  console.log(await g.invoke({ question: "退款", answer: "" }));
  console.log(await g.invoke({ question: "怎么申请发票", answer: "" }));
}

// ---------------------------------------------------------------- 第 2 跳
line("第 2 跳：加质检与回退");
{
  const KNOWLEDGE: Record<string, string> = {
    退款: "退款需在签收后 7 天内申请，且商品未使用。",
  };

  const State = Annotation.Root({
    question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    // 累加：每版都留着（等价于 Python 的 Annotated[list[str], add]）
    history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const draft = (s: typeof State.State) => {
    const n = s.history.length;
    const ans =
      n === 0
        ? (KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。")
        : (KNOWLEDGE[s.question.trim()] ??
          `关于「${s.question}」，我目前没有可靠信息，已为您转人工。`);
    return { answer: ans, history: [`第${n + 1}版：${ans}`] };
  };

  const check = (s: typeof State.State) => ({
    verdict: s.answer === "您好，已收到您的反馈。" ? "打回" : "通过",
  });

  const route = (s: typeof State.State) => (s.verdict === "通过" ? END : "draft");

  const g = new StateGraph(State)
    .addNode("draft", draft)
    .addNode("check", check)
    .addEdge(START, "draft")
    .addEdge("draft", "check")
    .addConditionalEdges("check", route, ["draft", END])
    .compile();

  const r = await g.invoke({
    question: "怎么申请发票",
    answer: "",
    history: [],
    verdict: "",
  });
  console.log("最终回复：", r.answer);
  console.log("改写历史：");
  for (const h of r.history) console.log("  -", h);
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：加上限与兜底");
{
  const MAX_ROUNDS = 3;
  const KNOWLEDGE: Record<string, string> = {
    退款: "退款需在签收后 7 天内申请，且商品未使用。",
  };

  const State = Annotation.Root({
    question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const draft = (s: typeof State.State) => {
    const n = s.history.length;
    let ans: string;
    if (n === 0) {
      ans = KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。";
    } else if (n < MAX_ROUNDS - 1) {
      ans =
        KNOWLEDGE[s.question.trim()] ??
        `关于「${s.question}」，我目前没有可靠信息，已为您转人工。`;
    } else {
      ans = "抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。";
    }
    return { answer: ans, history: [`第${n + 1}版：${ans}`] };
  };

  const check = (s: typeof State.State) => ({
    verdict: s.history.length < MAX_ROUNDS ? "打回" : "通过",
  });

  const route = (s: typeof State.State) => {
    if (s.verdict === "通过") return END;
    if (s.history.length >= MAX_ROUNDS) return END;
    return "draft";
  };

  const g = new StateGraph(State)
    .addNode("draft", draft)
    .addNode("check", check)
    .addEdge(START, "draft")
    .addEdge("draft", "check")
    .addConditionalEdges("check", route, ["draft", END])
    .compile();

  const r = await g.invoke(
    { question: "怎么申请发票", answer: "", history: [], verdict: "" },
    { recursionLimit: 25 }
  );
  console.log("最终回复：", r.answer);
  console.log("共改写：", r.history.length, "版");
  console.log("三版历史：");
  for (const h of r.history) console.log("  -", h);
}

// ---------------------------------------------------------------- 拆掉保险丝
line("拆掉保险丝：只留 return \"draft\"");
{
  const MAX_ROUNDS = 3;
  const State = Annotation.Root({
    question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const g = new StateGraph(State)
    .addNode("draft", (s) => {
      const n = s.history.length;
      return { answer: "x", history: [`第${n + 1}版`] };
    })
    .addNode("check", () => ({ verdict: "打回" }))
    .addEdge(START, "draft")
    .addEdge("draft", "check")
    .addConditionalEdges("check", () => "draft" as const, ["draft"])
    .compile();

  try {
    await g.invoke(
      { question: "怎么申请发票", answer: "", history: [], verdict: "" },
      { recursionLimit: 25 }
    );
    console.log("  没有抛错（不符合预期）");
  } catch (e: any) {
    console.log("  ", e.name + ":", String(e.message).split("\n")[0]);
  }
  console.log("  -> 与 Python 一致：超限是抛异常，不是返回兜底回复");
  console.log("  MAX_ROUNDS =", MAX_ROUNDS);
}
