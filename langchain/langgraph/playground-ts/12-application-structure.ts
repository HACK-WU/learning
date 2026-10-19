// 课 12 · Application structure 与测试（TypeScript 侧）
// 对照：../../playground/12_application_structure.py（Python 侧）
// 运行：npm run l12
import {
  Annotation,
  Command,
  END,
  interrupt,
  MemorySaver,
  START,
  StateGraph,
} from "@langchain/langgraph";
import { FakeListChatModel } from "@langchain/core/utils/testing";
import { AIMessage } from "@langchain/core/messages";

const line = (t: string) => console.log(`\n===== ${t} =====`);
const show = (v: unknown) => JSON.stringify(v);

// ---------------------------------------------------------------- 验证零
line("验证零：模型塞进 State（TS 侧）");
{
  const S = Annotation.Root({
    messages: Annotation<any[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const g = new StateGraph(S)
    .addNode("n", (s: any) => ({ messages: [] }))
    .addEdge(START, "n")
    .addEdge("n", END)
    .compile();
  try {
    const fake = new FakeListChatModel({ responses: ["x"] });
    const r: any = await g.invoke({ messages: [], model: fake } as any);
    console.log("  传了未声明键 model，结果 keys =", Object.keys(r));
    console.log("  -> 没报错，多出来的键被丢弃（不是 KeyError）");
    const s: any = await g.getState({ configurable: { thread_id: "x" } });
    console.log("  存档里的值 =", show(s.values));
  } catch (e: any) {
    console.log("  报错:", e.name, "-", String(e.message).split("\n")[0]);
  }
}

// ---------------------------------------------------------------- 验证十一
line("验证十一：假模型 + config 注入");
{
  const S = Annotation.Root({
    messages: Annotation<any[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const g = new StateGraph(S)
    .addNode("llm", async (s: any, config: any) => {
      const model = config?.configurable?.model;
      console.log("  config.configurable 的键 =", Object.keys(config.configurable ?? {}));
      const resp = await model.invoke(s.messages ?? []);
      return { messages: [...(s.messages ?? []), resp] };
    })
    .addEdge(START, "llm")
    .addEdge("llm", END)
    .compile();

  const fake = new FakeListChatModel({ responses: ["固定回复"] });
  const r: any = await g.invoke({ messages: [] }, { configurable: { model: fake } });
  console.log("  用假模型 ->", r.messages.map((m: any) => m.content));
}

// ---------------------------------------------------------------- 验证十二
line("验证十二：假模型能不能复用（TS 与 Python 相反）");
{
  const fake = new FakeListChatModel({ responses: ["A", "B"] });
  const outs: string[] = [];
  for (let i = 0; i < 4; i += 1) {
    const m: any = await fake.invoke([{ role: "user", content: "hi" }]);
    outs.push(m.content as string);
  }
  console.log("  连续 4 次 invoke ->", outs);
  console.log("  -> 用尽后回到第 0 条（循环），不会抛 StopIteration");
}

// ---------------------------------------------------------------- 验证十三
line("验证十三：断言轨迹（埋桩）");
{
  const S = Annotation.Root({
    v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const trace: string[] = [];
  const g = new StateGraph(S)
    .addNode("s1", (s: any) => { trace.push("s1"); return { v: (s.v ?? 0) + 1 }; })
    .addNode("s2", (s: any) => { trace.push("s2"); return { v: (s.v ?? 0) * 10 }; })
    .addConditionalEdges("s1", (s: any) => {
      trace.push("route");
      return s.v > 0 ? "s2" : END;
    }, ["s2", END])
    .addEdge(START, "s1")
    .addEdge("s2", END)
    .compile();
  const r: any = await g.invoke({ v: 0 });
  console.log("  结果:", show({ v: r.v }));
  console.log("  轨迹:", show(trace));
}

// ---------------------------------------------------------------- 验证十四
line("验证十四：断言轨迹（不埋桩，streamMode: updates）");
{
  const S = Annotation.Root({
    v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const g2 = new StateGraph(S)
    .addNode("s1", (s: any) => ({ v: (s.v ?? 0) + 1 }))
    .addNode("s2", (s: any) => ({ v: (s.v ?? 0) * 10 }))
    .addEdge(START, "s1")
    .addEdge("s1", "s2")
    .addEdge("s2", END)
    .compile();
  const steps: string[] = [];
  for await (const c of await g2.stream({ v: 0 }, { streamMode: "updates" })) {
    steps.push(Object.keys(c as any)[0]);
  }
  console.log("  updates 轨迹:", show(steps));
}

// ---------------------------------------------------------------- 验证十五
line("验证十五：测 interrupt");
{
  const S = Annotation.Root({
    v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const g3 = new StateGraph(S)
    .addNode("ask", (s: any) => {
      const ans: any = interrupt({ question: "批准吗", v: s.v });
      return { v: (s.v ?? 0) + (ans === "批准" ? 1 : 0) };
    })
    .addEdge(START, "ask")
    .addEdge("ask", END)
    .compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "t15" } };
  const r: any = await g3.invoke({ v: 0 }, cfg);
  console.log("  invoke keys =", Object.keys(r));
  console.log("  有 __interrupt__:", "__interrupt__" in r);
  console.log("  __interrupt__ 内容 =", show(r.__interrupt__?.[0]?.value));
  const r2: any = await g3.invoke(new Command({ resume: "批准" }), cfg);
  console.log("  resume ->", show({ v: r2.v }));
}

// ---------------------------------------------------------------- 验证十六
line("验证十六：非确定性");
{
  const S = Annotation.Root({
    v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  });
  const g4 = new StateGraph(S)
    .addNode("r", () => {
      const n = Math.floor(Math.random() * 3) + 1;
      return { v: n };
    })
    .addEdge(START, "r")
    .addEdge("r", END)
    .compile();
  const outs: number[] = [];
  for (let i = 0; i < 10; i += 1) {
    const r: any = await g4.invoke({ v: 0 });
    outs.push(r.v);
  }
  console.log("  10 次 invoke 结果:", show(outs));
  console.log("  -> 不稳定，不能直接写断言");
}

// ---------------------------------------------------------------- 验证十七
line("验证十七：cassette 回放（TS 侧写法）");
{
  const cassette = new Map<string, any>();
  let mode: "record" | "replay" = "record";
  let realCalls = 0;
  const fetchWeather = async (city: string) => {
    const key = `weather:${city}`;
    if (mode === "replay" && cassette.has(key)) {
      console.log("  [replay] 命中 cassette:", key);
      return cassette.get(key);
    }
    realCalls += 1;
    const data = { temp: 26, cond: "晴" };
    cassette.set(key, data);
    console.log("  [record] 真实调用一次:", key);
    return data;
  };
  console.log("  record 模式 ->", show(await fetchWeather("杭州")));
  mode = "replay";
  console.log("  replay 模式 ->", show(await fetchWeather("杭州")));
  console.log("  真实调用次数 =", realCalls);
}

// ---------------------------------------------------------------- 验证十八
line("验证十八：加节点（v2 补跑）");
{
  const S = Annotation.Root({
    x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const saver = new MemorySaver();
  const v1 = new StateGraph(S)
    .addNode("a", () => ({ x: 1, log: ["a"] }))
    .addNode("ask", () => {
      const ans: any = interrupt({ question: "批准吗" });
      return { log: [`ask=${ans}`] };
    })
    .addEdge(START, "a")
    .addEdge("a", "ask")
    .addEdge("ask", END)
    .compile({ checkpointer: saver });
  const cfg = { configurable: { thread_id: "t18" } };
  const r1: any = await v1.invoke({ x: 0 }, cfg);
  console.log("  v1 invoke ->", show({ x: r1.x, log: r1.log }), "有中断:", "__interrupt__" in r1);

  const v2 = new StateGraph(S)
    .addNode("a", () => ({ x: 1, log: ["a"] }))
    .addNode("ask", () => {
      const ans: any = interrupt({ question: "批准吗" });
      return { log: [`ask=${ans}`] };
    })
    .addNode("b", () => ({ log: ["b"] }))
    .addEdge(START, "a")
    .addEdge("a", "ask")
    .addEdge("ask", "b")
    .addEdge("b", END)
    .compile({ checkpointer: saver });
  const r2: any = await v2.invoke(new Command({ resume: "批准" }), cfg);
  console.log("  v2 resume ->", show({ x: r2.x, log: r2.log }));
}

// ---------------------------------------------------------------- 验证十九
line("验证十九：删节点（静默）");
{
  const S = Annotation.Root({
    x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const saver = new MemorySaver();
  const mk = (withAsk: boolean) => {
    const b = new StateGraph(S).addNode("a", () => ({ x: 1, log: ["a"] }));
    if (withAsk) {
      b.addNode("ask", () => {
        const ans: any = interrupt({ question: "批准吗" });
        return { log: [`ask=${ans}`] };
      })
        .addEdge(START, "a")
        .addEdge("a", "ask")
        .addEdge("ask", END);
    } else {
      b.addEdge(START, "a").addEdge("a", END);
    }
    return b.compile({ checkpointer: saver });
  };
  const cfg = { configurable: { thread_id: "t19" } };
  const g1 = mk(true);
  const r1: any = await g1.invoke({ x: 0 }, cfg);
  console.log("  有 ask 的版本跑到中断:", show({ x: r1.x, log: r1.log }), "有中断:", "__interrupt__" in r1);
  const g2 = mk(false);
  try {
    const r2: any = await g2.invoke(new Command({ resume: "批准" }), cfg);
    console.log("  无 ask 的版本 resume ->", show({ x: r2.x, log: r2.log }), "有中断:", "__interrupt__" in r2);
  } catch (e: any) {
    console.log("  无 ask 的版本 resume 报错:", e.name, "-", String(e.message).split("\n")[0]);
  }
}

// ---------------------------------------------------------------- 验证二十
line("验证二十：State 加字段");
{
  const V1 = Annotation.Root({
    x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const saver = new MemorySaver();
  const g1 = new StateGraph(V1)
    .addNode("a", () => ({ x: 1, log: ["a"] }))
    .addEdge(START, "a")
    .addEdge("a", END)
    .compile({ checkpointer: saver });
  const cfg = { configurable: { thread_id: "t20" } };
  const r1: any = await g1.invoke({ x: 0 }, cfg);
  console.log("  v1 跑一轮:", show({ x: r1.x, log: r1.log }));

  const V2 = Annotation.Root({
    x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    y: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });
  const g2 = new StateGraph(V2)
    .addNode("a", () => ({ x: 1, log: ["a"] }))
    .addEdge(START, "a")
    .addEdge("a", END)
    .compile({ checkpointer: saver });
  const st: any = await g2.getState(cfg);
  console.log("  v2 读老 thread ->", show(st.values));
  console.log("  新字段 y 的值 =", st.values.y, "（类型:", typeof st.values.y, "）");
}

// ---------------------------------------------------------------- 验证二十一
line("验证二十一：checkpoint_ns 当版本号");
{
  const S = Annotation.Root({
    x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const g = new StateGraph(S)
    .addNode("a", () => ({ x: 1, log: ["a"] }))
    .addEdge(START, "a")
    .addEdge("a", END)
    .compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "t21" } };
  const r: any = await g.invoke({ x: 0 }, cfg);
  console.log("  默认 ns 回读:", show({ x: r.x, log: r.log }));
  try {
    const st: any = await g.getState({ configurable: { thread_id: "t21", checkpoint_ns: "v2" } });
    console.log("  ns=v2 回读:", show(st.values), "next =", show(st.next));
  } catch (e: any) {
    console.log("  ns=v2 回读报错:", e.name, "-", String(e.message).split("\n")[0]);
  }
}

// ---------------------------------------------------------------- 验证二十二
line("验证二十二：SqliteSaver / State(dict) —— Python 专属，TS 无对等物");
{
  console.log("  Python 侧：SqliteSaver.from_conn_string 返回上下文管理器，直接传 compile 抛 TypeError");
  console.log("  TS 侧：没有 SqliteSaver 这个同步工厂，等价的 @langchain/langgraph-checkpoint-sqlite");
  console.log("         用 new SqliteSaver(db) 实例，不存在 from_conn_string 误用问题（E6 能力缺口）");
}

// ---------------------------------------------------------------- 验证二十三
line("验证二十三：空状态 schema");
{
  try {
    const g = new StateGraph({} as any)
      .addNode("a", () => ({ v: 1 }))
      .addEdge(START, "a")
      .addEdge("a", END)
      .compile();
    const r: any = await g.invoke({});
    console.log("  空 schema 编译 + 运行 ->", show(r), "keys =", Object.keys(r));
  } catch (e: any) {
    console.log("  空 schema 报错:", e.name, "-", String(e.message).split("\n")[0]);
  }
}

// ---------------------------------------------------------------- 收束
line("小结：TS 侧与 Python 侧的关键差异");
console.log("  1) 模型塞 State：Python 抛 KeyError；TS 静默丢弃多余键，不报错");
console.log("  2) 假模型：Python 一次性迭代器会 StopIteration；TS FakeListChatModel 循环复用");
console.log("  3) 假模型类名：GenericFakeChatModel -> FakeListChatModel({ responses: [...] })");
console.log("  4) config 注入路径相同：config.configurable.model（节点第二参数）");
console.log("  5) 断言轨迹一致：streamMode: 'updates' 的 chunk 键就是节点名");
console.log("  6) 中断断言一致：'__interrupt__' in result；resume 用 new Command({ resume })");
console.log("  7) 加节点会补跑、删节点静默、加字段无值：三条与 Python 一致");
console.log("  8) checkpoint_ns 同样不能当版本号");
