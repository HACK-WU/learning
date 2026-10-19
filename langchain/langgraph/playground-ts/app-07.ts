// 应用实战 07 · Streaming 流式输出（TypeScript 侧）
// 对照：../../应用实战/07-Streaming 流式输出.md
// 运行：npm run a07
import { Annotation, END, getWriter, START, StateGraph } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  docs: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  draft: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  final: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const retrieve = () => ({ docs: ["文档A", "文档B"] });
const generate = (s: typeof State.State) => ({ draft: `基于${s.docs.length}篇的草稿` });
const proofread = (s: typeof State.State) => ({ final: s.draft + "（已校对）" });

const builder = new StateGraph(State)
  .addNode("检索", retrieve)
  .addNode("生成", generate)
  .addNode("校对", proofread)
  .addEdge(START, "检索")
  .addEdge("检索", "生成")
  .addEdge("生成", "校对")
  .addEdge("校对", END);
const graph = builder.compile();

const inp = { question: "怎么退款", docs: [], draft: "", final: "" };

// ---------------------------------------------------------------- 第 1 跳
line("第 1 跳：invoke vs stream(updates)");
{
  const r = await graph.invoke(inp);
  console.log("--- invoke（只有终态）---");
  console.log(r.final);

  console.log("--- stream(updates)（逐节点）---");
  for await (const chunk of await graph.stream(inp, { streamMode: "updates" })) {
    const node = Object.keys(chunk as object)[0];
    console.log(`  完成：${node}`);
  }

  console.log("--- stream(values)（全量重发）---");
  for await (const chunk of await graph.stream(inp, { streamMode: "values" })) {
    console.log("  ", chunk);
  }
}

// ---------------------------------------------------------------- 第 2 跳
line("第 2 跳：节点里主动喊话（custom）");
{
  // TS 用 getWriter()，不是 Python 的 get_stream_writer()
  const retrieveV2 = () => {
    const w = getWriter()!;
    const found: string[] = [];
    ["文档A", "文档B", "文档C"].forEach((name, i) => {
      found.push(name);
      w({ step: "检索", current: i + 1, total: 3, msg: `查到 ${name}` });
    });
    return { docs: found };
  };

  const generateV2 = (s: typeof State.State) => {
    const w = getWriter()!;
    w({ step: "生成", progress: 0.5, msg: "写了一半" });
    w({ step: "生成", progress: 1.0, msg: "写完了" });
    return { draft: `基于${s.docs.length}篇的草稿` };
  };

  const builder2 = new StateGraph(State)
    .addNode("检索", retrieveV2)
    .addNode("生成", generateV2)
    .addNode("校对", proofread)
    .addEdge(START, "检索")
    .addEdge("检索", "生成")
    .addEdge("生成", "校对")
    .addEdge("校对", END);
  const graph2 = builder2.compile();

  console.log("--- stream(custom)：节点里喊的话 ---");
  for await (const data of await graph2.stream(inp, { streamMode: "custom" })) {
    console.log("  ", data);
  }

  console.log("--- 不声明 custom，用 values 收 ---");
  const lost: unknown[] = [];
  for await (const c of await graph2.stream(inp, { streamMode: "values" })) lost.push(c);
  console.log("  values 收到 chunk 数:", lost.length, "（custom 数据全丢）");

  console.log("--- 两个模式一起要 ---");
  for await (const [mode, chunk] of await graph2.stream(inp, {
    streamMode: ["updates", "custom"],
  }) as any) {
    if (mode === "custom") console.log(`  进度 ${JSON.stringify(chunk)}`);
    else console.log(`  完成 ${Object.keys(chunk as object)[0]}`);
  }
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：子图里的进度");
{
  const SubState = Annotation.Root({
    docs: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
    draft: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const subSearch = (s: typeof SubState.State) => {
    const w = getWriter()!;
    w({ from: "子图-查资料", progress: 0.5 });
    return { docs: [...(s.docs ?? []), "补充文档"] };
  };
  const subWrite = (s: typeof SubState.State) => {
    const w = getWriter()!;
    w({ from: "子图-写草稿", progress: 1.0 });
    return { draft: `基于${s.docs.length}篇的草稿` };
  };

  const sub = new StateGraph(SubState)
    .addNode("查资料", subSearch)
    .addNode("写草稿", subWrite)
    .addEdge(START, "查资料")
    .addEdge("查资料", "写草稿")
    .addEdge("写草稿", END)
    .compile();

  const retrieveV2 = () => {
    const w = getWriter()!;
    const found: string[] = [];
    ["文档A", "文档B", "文档C"].forEach((name, i) => {
      found.push(name);
      w({ step: "检索", current: i + 1, total: 3, msg: `查到 ${name}` });
    });
    return { docs: found };
  };

  // 父图：把编译好的子图直接当节点（call 子图）
  const generateV3 = async (s: typeof State.State) => {
    const r = await sub.invoke({ docs: s.docs, draft: "" });
    return { draft: r.draft };
  };

  const builder3 = new StateGraph(State)
    .addNode("检索", retrieveV2)
    .addNode("生成", generateV3)
    .addNode("校对", proofread)
    .addEdge(START, "检索")
    .addEdge("检索", "生成")
    .addEdge("生成", "校对")
    .addEdge("校对", END);
  const graph3 = builder3.compile();

  console.log("--- 不开 subgraphs：子图的 custom 收不到 ---");
  const none: unknown[] = [];
  for await (const d of await graph3.stream(inp, { streamMode: "custom" })) none.push(d);
  console.log("  ", JSON.stringify(none));

  console.log("--- 开 subgraphs=true ---");
  for await (const [ns, data] of await graph3.stream(inp, {
    streamMode: "custom",
    subgraphs: true,
  }) as any) {
    const where = (ns as string[]).map((n) => n.split(":")[0]).join("/") || "主图";
    console.log(`  [${where}] ${JSON.stringify(data)}`);
  }

  console.log("--- 多模式 + subgraphs：三元组 ---");
  for await (const [ns, mode, payload] of await graph3.stream(inp, {
    streamMode: ["updates", "custom"],
    subgraphs: true,
  }) as any) {
    const where = (ns as string[]).map((n) => n.split(":")[0]).join("/") || "主图";
    if (mode === "custom") console.log(`  进度条 [${where}] ${JSON.stringify(payload)}`);
    else console.log(`  步骤条 [${where}] 完成 ${Object.keys(payload as object)[0]}`);
  }

  console.log("--- 用二元组解包会怎样 ---");
  {
    let n = 0;
    let sample: unknown = null;
    try {
      for await (const [a, b] of await graph3.stream(inp, {
        streamMode: ["updates", "custom"],
        subgraphs: true,
      }) as any) {
        if (n === 0) sample = { a, b };
        n++;
      }
      console.log("  没报错，共", n, "条；第一条解成 [a,b] =", JSON.stringify(sample));
    } catch (e: any) {
      console.log("  ", e.name + ":", e.message);
    }
  }
}
