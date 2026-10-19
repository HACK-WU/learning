/**
 * 应用实战 11：已有脚本想加暂停和断点续跑，要不要重写成图
 *
 * 对应课文：应用实战/11-Functional API 与选型.md
 * 逐段对齐课文的 7 个 Python 块：
 *   1. 第 1 跳：entrypoint + task
 *   2. 坑一：普通函数 resume 时重跑
 *   3. 坑二：getState / getStateHistory
 *   4. 第一步：全部标 task
 *   5. 第二步：previous（TS 用 getPreviousState）
 *   6. 对照 Graph API 的累加
 *   7. 第三步：混用（旧图当函数调）
 *
 * 运行：npm run a11
 */
import {
  entrypoint,
  task,
  interrupt,
  MemorySaver,
  getPreviousState,
  StateGraph,
  Annotation,
  START,
  END,
  Command,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n--- ${t} ---`);

// ============================================================
// 第 1 跳：给已有脚本加两个装饰器
// ============================================================
line("第 1 跳：entrypoint + task");

const SIDE = { load: 0, clean: 0 };

// ⚠️ TS 的 task 是 task(name, fn)，没有装饰器
const load = task("load", async (src: string) => {
  SIDE.load += 1;
  return [3, 1, 2];
});

// ← 这个故意不标 task（就是普通函数）
const clean = (data: number[]) => {
  SIDE.clean += 1;
  return [...data].sort((a, b) => a - b);
};

// ⚠️ entrypoint 是 entrypoint({ name, checkpointer }, fn)：选项对象在前，且 name 必填
const process = entrypoint(
  { name: "process", checkpointer: new MemorySaver() },
  async (src: string) => {
    const data = await load(src); // ⚠️ TS 返回 Promise，不是 .result()
    const cleaned = clean(data);
    const ok = interrupt({ question: "清洗结果对吗", data: cleaned });
    return { data: cleaned, approved: ok };
  }
);

const cfg = { configurable: { thread_id: "job-1" } };

{
  // config 必填验证放前面、并用独立 entrypoint，避免污染主流程的副作用计数
  const probeCfg = entrypoint(
    { name: "probeCfg", checkpointer: new MemorySaver() },
    async (x: string) => ({ ok: x })
  );
  try {
    await probeCfg.invoke("orders.csv");
  } catch (e: any) {
    console.log(`不传 config -> ${e.name}: ${String(e.message).split("\n")[0].slice(0, 140)}`);
  }

  const r = await process.invoke("orders.csv", cfg);
  console.log("invoke ->", JSON.stringify(r));
  console.log(`副作用计数: ${JSON.stringify(SIDE)}`);
}

// ============================================================
// 坑一：没标 task 的函数，resume 时必然重跑
// ============================================================
line("坑一：resume 时普通函数重跑");

{
  console.log("resume 前:", JSON.stringify(SIDE));
  const r2 = await process.invoke(new Command({ resume: "通过" }), cfg);
  console.log("resume ->", JSON.stringify(r2));
  console.log(`resume 后: ${JSON.stringify(SIDE)}`);
}

// ============================================================
// 坑二：getState / getStateHistory
// ============================================================
line("坑二：想改中间某一步的结果");

{
  const st = await process.getState(cfg);
  console.log("getState ->", JSON.stringify(st.values));
  const hist: any[] = [];
  for await (const s of await process.getStateHistory(cfg)) hist.push(s);
  console.log("历史条数:", hist.length);
  console.log("next 形态:", JSON.stringify(hist.map((h) => h.next)));
}

// ============================================================
// 第一步：给所有有副作用的步骤标 task
// ============================================================
line("第一步：全部标 task");

const SIDE2 = { load: 0, clean: 0, write: 0 };

const load2 = task("load2", async (src: string) => {
  SIDE2.load += 1;
  return [3, 1, 2];
});

const clean2 = task("clean2", async (data: number[]) => {
  SIDE2.clean += 1;
  return [...data].sort((a, b) => a - b);
});

const write2 = task("write2", async (data: number[], ok: unknown) => {
  SIDE2.write += 1;
  return `写回 ${data.length} 条（审批=${String(ok)}）`;
});

const process2 = entrypoint(
  { name: "process2", checkpointer: new MemorySaver() },
  async (src: string) => {
    const data = await load2(src);
    const cleaned = await clean2(data);
    const ok = interrupt({ question: "确认", data: cleaned });
    return { result: await write2(cleaned, ok) };
  }
);

const cfg2 = { configurable: { thread_id: "job-2" } };

{
  const r3 = await process2.invoke("orders.csv", cfg2);
  console.log("invoke ->", JSON.stringify(r3));
  console.log(`  计数: ${JSON.stringify(SIDE2)}`);
  const r4 = await process2.invoke(new Command({ resume: "通过" }), cfg2);
  console.log("resume ->", JSON.stringify(r4));
  console.log(`  计数: ${JSON.stringify(SIDE2)}`);

  // task 不是缓存：同 thread 再跑一遍（不中断）
  const SIDE2B = { ...SIDE2 };
  const plain = entrypoint(
    { name: "plain", checkpointer: new MemorySaver() },
    async (x: number) => ({ out: await load2("x") })
  );
  const c = { configurable: { thread_id: "nocache" } };
  await plain.invoke(1, c);
  const after1 = SIDE2.load;
  await plain.invoke(1, c);
  console.log(`task 不是缓存：同 thread 再 invoke，load 计数 ${after1} -> ${SIDE2.load}`);
  void SIDE2B;
}

// ============================================================
// 第二步：previous 承载跨轮状态
// ============================================================
line("第二步：previous（TS 用 getPreviousState）");

{
  const pipeline = entrypoint(
    { name: "pipeline", checkpointer: new MemorySaver() },
    async (batch: number[]) => {
      // ⚠️ TS 回调只有 (input, config)，没有 previous 形参
      const prev = getPreviousState<{ done: number[] } | undefined>();
      const done = [...((prev as any)?.done ?? []), batch.length];
      return { done, total: done.reduce((a, b) => a + b, 0) };
    }
  );
  const cfg3 = { configurable: { thread_id: "pipe" } };
  console.log("第1批:", JSON.stringify(await pipeline.invoke([1, 2], cfg3)));
  console.log("第2批:", JSON.stringify(await pipeline.invoke([3, 4, 5], cfg3)));
  console.log("第3批:", JSON.stringify(await pipeline.invoke([6], cfg3)));
}

// ============================================================
// 对照 Graph API 的累加
// ============================================================
line("对照 Graph API：同样的操作");

const GState = Annotation.Root({
  v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  inc: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});

const g = new StateGraph(GState)
  .addNode("add", (s: typeof GState.State) => ({ v: s.v + s.inc }))
  .addEdge(START, "add")
  .addEdge("add", END)
  .compile({ checkpointer: new MemorySaver() });

{
  const cfgg = { configurable: { thread_id: "g" } };
  const r1 = await g.invoke({ v: 0, inc: 10 }, cfgg);
  console.log("Graph 第1次:", r1.v);
  // 只传增量（Python 课文的写法）：TS 会把存档点里的 v=10 带进来，得到 15
  const r2 = await g.invoke({ inc: 5 }, cfgg);
  console.log("Graph 第2次（只传 inc）:", r2.v, "  <- Python 是 5，TS 是 15");
  // 显式把 v 归零，才是与 Python 对齐的「覆盖」语义
  const r3 = await g.invoke({ v: 0, inc: 5 }, cfgg);
  console.log("Graph 第2次（显式传 v:0）:", r3.v);
}

// ============================================================
// 第三步：混用——把旧图当函数调
// ============================================================
line("第三步：混用（旧图当函数调）");

const callLegacyGraph = task("callLegacy", async (x: number) => {
  // ⚠️ 内层图的入参契约是它自己的 State schema，跟外层无关
  const r = await g.invoke({ v: x }, { configurable: { thread_id: `legacy-${x}` } });
  return r.v;
});

const mixed = entrypoint(
  { name: "mixed", checkpointer: new MemorySaver() },
  async (x: number) => ({ out: await callLegacyGraph(x) })
);

{
  const cfg4 = { configurable: { thread_id: "mix" } };
  console.log("混用 ->", JSON.stringify(await mixed.invoke(1, cfg4)));
  console.log("再来 ->", JSON.stringify(await mixed.invoke(1, cfg4)));

  // 改法：显式传全内层图需要的字段
  const callLegacyFull = task("callLegacyFull", async (x: number) => {
    const r = await g.invoke(
      { v: x, inc: 10 },
      { configurable: { thread_id: `legacy-full-${x}` } }
    );
    return r.v;
  });
  const mixedFull = entrypoint(
    { name: "mixedFull", checkpointer: new MemorySaver() },
    async (x: number) => ({ out: await callLegacyFull(x) })
  );
  const c5 = { configurable: { thread_id: "mix2" } };
  console.log("传全字段 ->", JSON.stringify(await mixedFull.invoke(1, c5)));
}

// ============================================================
// 补充：底层同一个 Pregel
// ============================================================
line("补充：两套 API 底层是同一个 Pregel");
{
  const probe = entrypoint({ name: "probe", checkpointer: new MemorySaver() }, async () => 1);
  console.log("entrypoint 对象类型:", probe.constructor.name);
}

console.log("\n=== app-11 全部完成 ===");
