// 课 11 · Functional API 与选型（TypeScript 侧）
// 对照：../../playground/11_functional_api.py（Python 侧）
// 运行：npm run l11
import { InMemoryCache } from "@langchain/langgraph-checkpoint";
import {
  Annotation, Command, END, entrypoint, getPreviousState, interrupt, MemorySaver, START, StateGraph, task,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);
const cfg = (tid: string) => ({ configurable: { thread_id: tid } });

// 验证一：最小 entrypoint / task
line("验证一：最小 entrypoint / task");
{
  const addOne = task("addOne", async (x: number) => x + 1);
  const flow = entrypoint({ name: "flow" }, async (x: number) => {
    const a = await addOne(x);
    const b = await addOne(a);
    return b;
  });
  console.log("  ->", await flow.invoke(1));
}

// 验证二：entrypoint 对象类型与能力面
line("验证二：entrypoint 对象类型与能力面");
{
  const flow = entrypoint({ name: "t2", checkpointer: new MemorySaver() }, async (x: number) => x);
  console.log("  构造器:", flow.constructor.name);
  for (const k of ["invoke", "stream", "getState", "updateState", "getStateHistory"]) {
    console.log(`  有 ${k}:`, typeof (flow as any)[k] === "function");
  }
}

// 验证三：并发（先提交后收）
line("验证三：task 并发");
{
  const slowAdd = task("slowAdd", async (x: number) => {
    await new Promise((r) => setTimeout(r, 300));
    return x + 1;
  });
  const par = entrypoint("par", async (x: number) => {
    const f1 = slowAdd(x);
    const f2 = slowAdd(x + 10);
    return (await f1) + (await f2);
  });
  let st = Date.now();
  console.log("  并发 ->", await par.invoke(1), " 耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");

  const par2 = entrypoint("par2", async (x: number) => {
    const a = await slowAdd(x);
    const b = await slowAdd(x + 10);
    return a + b;
  });
  st = Date.now();
  console.log("  串行 ->", await par2.invoke(1), " 耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");
}

// 验证四：动态扇出（列表推导）
line("验证四：动态扇出");
{
  const work = task("work", async (i: number) => i * 10);
  const fan = entrypoint("fan", async (items: number[]) => {
    const futs = items.map((i) => work(i));
    return { results: await Promise.all(futs) };
  });
  console.log("  ->", JSON.stringify(await fan.invoke([1, 2, 3])));
}

// 验证五：同 thread 再 invoke，task 会不会复用
line("验证五：同 thread 再 invoke");
{
  let runs = 0;
  const t = task("t", async (x: number) => { runs += 1; return x * 10; });
  const flow = entrypoint({ name: "f5", checkpointer: new MemorySaver() }, async (x: number) => t(x));
  const c = cfg("t5");
  console.log("  第一次:", await flow.invoke(2, c), " task 执行", runs, "次");
  console.log("  同 thread 再 invoke:", await flow.invoke(2, c), " task 执行", runs, "次  <- 不复用");
}

// 验证六：挂 checkpointer 不传 config
line("验证六：挂 checkpointer 不传 config");
{
  const flow = entrypoint({ name: "f6", checkpointer: new MemorySaver() }, async (x: number) => x + 1);
  try { await flow.invoke(1); } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message.split("\n")[0]);
  }
}

// 验证七：不挂 checkpointer 也能跑
line("验证七：不挂 checkpointer");
{
  const flow = entrypoint("f7", async (x: number) => x + 1);
  console.log("  ->", await flow.invoke(1));
}

