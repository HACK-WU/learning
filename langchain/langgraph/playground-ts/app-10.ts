/**
 * 应用实战 10：外部接口抖了就整单失败，还不能拖垮别的环节
 *
 * 对应课文：应用实战/10-Fault-tolerance 与 Subgraphs.md
 * 逐段对齐课文的 12 个 Python 块：
 *   1. 第 1 跳：retryPolicy 挂节点
 *   2. 坑一：ValueError 不重试（TS 侧结论相反）
 *   3. 坑二：同步节点配 timeout
 *   4. 第一步：领域异常
 *   5. 第二步：errorHandler 兜底
 *   6. 第二步改法：Command 续上
 *   7. 第二步补充：从哪读异常
 *   8. 第三步：async + timeout
 *   9. 第四步：拆子图
 *  10. 第五步：状态隔离
 *  11. 第六步：subgraphs = true
 *
 * 运行：npm run a10
 */
import { StateGraph, START, END, Annotation, Command, MemorySaver } from "@langchain/langgraph";

const line = (t: string) => console.log(`\n--- ${t} ---`);

// ============================================================
// 共享状态：Order
//
// ⚠️ 与 Python 课文的关键建模差异：Python 的 `log: list` 没有 reducer，是
// LastValue 通道，节点里靠 `state.get("log", []) + [...]` 手工累加。
// TS 侧若给 log 配 concat reducer，子图回写父图时会**累加两次**（父图原有 + 子图返回），
// 所以这里同样用 LastValue + 手工拼接，语义与 Python 逐字对齐。
// ============================================================
const Order = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  decision: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const checkStock = (s: typeof Order.State) => ({
  log: [...s.log, "查库存:有货"],
});

const decide = (s: typeof Order.State) => {
  const d = s.risk < 0.7 ? "通过" : "拒绝";
  return { log: [...s.log, `出结论:${d}`], decision: d };
};

const notify = (s: typeof Order.State) => ({ log: [...s.log, `通知:${s.decision}`] });

// TS 没有内置 ConnectionError，自定义一个等价物
// （Node 侧真实场景通常来自 fetch 的 TypeError / errno=ECONNREFUSED）
class ConnectionError extends Error {
  constructor(m: string) {
    super(m);
    this.name = "ConnectionError";
  }
}

class RiskAPIError extends Error {
  constructor(m: string) {
    super(m);
    this.name = "RiskAPIError";
  }
}

// ============================================================
// 第 1 跳：给调用节点挂上重试
// ============================================================
line("第 1 跳：retryPolicy 挂节点");

const ATTEMPTS = { risk: 0 };

const callRisk = (s: typeof Order.State) => {
  ATTEMPTS.risk += 1;
  if (ATTEMPTS.risk < 3) {
    throw new ConnectionError(`风控接口抖动 ${ATTEMPTS.risk}`);
  }
  return { log: [...s.log, "调风控:成功"], risk: 0.3 };
};

{
  const g = new StateGraph(Order)
    .addNode("查库存", checkStock)
    .addNode("调风控", callRisk, {
      retryPolicy: {
        maxAttempts: 3,
        initialInterval: 10, // ⚠️ 毫秒（Python 是秒）
        logWarning: false, // ⚠️ TS 独有字段，默认 true 会往 stdout 打重试日志
      },
    })
    .addNode("出结论", decide)
    .addNode("通知", notify)
    .addEdge(START, "查库存")
    .addEdge("查库存", "调风控")
    .addEdge("调风控", "出结论")
    .addEdge("出结论", "通知")
    .addEdge("通知", END)
    .compile();

  const r = await g.invoke({ order_id: "SO-1", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));
  console.log(`调风控实际执行: ${ATTEMPTS.risk} 次`);

  // logWarning 默认值是 true —— 单独演示一次
  let n = 0;
  const flaky = (s: typeof Order.State) => {
    n += 1;
    if (n < 2) throw new ConnectionError("抖一下");
    return { log: [...s.log, "调风控:成功"] };
  };
  await new StateGraph(Order)
    .addNode("调风控", flaky, { retryPolicy: { maxAttempts: 2, initialInterval: 10 } })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile()
    .invoke({ order_id: "SO-1b", log: [], risk: 0, decision: "" });
  console.log("  ↑ 上面那行 Retrying task 就是 logWarning 默认为 true 的效果（Python 走 logging，打到 stderr）");
}

// ============================================================
// 坑一：抛 ValueError / 普通 Error 还会重试吗
// ============================================================
line("坑一：抛 ValueError 还会重试吗（TS 侧与 Python 相反）");

