// 课 10 · Fault-tolerance 与 Subgraphs（TypeScript 侧）
// 对照：../../playground/10_fault_tolerance.py（Python 侧）
// 运行：npm run l10
import {
  Annotation, Command, END, MemorySaver, START, StateGraph,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

const S = Annotation.Root({
  log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  n: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }),
});

// 验证零：不配 retryPolicy 到底会不会重试
line("验证零：不配 retryPolicy 的重试次数");
{
  const cases: [string, () => Error][] = [
    ["普通 Error", () => new Error("boom")],
    ["HTTP 404", () => Object.assign(new Error("not-found"), { status: 404 })],
    ["HTTP 500", () => Object.assign(new Error("server-err"), { status: 500 })],
  ];
  for (const [name, mk] of cases) {
    let runs = 0;
    const g = new StateGraph(S)
      .addNode("work", () => {
        runs += 1;
        throw mk();
      })
      .addEdge(START, "work").addEdge("work", END)
      .compile();
    try { await g.invoke({ log: [], n: 0 }); } catch { /* 预期抛错 */ }
    console.log(`  ${name.padEnd(12)} -> 调用 ${runs} 次  <- 无 policy = 不重试`);
  }

  // 同一份 policy 只有挂到 addNode / setNodeDefaults 上才生效
  let runs404 = 0;
  const withPolicy = new StateGraph(S)
    .addNode("work", () => {
      runs404 += 1;
      throw Object.assign(new Error("not-found"), { status: 404 });
    }, { retryPolicy: { maxAttempts: 4, initialInterval: 5, jitter: false, logWarning: false } })
    .addEdge(START, "work").addEdge("work", END)
    .compile();
  try { await withPolicy.invoke({ log: [], n: 0 }); } catch { /* 预期抛错 */ }
  console.log(`  HTTP 404 + policy(maxAttempts=4) -> 调用 ${runs404} 次  <- 404 在默认黑名单`);
}

// 验证一：默认 retryOn 对各类异常的判断
line("验证一：默认 retryOn 的异常对照表（前提：已配 retryPolicy）");
{
  const cases: [string, () => Error][] = [
    ["ValueError", () => new Error("x")],
    ["TypeError", () => new TypeError("x")],
    ["RangeError", () => new RangeError("x")],
    ["连接错误(ECONNREFUSED)", () => Object.assign(new Error("x"), { code: "ECONNREFUSED" })],
    ["HTTP 500", () => Object.assign(new Error("x"), { status: 500 })],
    ["HTTP 404", () => Object.assign(new Error("x"), { status: 404 })],
    ["普通自定义异常", () => new Error("x")],
  ];
  for (const [name, mk] of cases) {
    const e: any = mk();
    // 复刻 dist/pregel/retry.js 的 DEFAULT_RETRY_ON_HANDLER 判定
    const status = e?.response?.status ?? e?.status;
    const noRetry = [400,401,402,403,404,405,406,407,409].includes(+status);
    const retry = e.name === "AbortError" ? false
      : e.name === "GraphValueError" ? false
      : e?.code === "ECONNABORTED" ? false
      : noRetry ? false
      : e?.error?.code === "insufficient_quota" ? false
      : true;
    console.log(`  ${name.padEnd(24)} -> ${retry ? "✅重试" : "❌不重试"}`);
  }
}

// 验证二：抛普通 Error，配 retryPolicy 会不会重试
line("验证二：普通 Error + retryPolicy(maxAttempts=3)");
{
  let runs = 0;
  const g = new StateGraph(S)
    .addNode("b", () => { runs += 1; throw new Error("临时故障"); },
      { retryPolicy: { maxAttempts: 3, initialInterval: 10, jitter: false } })
    .addEdge(START, "b").addEdge("b", END)
    .compile();
  try {
    await g.invoke({ log: [], n: 0 });
  } catch (e: any) {
    console.log("  invoke ->", e.constructor.name + ":", e.message);
  }
  console.log("  实际执行", runs, "次  <- maxAttempts=3");
}