// 验证八：task 持久化（interrupt + resume）
line("验证八：task 持久化（interrupt + resume）");
{
  let ta = 0, tb = 0;
  const tA = task("tA", async (x: number) => { ta += 1; console.log("  [副作用] tA 真的跑了，输入", x); return x + 1; });
  const tB = task("tB", async (x: number) => { tb += 1; console.log("  [副作用] tB 真的跑了，输入", x); return x + 1; });
  const flow = entrypoint({ name: "f8t", checkpointer: new MemorySaver() }, async (x: number) => {
    const a = await tA(x);
    const ans = await interrupt({ question: "继续吗" });
    const b = await tB(a);
    return { a, b, ans };
  });
  const c = cfg("t8");
  console.log("  第一次:", JSON.stringify(await flow.invoke(1, c)), " tA 次数=", ta, " tB 次数=", tb);
  const r: any = await flow.invoke(new Command({ resume: "ok" }), c);
  console.log("  resume:", JSON.stringify(r), " tA 次数=", ta, " tB 次数=", tb, " <- tA 没重跑");
}

// 验证九：普通函数对照（必重跑）
line("验证九：普通函数对照");
{
  let plain = 0;
  const flow = entrypoint({ name: "f9", checkpointer: new MemorySaver() }, async (x: number) => {
    plain += 1;
    console.log("  [副作用] plain_a 真的跑了  执行", plain, "次");
    const ans = await interrupt({ question: "继续吗" });
    return { ans };
  });
  const c = cfg("t9");
  await flow.invoke(1, c);
  await flow.invoke(new Command({ resume: "ok" }), c);
}

// 验证十：previous 的 TS 写法（getPreviousState）
line("验证十：previous 的 TS 替代写法");
{
  const f10 = entrypoint({ name: "f10", checkpointer: new MemorySaver() }, async (x: number) => {
    const prev = getPreviousState<number>() ?? 0;
    return prev + x;
  });
  const c = cfg("t10");
  console.log("  第1次 invoke(10):", await f10.invoke(10, c));
  console.log("  第2次 invoke(5) :", await f10.invoke(5, c), "  <- 需要 getPreviousState");
}

// 验证十一：Graph API 同操作对照（不声明 reducer = 覆盖）
line("验证十一：Graph API 累加对照");
{
  const S = Annotation.Root({
    total: Annotation<number>(),                                   // ← 不声明 reducer
    inc: Annotation<number>(),
  });
  const g = new StateGraph(S).addNode("add", (s: any) => ({ total: s.total + s.inc }))
    .addEdge(START, "add").addEdge("add", END).compile({ checkpointer: new MemorySaver() });
  const c = cfg("g11");
  console.log("  第1次 (total=0, inc=10):", JSON.stringify(await g.invoke({ total: 0, inc: 10 }, c)));
  console.log("  第2次 (inc=5):", JSON.stringify(await g.invoke({ inc: 5 }, c)), "  <- 没有 reducer 就是覆盖");
}

// 验证十二：entrypoint.final 分离"返回给调用方"和"存档"
line("验证十二：entrypoint.final");
{
  const f12 = entrypoint({ name: "f12", checkpointer: new MemorySaver() }, async (x: number) => {
    const prev = getPreviousState<number>() ?? 0;
    return entrypoint.final({ value: prev, save: 2 * x + prev });
  });
  const c = cfg("t12");
  console.log("  第1次 invoke(10):", await f12.invoke(10, c));
  console.log("  第2次 invoke(5) :", await f12.invoke(5, c), "  <- TS 独有 API");
}

// 验证十三：task 的 retry（注意 TS 键名是 retry 不是 retryPolicy）
line("验证十三：task 的 retry");
{
  let runs = 0;
  class NetError extends Error { constructor(m: string) { super(m); this.name = "NetError"; } }
  const flaky = task({ name: "flaky", retry: { maxAttempts: 3, initialInterval: 5, jitter: false } },
    async (x: number) => { runs += 1; if (runs < 3) throw new NetError("抖动"); return x * 2; });
  const flow = entrypoint("f13", async (x: number) => flaky(x));
  console.log("  结果:", await flow.invoke(2), " task 执行", runs, "次");

  let runs2 = 0;
  const bad = task({ name: "bad", retry: { maxAttempts: 3, initialInterval: 5, jitter: false } },
    async () => { runs2 += 1; throw new Error("代码bug"); });
  const flow2 = entrypoint("f13b", async (_x: number) => bad());
  try { await flow2.invoke(1); } catch (e: any) { console.log("  抛错:", e.message); }
  console.log("  task 执行", runs2, "次  <- TS 默认重试，与 Python 只跑 1 次不同");
}