{
  const ATTEMPTS2 = { n: 0 };
  const callRiskVe = (s: typeof Order.State) => {
    ATTEMPTS2.n += 1;
    // Python 里对应 raise ValueError("风控返回了非法数据")
    // TS 没有独立的 ValueError 类型，`new Error` 就是最"普通"的错误
    throw new Error("风控返回了非法数据");
  };

  const g = new StateGraph(Order)
    .addNode("调风控", callRiskVe, {
      retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  try {
    await g.invoke({ order_id: "SO-2", log: [], risk: 0, decision: "" });
  } catch (e: any) {
    console.log(`${e.name}: ${e.message}`);
  }
  console.log(`调风控实际执行: ${ATTEMPTS2.n} 次   <- Python 是 1 次，TS 跑满 maxAttempts`);

  // 关掉重试：TS 侧必须写 retryOn 函数（黑名单是默认值）
  const ATTEMPTS2B = { n: 0 };
  const callRiskNo = (s: typeof Order.State) => {
    ATTEMPTS2B.n += 1;
    throw new Error("风控返回了非法数据");
  };
  const g2 = new StateGraph(Order)
    .addNode("调风控", callRiskNo, {
      retryPolicy: {
        maxAttempts: 3,
        initialInterval: 10,
        logWarning: false,
        // ⚠️ retryOn 只能传函数；`retryOn: Error` 是类型错误（Python 可直接传异常类）
        retryOn: (e: any) => !String(e?.message ?? "").includes("非法数据"),
      },
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  try {
    await g2.invoke({ order_id: "SO-2b", log: [], risk: 0, decision: "" });
  } catch (e: any) {
    console.log(`显式排除后: ${e.name}: ${e.message}`);
  }
  console.log(`显式排除后实际执行: ${ATTEMPTS2B.n} 次`);
}

// ============================================================
// 坑二：给同步节点配 timeout
// ============================================================
line("坑二：同步节点配 timeout");

const sleepSync = (ms: number) => {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    /* 同步阻塞 */
  }
};

const slowSync = (s: typeof Order.State) => {
  sleepSync(2000);
  return { log: [...s.log, "慢完成"] };
};

{
  const b = new StateGraph(Order)
    .addNode("调风控", slowSync, { timeout: 500 }) // ⚠️ 毫秒
    .addEdge(START, "调风控")
    .addEdge("调风控", END);

  // ⚠️ Python 在 compile() 阶段就抛 ValueError；TS 编译通过，运行期才抛 NodeTimeoutError
  const g = b.compile();
  console.log("compile 成功（TS 不像 Python 那样在编译期拦截同步节点 + timeout）");
  const t0 = Date.now();
  try {
    const r = await g.invoke({ order_id: "SO-3", log: [], risk: 0, decision: "" });
    console.log(`invoke 返回: ${JSON.stringify(r.log)}  elapsed=${Date.now() - t0}ms`);
  } catch (e: any) {
    console.log(
      `invoke -> ${e.name}: ${String(e.message).split("\n")[0]}  elapsed=${Date.now() - t0}ms`
    );
  }
}

// ============================================================
// 第一步：领域异常
// ============================================================
line("第一步：自定义领域异常");

const ATTEMPTS3 = { n: 0 };

const callRiskV2 = (s: typeof Order.State) => {
  ATTEMPTS3.n += 1;
  if (ATTEMPTS3.n < 3) {
    throw new RiskAPIError(`风控故障 ${ATTEMPTS3.n}`);
  }
  return { log: [...s.log, "调风控:成功"], risk: 0.3 };
};

{
  const g = new StateGraph(Order)
    .addNode("调风控", callRiskV2, {
      retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  const r = await g.invoke({ order_id: "SO-4", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));
  console.log(`实际执行: ${ATTEMPTS3.n} 次`);
}

// ============================================================
// 第二步：errorHandler 兜底
// ============================================================
line("第二步：errorHandler 兜底（返回值是普通对象 → 流程断在这）");

const riskFallback = (state: typeof Order.State) => {
  console.log(`  兜底收到 state: log=${JSON.stringify(state.log)}`);
  return { log: [...state.log, "调风控:兜底放行"], risk: 0.5 };
};

const ATTEMPTS4 = { n: 0 };

const alwaysDown = (s: typeof Order.State) => {
  ATTEMPTS4.n += 1;
  throw new RiskAPIError("风控彻底挂了");
};

{
  const g = new StateGraph(Order)
    .addNode("查库存", checkStock)
    .addNode("调风控", alwaysDown, {
      retryPolicy: { maxAttempts: 2, initialInterval: 10, logWarning: false },
      errorHandler: riskFallback,
    })
    .addNode("出结论", decide)
    .addNode("通知", notify)
    .addEdge(START, "查库存")
    .addEdge("查库存", "调风控")
    .addEdge("调风控", "出结论")
    .addEdge("出结论", "通知")
    .addEdge("通知", END)
    .compile();

  const r = await g.invoke({ order_id: "SO-5", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));
  console.log(`调风控执行: ${ATTEMPTS4.n} 次（重试用尽后才走兜底）`);
}

// ============================================================
// 第二步改法：Command 续上
// ============================================================
line("第二步改法：Command({ goto }) 续上流程");

const riskFallbackGoto = (state: typeof Order.State) =>
  new Command({
    goto: "出结论",
    update: { log: [...state.log, "调风控:兜底放行"], risk: 0.5 },
  });

{
  const g = new StateGraph(Order)
    .addNode("查库存", checkStock)
    .addNode("调风控", alwaysDown, {
      retryPolicy: { maxAttempts: 2, initialInterval: 10, logWarning: false },
      errorHandler: riskFallbackGoto,
      // ⚠️ TS 侧 errorHandler 返回 Command 时，同样要在 addNode 的 ends 里声明去处
      ends: ["出结论"],
    })
    .addNode("出结论", decide)
    .addNode("通知", notify)
    .addEdge(START, "查库存")
    .addEdge("查库存", "调风控")
    .addEdge("调风控", "出结论")
    .addEdge("出结论", "通知")
    .addEdge("通知", END)
    .compile();

  ATTEMPTS4.n = 0;
  const r = await g.invoke({ order_id: "SO-6", log: [], risk: 0, decision: "" });
  console.log(`Command({goto:'出结论'}) -> ${JSON.stringify(r.log)}`);
  console.log(`decision = ${r.decision}`);
  console.log(`调风控执行 ${ATTEMPTS4.n} 次`);
}

// ============================================================
// 第二步补充：TS 从哪拿异常
// ============================================================
line("第二步补充：errorHandler 怎么拿异常（TS 是第二参数，且被 NodeError 包了一层）");

{
  const seen: unknown[] = [];
  const probe = (state: typeof Order.State, error: unknown) => {
    seen.push(error);
    return { log: [...state.log, "兜底"], risk: 0.5 };
  };
  const g = new StateGraph(Order)
    .addNode("调风控", alwaysDown, {
      retryPolicy: { maxAttempts: 1, initialInterval: 10, logWarning: false },
      errorHandler: probe,
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  await g.invoke({ order_id: "SO-7", log: [], risk: 0, decision: "" });

  const err: any = seen[0];
  console.log("  第二参数 typeof:", typeof err);
  console.log("  顶层 keys:", JSON.stringify(Object.keys(err ?? {})));
  console.log("  err.node:", JSON.stringify(err?.node));
  console.log("  err.error?.name:", JSON.stringify(err?.error?.name));
  console.log("  err.message:", JSON.stringify(err?.message));
  console.log("  真正的异常在 err.error 里：", err?.error?.message);

  // 真实写法：解包一层
  const withUnwrap = (state: typeof Order.State, error: any) => {
    const real = error?.error ?? error;
    return { log: [...state.log, `兜底:${real?.name ?? "unknown"}`], risk: 0.5 };
  };
  const g2 = new StateGraph(Order)
    .addNode("调风控", alwaysDown, {
      retryPolicy: { maxAttempts: 1, initialInterval: 10, logWarning: false },
      errorHandler: withUnwrap,
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  const r2 = await g2.invoke({ order_id: "SO-7b", log: [], risk: 0, decision: "" });
  console.log("  解包后结果:", JSON.stringify(r2.log));
  console.log(
    "  对照：Python 的 errorHandler 是 (state) 单参，异常要从 config['configurable']['__pregel_node_error'] 翻"
  );
}

// ============================================================
// 第三步：async + timeout
// ============================================================
line("第三步：async 节点才配得上 timeout");

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const slowAsync = async (s: typeof Order.State) => {
  await sleep(2000);
  return { log: [...s.log, "慢完成"] };
};

{
  const g = new StateGraph(Order)
    .addNode("调风控", slowAsync, {
      timeout: 400, // ⚠️ 毫秒
      errorHandler: riskFallback,
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  const r = await g.invoke({ order_id: "SO-8", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));

  // timeout × retry 叠乘
  const ATT = { n: 0 };
  const slowRetry = async (s: typeof Order.State) => {
    ATT.n += 1;
    await sleep(2000);
    return { log: [...s.log, "慢完成"] };
  };
  const g2 = new StateGraph(Order)
    .addNode("调风控", slowRetry, {
      timeout: 300,
      retryPolicy: { maxAttempts: 3, initialInterval: 1, logWarning: false },
      errorHandler: riskFallback,
    })
    .addEdge(START, "调风控")
    .addEdge("调风控", END)
    .compile();
  const t0 = Date.now();
  const r2 = await g2.invoke({ order_id: "SO-9", log: [], risk: 0, decision: "" });
  console.log(
    `timeout×retry 叠乘: ${JSON.stringify(r2.log)}  执行 ${ATT.n} 次  耗时 ${Date.now() - t0}ms`
  );
}

// ============================================================
// 第四步：拆子图
// ============================================================
line("第四步：把风控拆成子图");

const RiskIn = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});

const riskSub = new StateGraph(RiskIn)
  .addNode("调风控", callRiskV2 as any, {
    retryPolicy: { maxAttempts: 3, initialInterval: 10, logWarning: false },
    errorHandler: riskFallback as any,
  })
  .addNode("判定", (s: typeof RiskIn.State) => ({ log: [...s.log, `风控判定:${s.risk}`] }))
  .addEdge(START, "调风控")
  .addEdge("调风控", "判定")
  .addEdge("判定", END)
  .compile();

{
  const g = new StateGraph(Order)
    .addNode("查库存", checkStock)
    .addNode("风控", riskSub) // ← 编译好的图当节点挂
    .addNode("出结论", decide)
    .addNode("通知", notify)
    .addEdge(START, "查库存")
    .addEdge("查库存", "风控")
    .addEdge("风控", "出结论")
    .addEdge("出结论", "通知")
    .addEdge("通知", END)
    .compile();

  ATTEMPTS3.n = 0;
  const r = await g.invoke({ order_id: "SO-10", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));
  console.log(`子图内调风控执行: ${ATTEMPTS3.n} 次`);
}

// ============================================================
// 第五步：状态隔离
// ============================================================
line("第五步：状态隔离——子图私有字段静默消失");

const RiskIn2 = Annotation.Root({
  order_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  log: Annotation<string[]>({ reducer: (_p, n) => n, default: () => [] }),
  risk: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  risk_detail: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }), // ← 子图私有
});

const sub2 = new StateGraph(RiskIn2)
  .addNode("调风控", (s: typeof RiskIn2.State) => ({
    risk: 0.3,
    risk_detail: "评分明细",
    log: [...s.log, "调风控:成功"],
  }))
  .addEdge(START, "调风控")
  .addEdge("调风控", END)
  .compile();

{
  const g = new StateGraph(Order)
    .addNode("风控", sub2)
    .addNode("出结论", (s: typeof Order.State) => ({
      log: [...s.log, `父图keys=${JSON.stringify(Object.keys(s).sort())}`],
    }))
    .addEdge(START, "风控")
    .addEdge("风控", "出结论")
    .addEdge("出结论", END)
    .compile();

  const r = await g.invoke({ order_id: "SO-11", log: [], risk: 0, decision: "" });
  console.log("结果:", JSON.stringify(r.log));
  console.log("父图最终 keys:", JSON.stringify(Object.keys(r).sort()));
}

// ============================================================
// 第六步：subgraphs = true
// ============================================================
line("第六步：子图内部排障要开 subgraphs: true");

{
  const saver = new MemorySaver();
  const g9 = new StateGraph(Order)
    .addNode("查库存", checkStock)
    .addNode("风控", riskSub)
    .addNode("出结论", decide)
    .addNode("通知", notify)
    .addEdge(START, "查库存")
    .addEdge("查库存", "风控")
    .addEdge("风控", "出结论")
    .addEdge("出结论", "通知")
    .addEdge("通知", END)
    .compile({ checkpointer: saver });

  const cfg = { configurable: { thread_id: "so-12" } };
  await g9.invoke({ order_id: "SO-12", log: [], risk: 0, decision: "" }, cfg);

  console.log("默认视角（父图历史）:");
  // ⚠️ getStateHistory 返回异步迭代器，外层还要 await
  for await (const s of await g9.getStateHistory(cfg)) {
    const ns = s.config?.configurable?.checkpoint_ns ?? "";
    console.log(`  ns=${JSON.stringify(ns).padEnd(5)} next=${JSON.stringify(s.next)}`);
  }

  console.log("subgraphs: true 视角:");
  // ⚠️ TS 的 stream 第二参数同时承载 config 与流选项，不像 Python 分成三个位置参数
  for await (const pair of (await g9.stream(
    { order_id: "SO-13", log: [], risk: 0, decision: "" },
    { streamMode: "updates", subgraphs: true, configurable: { thread_id: "so-13" } }
  )) as any) {
    const [ns, chunk] = pair as [string[], Record<string, unknown>];
    // ⚠️ TS 侧 chunk 是「节点名 → 输出」的映射，ns 是数组（Python 是元组）
    console.log(`  ns=${JSON.stringify(ns).padEnd(46)} chunk=${JSON.stringify(Object.keys(chunk))}`);
  }
}

console.log("\n=== app-10 全部完成 ===");