// 验证三：maxAttempts 含第一次
line("验证三：maxAttempts 含第一次");
{
  for (const m of [1, 2, 3]) {
    let runs = 0;
    const g = new StateGraph(S)
      .addNode("b", () => { runs += 1; throw new Error("x"); },
        { retryPolicy: { maxAttempts: m, initialInterval: 5, jitter: false } })
      .addEdge(START, "b").addEdge("b", END).compile();
    try { await g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
    console.log(`  maxAttempts=${m} -> ${runs} 次`);
  }
}

// 验证四：退避间隔
line("验证四：退避间隔（jitter=false）");
{
  const t: number[] = [];
  const g = new StateGraph(S)
    .addNode("b", () => { t.push(Date.now()); throw new Error("x"); },
      { retryPolicy: { maxAttempts: 4, initialInterval: 300, backoffFactor: 2, jitter: false } })
    .addEdge(START, "b").addEdge("b", END).compile();
  const st = Date.now();
  try { await g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  总耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");
  console.log("  实测间隔:", t.slice(1).map((x, i) => ((x - t[i]) / 1000).toFixed(2) + "s"));
}

// 验证五：jitter 默认值
line("验证五：jitter 默认（不传）");
{
  const t: number[] = [];
  const g = new StateGraph(S)
    .addNode("b", () => { t.push(Date.now()); throw new Error("x"); },
      { retryPolicy: { maxAttempts: 4, initialInterval: 500 } })
    .addEdge(START, "b").addEdge("b", END).compile();
  try { await g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  jitter 默认实测间隔:", t.slice(1).map((x, i) => ((x - t[i]) / 1000).toFixed(2) + "s"));
}

// 验证六：errorHandler 的签名与拿 error 的方式
line("验证六：errorHandler 签名 (state, error, config)");
{
  let seen: any = null;
  const g = new StateGraph(S)
    .addNode("b", () => { throw new Error("崩了"); },
      {
        retryPolicy: { maxAttempts: 2, initialInterval: 5, jitter: false },
        errorHandler: (state: any, error: any, config: any) => {
          seen = { state, errorName: error?.constructor?.name, errorMsg: error?.message, hasConfig: !!config };
          return { log: ["兜底"], n: -1 };
        },
      })
    .addEdge(START, "b").addEdge("b", END).compile();
  const r: any = await g.invoke({ log: ["ok"], n: 1 });
  console.log("  handler 收到:", JSON.stringify(seen));
  console.log("  结果:", JSON.stringify(r));
}

// 验证七：NodeError 的结构
line("验证七：NodeError 的结构");
{
  let seen: any = null;
  const g = new StateGraph(S)
    .addNode("b", () => { throw new Error("崩了"); },
      { errorHandler: (state: any, error: any) => { seen = error; return { log: ["兜底"] }; } })
    .addEdge(START, "b").addEdge("b", END).compile();
  await g.invoke({ log: [], n: 0 });
  console.log("  构造器:", seen?.constructor?.name);
  console.log("  自己的键:", Object.keys(seen));
  console.log("  node =", seen?.node, " error =", seen?.error?.constructor?.name + ":" + seen?.error?.message);
  console.log("  message =", JSON.stringify(seen?.message));
}

// 验证八：handler 返回普通 dict 会截断流程
line("验证八：handler 返回普通对象是否截断流程");
{
  const b = new StateGraph(S)
    .addNode("查库存", () => ({ log: ["查库存:有货"] }))
    .addNode("调风控", () => { throw new Error("风控挂了"); },
      { errorHandler: () => ({ log: ["调风控:兜底放行"] }) })
    .addNode("出结论", () => ({ log: ["出结论:通过"] }))
    .addNode("通知", () => ({ log: ["通知:通过"] }))
    .addEdge(START, "查库存").addEdge("查库存", "调风控")
    .addEdge("调风控", "出结论").addEdge("出结论", "通知").addEdge("通知", END);
  const r: any = await b.compile().invoke({ log: [], n: 0 });
  console.log("  结果:", JSON.stringify(r.log));
}

// 验证九：handler 返回 Command(goto) 能续流程
line("验证九：handler 返回 Command(goto) 续流程");
{
  const b = new StateGraph(S)
    .addNode("查库存", () => ({ log: ["查库存:有货"] }))
    .addNode("调风控", () => { throw new Error("风控挂了"); },
      { errorHandler: () => new Command({ goto: "出结论", update: { log: ["调风控:兜底放行"] } }) })
    .addNode("出结论", () => ({ log: ["出结论:通过"] }))
    .addNode("通知", () => ({ log: ["通知:通过"] }))
    .addEdge(START, "查库存").addEdge("查库存", "调风控")
    .addEdge("调风控", "出结论").addEdge("出结论", "通知").addEdge("通知", END);
  const r: any = await b.compile().invoke({ log: [], n: 0 });
  console.log("  结果:", JSON.stringify(r.log));
}

// 验证十：handler 自己抛错
line("验证十：handler 自己抛错");
{
  const g = new StateGraph(S)
    .addNode("b", () => { throw new Error("原始错"); },
      { errorHandler: () => { throw new Error("handler 自己也崩了"); } })
    .addEdge(START, "b").addEdge("b", END).compile();
  try { await g.invoke({ log: [], n: 0 }); } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message);
  }
}

// 验证十一：同步节点配 timeout 会不会 compile 报错
line("验证十一：同步节点配 timeout（毫秒）");
{
  const g = new StateGraph(S)
    .addNode("b", () => { const t = Date.now(); while (Date.now() - t < 300) {} return { log: ["同步跑完"] }; },
      { timeout: 100 })
    .addEdge(START, "b").addEdge("b", END);
  let built = "ok";
  try { g.compile(); } catch (e: any) { built = e.constructor.name + ": " + e.message; }
  console.log("  compile() ->", built);
  try {
    const r: any = await g.compile().invoke({ log: [], n: 0 });
    console.log("  invoke ->", JSON.stringify(r.log), " ← 同步死循环也能跑完，只是结果被丢弃");
  } catch (e: any) {
    console.log("  invoke ->", e.constructor.name + ":", e.message);
  }
}

// 验证十二：async 节点 timeout 生效
line("验证十二：async 节点 timeout 生效");
{
  const g = new StateGraph(S)
    .addNode("b", async () => { await new Promise((r) => setTimeout(r, 300)); return { log: ["跑完"] }; },
      { timeout: 100 })
    .addEdge(START, "b").addEdge("b", END).compile();
  const st = Date.now();
  try { await g.invoke({ log: [], n: 0 }); } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message);
  }
  console.log("  耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");
}