// 验证十四：cachePolicy 两头配
line("验证十四：cachePolicy 两头配");
{
  let runsA = 0;
  const t = task({ name: "tc", cachePolicy: { ttl: 60 } }, async (x: number) => { runsA += 1; return x * 2; });
  const noCache = entrypoint({ name: "f14a", checkpointer: new MemorySaver() }, async (x: number) => t(x));
  const c1 = cfg("t14a");
  await noCache.invoke(3, c1);
  await noCache.invoke(3, c1);
  console.log("  A) task 有 cachePolicy / entrypoint 无 cache -> 执行", runsA, "次（没缓存）");

  let runsB = 0;
  const t2 = task({ name: "tc2", cachePolicy: { ttl: 60 } }, async (x: number) => { runsB += 1; return x * 2; });
  const withCache = entrypoint({ name: "f14b", checkpointer: new MemorySaver(), cache: new InMemoryCache() }, async (x: number) => t2(x));
  await withCache.invoke(3, cfg("t14b"));
  await withCache.invoke(3, cfg("t14c"));
  console.log("  B) task 有 + entrypoint 有 cache（不同 thread）-> 执行", runsB, "次  <- 缓存跨 thread");
}

// 验证十五：同步/异步 task 配 timeout
line("验证十五：task 配 timeout");
{
  const syncSlow = task({ name: "syncSlow", timeout: 100 }, async (x: number) => x);
  const flow = entrypoint("f15", async (x: number) => syncSlow(x));
  console.log("  定义阶段 -> ok（TS 不抛）");
  try {
    const slow = task({ name: "slow", timeout: 100 }, async () => {
      await new Promise((r) => setTimeout(r, 400));
      return "跑完";
    });
    const f = entrypoint("f15b", async (x: number) => slow());
    const st = Date.now();
    await f.invoke(1);
    console.log("  超时节点竟然跑完:", ((Date.now() - st) / 1000).toFixed(2) + "s");
  } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message);
  }
}

// 验证十六：状态可见性对照（Graph 2 节点 vs Functional 2 task）
line("验证十六：状态可见性对照");
{
  const S = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const g = new StateGraph(S)
    .addNode("step1", () => ({ log: ["step1"] }))
    .addNode("step2", () => ({ log: ["step2"] }))
    .addEdge(START, "step1").addEdge("step1", "step2").addEdge("step2", END)
    .compile({ checkpointer: new MemorySaver() });
  const gc = cfg("vis-g");
  await g.invoke({ log: [] }, gc);
  const gs: any = await g.getState(gc);
  console.log("  Graph getState values:", JSON.stringify(gs.values), " next:", JSON.stringify(gs.next));

  const t1 = task("t1", async () => 1);
  const t2 = task("t2", async () => 1);
  const f = entrypoint({ name: "vis-f", checkpointer: new MemorySaver() }, async () => {
    const a = await t1();
    const b = await t2();
    return { a: a + b };
  });
  const fc = cfg("vis-f");
  await f.invoke(1, fc);
  const fs: any = await f.getState(fc);
  console.log("  Functional getState values:", JSON.stringify(fs.values), " next:", JSON.stringify(fs.next));
}

// 验证十七：历史条数
line("验证十七：历史条数");
{
  const S = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const g = new StateGraph(S)
    .addNode("step1", () => ({ log: ["step1"] }))
    .addNode("step2", () => ({ log: ["step2"] }))
    .addEdge(START, "step1").addEdge("step1", "step2").addEdge("step2", END)
    .compile({ checkpointer: new MemorySaver() });
  const gc = cfg("h-g");
  await g.invoke({ log: [] }, gc);
  const gnext: string[] = [];
  for await (const s of await g.getStateHistory(gc)) gnext.push(JSON.stringify(s.next));
  console.log("  Graph（2 节点） 历史", gnext.length, "条:", JSON.stringify(gnext));

  const t1 = task("t1", async () => 1);
  const t2 = task("t2", async () => 1);
  const f = entrypoint({ name: "h-f", checkpointer: new MemorySaver() }, async () => {
    const a = await t1(); const b = await t2(); return { a: a + b };
  });
  const fc = cfg("h-f");
  await f.invoke(1, fc);
  const fnext: string[] = [];
  for await (const s of await f.getStateHistory(fc)) fnext.push(JSON.stringify(s.next));
  console.log("  Functional（2 task） 历史", fnext.length, "条:", JSON.stringify(fnext));
}

// 验证十八：混用（图当函数调）
line("验证十八：混用（图当函数调）");
{
  const S = Annotation.Root({ v: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }) });
  const g = new StateGraph(S).addNode("inc", (s) => ({ v: s.v + 10 }))
    .addEdge(START, "inc").addEdge("inc", END).compile();

  const callGraph = task("callGraph", async (x: number) =>
    (await g.invoke({ v: x }, { configurable: { thread_id: `gg${x}` } }) as any).v);
  const outer = entrypoint({ name: "outer", checkpointer: new MemorySaver() },
    async (x: number) => (await callGraph(x)) + 1);
  console.log("  图当函数调 ->", await outer.invoke(1, cfg("mix")));
}

// 验证十九：entrypoint 嵌套 entrypoint
line("验证十九：entrypoint 嵌套");
{
  const inner = entrypoint("inner", async (x: number) => x * 2);
  const outer = entrypoint("outerN", async (x: number) => (await inner.invoke(x)) + 1);
  console.log("  ->", await outer.invoke(5));
}

// 验证二十：stream 的粒度
line("验证二十：stream 的粒度");
{
  const t9 = task("t9", async (x: number) => x * 3);
  const f9 = entrypoint("f9s", async (x: number) => ({ r: await t9(x) }));
  console.log("  streamMode=updates:");
  for await (const c of await f9.stream(6, { streamMode: "updates" })) console.log("   ", JSON.stringify(c));
  console.log("  streamMode=values:");
  for await (const c of await f9.stream(6, { streamMode: "values" })) console.log("   ", JSON.stringify(c));
}

// 验证二十一：逐字段改 vs 整体替换
line("验证二十一：updateState 语义");
{
  const S = Annotation.Root({ v: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }) });
  const g = new StateGraph(S).addNode("a", () => ({ v: 1 })).addEdge(START, "a").addEdge("a", END)
    .compile({ checkpointer: new MemorySaver() });
  const gc = cfg("u-g");
  await g.invoke({ v: 0 }, gc);
  await g.updateState(gc, { v: 100 });
  console.log("  Graph updateState 后:", JSON.stringify((await g.getState(gc)).values));

  const f = entrypoint({ name: "u-f", checkpointer: new MemorySaver() }, async (x: number) => ({ v: x }));
  const fc = cfg("u-f");
  await f.invoke(1, fc);
  await (f as any).updateState(fc, { v: 100 });
  console.log("  Functional updateState 后:", JSON.stringify((await f.getState(fc)).values), " <- 整体替换返回值");
}

// 验证二十二：不调 await 丢弃结果
line("验证二十二：不取结果");
{
  const t = task("t22", async (x: number) => x * 2);
  const f = entrypoint("f22", async () => { t(5); return { done: true }; });
  console.log("  ->", JSON.stringify(await f.invoke(1)));
}

// 验证二十三：task 返回 Promise 而非 Future
line("验证二十三：task 返回类型");
{
  const t = task("t23", async (x: number) => x + 1);
  const f = entrypoint("f23", async () => {
    const p = t(1);
    console.log("  调用后未 await 时: type =", p.constructor.name, " instanceof Promise =", p instanceof Promise);
    return { v: await p };
  });
  console.log("  ->", JSON.stringify(await f.invoke(1)));
}