// 验证十三：超时触发 errorHandler
line("验证十三：超时触发 errorHandler");
{
  const g = new StateGraph(S)
    .addNode("b", async () => { await new Promise((r) => setTimeout(r, 300)); return { log: ["跑完"] }; },
      { timeout: 100, errorHandler: () => ({ log: ["超时兜底"] }) })
    .addEdge(START, "b").addEdge("b", END).compile();
  const st = Date.now();
  const r: any = await g.invoke({ log: [], n: 0 });
  console.log("  结果:", JSON.stringify(r.log), " 耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");
}

// 验证十四：TimeoutPolicy 的字段
line("验证十四：TimeoutPolicy 字段与 idleTimeout");
{
  const g = new StateGraph(S)
    .addNode("b", async () => { await new Promise((r) => setTimeout(r, 400)); return { log: ["跑完"] }; },
      { timeout: { runTimeout: 300, idleTimeout: 150 } })
    .addEdge(START, "b").addEdge("b", END).compile();
  const st = Date.now();
  try { await g.invoke({ log: [], n: 0 }); } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message);
  }
  console.log("  耗时", ((Date.now() - st) / 1000).toFixed(2) + "s  <- 150ms 触发，不是 300ms");
}

// 验证十五：超时 + retry 叠乘
line("验证十五：超时 + retry 叠乘");
{
  let runs = 0;
  const g = new StateGraph(S)
    .addNode("b", async () => { runs += 1; await new Promise((r) => setTimeout(r, 300)); return { log: ["跑完"] }; },
      { timeout: 100, retryPolicy: { maxAttempts: 3, initialInterval: 5, jitter: false } })
    .addEdge(START, "b").addEdge("b", END).compile();
  const st = Date.now();
  try { await g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  节点执行", runs, "次  耗时", ((Date.now() - st) / 1000).toFixed(2) + "s");
}

// 验证十六：父图私有字段，子图收不到
line("验证十六：父图私有字段子图收不到");
{
  const Inner = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const Outer = Annotation.Root({
    secret: Annotation<string>({ reducer: (_p, x) => x, default: () => "" }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  let seenKeys: string[] = [];
  const sub = new StateGraph(Inner)
    .addNode("i", (s: any) => {
      seenKeys = Object.keys(s);
      return { log: [`子图看到的 keys=${JSON.stringify(Object.keys(s))}`] };
    })
    .addEdge(START, "i").addEdge("i", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub)
    .addEdge(START, "sub").addEdge("sub", END).compile();
  const r: any = await parent.invoke({ secret: "S", log: [] });
  console.log("  父图传了 secret=S ->", JSON.stringify(r.log), " 子图实收 keys:", JSON.stringify(seenKeys));
}

// 验证十七：子图私有字段，父图静默吞掉
line("验证十七：子图私有字段父图静默吞掉");
{
  const Inner = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
    onlySub: Annotation<string>({ reducer: (_p, x) => x, default: () => "" }),
  });
  const Outer = Annotation.Root({
    secret: Annotation<string>({ reducer: (_p, x) => x, default: () => "" }),
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const sub = new StateGraph(Inner)
    .addNode("i", () => ({ log: ["子图写了"], onlySub: "子图私有" }))
    .addEdge(START, "i").addEdge("i", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub)
    .addEdge(START, "sub").addEdge("sub", END).compile();
  const r: any = await parent.invoke({ secret: "S", log: [] });
  console.log("  父图结果 keys:", JSON.stringify(Object.keys(r)));
  console.log("  log:", JSON.stringify(r.log), "  onlySub 在?", "onlySub" in r);
}

// 验证十八：子图不挂 checkpointer，父图历史
line("验证十八：子图不挂 checkpointer 时父图历史");
{
  const Inner = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const Outer = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const sub = new StateGraph(Inner)
    .addNode("i1", () => ({ log: ["子图内 foo=A"] }))
    .addNode("i2", () => ({ log: ["子图内第二步"] }))
    .addEdge(START, "i1").addEdge("i1", "i2").addEdge("i2", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub)
    .addNode("o", () => ({ log: ["父收尾"] }))
    .addEdge(START, "sub").addEdge("sub", "o").addEdge("o", END)
    .compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "sg1" } };
  await parent.invoke({ log: [] }, cfg);
  for await (const s of await parent.getStateHistory(cfg)) {
    console.log(`  ns="${(s.metadata as any)?.checkpoint_ns ?? s.config.configurable?.checkpoint_ns}" next=${JSON.stringify(s.next)} log=${JSON.stringify(s.values?.log)}`);
  }
}

// 验证十九：subgraphs=true 下的 ns
line("验证十九：stream(subgraphs: true) 的 ns");
{
  const Inner = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const Outer = Annotation.Root({
    log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  });
  const sub = new StateGraph(Inner)
    .addNode("i1", () => ({ log: ["i1"] }))
    .addNode("i2", () => ({ log: ["i2"] }))
    .addEdge(START, "i1").addEdge("i1", "i2").addEdge("i2", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub)
    .addNode("o", () => ({ log: ["o"] }))
    .addEdge(START, "sub").addEdge("sub", "o").addEdge("o", END).compile();
  for await (const [ns, chunk] of await parent.stream({ log: [] }, { subgraphs: true })) {
    console.log(`  ns=${JSON.stringify(ns)}  chunk=${JSON.stringify(chunk)}`);
  }
}

// 验证二十：子图抛错，父图 errorHandler 兜住
line("验证二十：子图抛错父图兜住");
{
  const Inner = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const Outer = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const sub = new StateGraph(Inner)
    .addNode("i", () => { throw new Error("子图炸了"); })
    .addEdge(START, "i").addEdge("i", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub, { errorHandler: () => ({ log: ["父图兜住了"] }) })
    .addEdge(START, "sub").addEdge("sub", END).compile();
  const r: any = await parent.invoke({ log: [] });
  console.log("  ->", JSON.stringify(r.log));
}

// 验证二十一：retryPolicy 配在子图内部节点
line("验证二十一：retryPolicy 配在子图内部节点");
{
  let runs = 0;
  const Inner = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const Outer = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const sub = new StateGraph(Inner)
    .addNode("i", () => {
      runs += 1;
      if (runs < 3) throw new Error("抖动");
      return { log: ["子图成功"] };
    }, { retryPolicy: { maxAttempts: 3, initialInterval: 5, jitter: false } })
    .addEdge(START, "i").addEdge("i", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub)
    .addEdge(START, "sub").addEdge("sub", END).compile();
  await parent.invoke({ log: [] });
  console.log("  子图内部节点执行", runs, "次");
}

// 验证二十二：setNodeDefaults 全图默认 + 节点级覆盖
line("验证二十二：setNodeDefaults 与节点级覆盖");
{
  const mk = (nodeMax?: number) => {
    let runs = 0;
    const fn = () => { runs += 1; throw new Error("x"); };
    const b = nodeMax === undefined
      ? new StateGraph(S).addNode("b", fn)
      : new StateGraph(S).addNode("b", fn, { retryPolicy: { maxAttempts: nodeMax, initialInterval: 5, jitter: false } });
    const g = b.setNodeDefaults({ retryPolicy: { maxAttempts: 5, initialInterval: 5, jitter: false } })
      .addEdge(START, "b").addEdge("b", END).compile();
    return { g, get: () => runs };
  };
  const a = mk();
  try { await a.g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  只配全局 maxAttempts=5 -> 执行", a.get(), "次");
  const c = mk(2);
  try { await c.g.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  全局 5 + 节点级 2 -> 执行", c.get(), "次  <- 节点级覆盖全局");
}

// 验证二十三：retryOn 自定义
line("验证二十三：retryOn 自定义");
{
  let byType = 0;
  const g1 = new StateGraph(S)
    .addNode("b", () => { byType += 1; if (byType < 3) throw new TypeError("x"); return { log: ["成功"] }; },
      { retryPolicy: { maxAttempts: 4, initialInterval: 5, jitter: false, retryOn: (e: any) => e instanceof TypeError } })
    .addEdge(START, "b").addEdge("b", END).compile();
  await g1.invoke({ log: [], n: 0 });
  console.log("  retryOn=TypeError 判断 -> 执行", byType, "次");

  let byFn = 0;
  const g2 = new StateGraph(S)
    .addNode("b", () => { byFn += 1; if (byFn < 3) throw new Error("可重试-抖动"); return { log: ["成功"] }; },
      { retryPolicy: { maxAttempts: 4, initialInterval: 5, jitter: false, retryOn: (e: any) => String(e.message).includes("可重试") } })
    .addEdge(START, "b").addEdge("b", END).compile();
  await g2.invoke({ log: [], n: 0 });
  console.log("  retryOn=函数判断 -> 执行", byFn, "次");

  let refuse = 0;
  const g3 = new StateGraph(S)
    .addNode("b", () => { refuse += 1; throw new Error("x"); },
      { retryPolicy: { maxAttempts: 5, initialInterval: 5, jitter: false, retryOn: () => false } })
    .addEdge(START, "b").addEdge("b", END).compile();
  try { await g3.invoke({ log: [], n: 0 }); } catch { /* ignore */ }
  console.log("  retryOn 恒 false -> 执行", refuse, "次  <- 默认会重试的异常被关掉");
}

// 验证二十四：retry 用尽后抛原始异常
line("验证二十四：retry 用尽后抛的异常类型");
{
  class NetError extends Error { constructor(m: string) { super(m); this.name = "NetError"; } }
  const g = new StateGraph(S)
    .addNode("b", () => { throw new NetError("永远失败"); },
      { retryPolicy: { maxAttempts: 3, initialInterval: 5, jitter: false } })
    .addEdge(START, "b").addEdge("b", END).compile();
  try { await g.invoke({ log: [], n: 0 }); } catch (e: any) {
    console.log("  ->", e.constructor.name + ":", e.message, " <- 原始异常，不是包装异常");
  }
}

// 验证二十五：errorHandler 放在子图内部
line("验证二十五：errorHandler 放在子图内部");
{
  const Inner = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const Outer = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const sub = new StateGraph(Inner)
    .addNode("i", () => { throw new Error("子图内部炸"); }, { errorHandler: () => ({ log: ["子图内兜底"] }) })
    .addEdge(START, "i").addEdge("i", END).compile();
  const parent = new StateGraph(Outer)
    .addNode("sub", sub).addEdge(START, "sub").addEdge("sub", END).compile();
  const r: any = await parent.invoke({ log: [] });
  console.log("  ->", JSON.stringify(r.log));
}

// 验证二十六：子图单独挂 checkpointer
line("验证二十六：子图 compile({checkpointer:true})");
{
  const Inner = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const Outer = Annotation.Root({ log: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }) });
  const sub = new StateGraph(Inner)
    .addNode("i1", () => ({ log: ["i1"] }))
    .addNode("i2", () => ({ log: ["i2"] }))
    .addEdge(START, "i1").addEdge("i1", "i2").addEdge("i2", END)
    .compile({ checkpointer: true });
  const parent = new StateGraph(Outer)
    .addNode("sub", sub).addEdge(START, "sub").addEdge("sub", END)
    .compile({ checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "sg2" } };
  await parent.invoke({ log: [] }, cfg);
  let cnt = 0;
  for await (const _ of await parent.getStateHistory(cfg)) cnt += 1;
  console.log("  父图历史条数:", cnt, "（ns 仍为 \"\"）");
  let subCnt = 0;
  try {
    for await (const _ of await (sub as any).getStateHistory({ configurable: { thread_id: "sub-alone" } })) subCnt += 1;
  } catch (e: any) { console.log("  子图独立查历史 ->", e.constructor.name + ":", e.message); }
  console.log("  子图脱离父图查历史:", subCnt, "条");
}
