// 应用实战 06 · Store 长期记忆（TypeScript 侧）
// 对照：../../应用实战/06-Store 长期记忆.md
// 运行：npm run a06
import {
  Annotation,
  END,
  InMemoryStore,
  MemorySaver,
  START,
  StateGraph,
  type LangGraphRunnableConfig,
} from "@langchain/langgraph";

const line = (t: string) => console.log(`\n===== ${t} =====`);

// ---------------------------------------------------------------- 第 1 跳（反面）
line("第 1 跳：把偏好存进状态里（错的做法）");
{
  const State = Annotation.Root({
    user_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    profile: Annotation<Record<string, unknown>>({ reducer: (_p, n) => n, default: () => ({}) }),
  });

  const writeNode = () => ({ profile: { prefers: "邮件沟通" } });
  const readNode = (s: typeof State.State) => ({ profile: s.profile ?? {} });

  const build = (node: (s: typeof State.State) => any) =>
    new StateGraph(State)
      .addNode("n", node)
      .addEdge(START, "n")
      .addEdge("n", END)
      .compile({ checkpointer: new MemorySaver() });

  const r1 = await build(writeNode).invoke(
    { user_id: "1", profile: {} },
    { configurable: { thread_id: "sess-1" } }
  );
  console.log("  sess-1(写):", r1.profile);

  const r2 = await build(readNode).invoke(
    { user_id: "1", profile: {} },
    { configurable: { thread_id: "sess-2" } }
  );
  console.log("  sess-2(读):", r2.profile);
  console.log("  -> 换会话就读不到，checkpointer 是 thread 作用域");
}

// ---------------------------------------------------------------- 第 2 跳
line("第 2 跳：挪到 Store，跨会话不丢");
{
  const State = Annotation.Root({
    user_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    seen: Annotation<Record<string, unknown> | null>({ reducer: (_p, n) => n, default: () => null }),
    note: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  // TS 侧没有"关键字参数注入"：store 挂在节点第二个参数的 store 字段上
  const node = async (s: typeof State.State, config: LangGraphRunnableConfig) => {
    const store = config.store!;
    const ns = [s.user_id, "preferences"]; // 按「用户」分格，不是按会话
    const item = await store.get(ns, "contact");
    if (item == null) {
      await store.put(ns, "contact", { prefers: "邮件沟通" });
      return { seen: null, note: "首次：已记下偏好" };
    }
    const v = item.value as { prefers: string };
    return { seen: item.value, note: `老客户：读到偏好 ${v.prefers}` };
  };

  const graph = new StateGraph(State)
    .addNode("n", node)
    .addEdge(START, "n")
    .addEdge("n", END)
    // 关键：store 建在图外面，三个 thread 共享同一个实例
    .compile({ checkpointer: new MemorySaver(), store: new InMemoryStore() });

  for (const tid of ["monday", "friday", "next-week"]) {
    const r = await graph.invoke(
      { user_id: "1" },
      { configurable: { thread_id: tid } }
    );
    console.log(`  thread=${tid.padEnd(10)} ${r.note}`);
  }

  const r2 = await graph.invoke({ user_id: "2" }, { configurable: { thread_id: "other" } });
  console.log("  user=2:", r2.note);
}

// ---------------------------------------------------------------- 第 3 跳
line("第 3 跳：三类记忆分层 + 热路径写入");
{
  const State = Annotation.Root({
    user_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    message: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
    profile: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
    episodes: Annotation<any[]>({ reducer: (_p, n) => n, default: () => [] }),
    rules: Annotation<any[]>({ reducer: (_p, n) => n, default: () => [] }),
    reply: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  });

  const assistant = async (s: typeof State.State, config: LangGraphRunnableConfig) => {
    const store = config.store!;
    const uid = s.user_id;
    const profileNs = [uid, "profile"];
    const episodeNs = [uid, "episodes"];
    const ruleNs = [uid, "rules"];

    // ① 语义：读档案（一份，固定 key）
    const p = await store.get(profileNs, "profile");
    let profile: Record<string, string> = (p?.value as Record<string, string>) ?? {};

    // ③ 程序：捞生效的规矩
    const rules = (await store.search(ruleNs, { filter: { enabled: true } })).map((i) => i.value);

    // ② 情景：捞最近经历（注意显式给 limit，默认只有 10 条）
    const episodes = (await store.search(episodeNs, { limit: 20 })).map((i) => i.value);

    // 热路径写入：本轮学到的新东西当场记下（在生成回复之前）
    if (s.message.includes("邮件")) {
      profile = { ...profile, prefers: "邮件沟通" }; // 合并旧的，别整条丢
      await store.put(profileNs, "profile", profile);
    }

    // key 带时间戳，永不覆盖
    await store.put(episodeNs, new Date().toISOString(), { event: s.message });

    const reply =
      `按${profile.prefers ?? "默认"}方式回复；` +
      `已知 ${episodes.length} 条历史；遵守 ${rules.length} 条规矩`;

    return { profile, episodes, rules, reply };
  };

  const shared = new InMemoryStore();
  await shared.put(["1", "rules"], "r1", { rule: "回复前先确认订单号", enabled: true });

  const graph = new StateGraph(State)
    .addNode("assistant", assistant)
    .addEdge(START, "assistant")
    .addEdge("assistant", END)
    .compile({ checkpointer: new MemorySaver(), store: shared });

  for (const [tid, msg] of [
    ["t1", "我偏好邮件沟通"],
    ["t2", "我的订单还没发货"],
  ] as const) {
    const r = await graph.invoke(
      { user_id: "1", message: msg },
      { configurable: { thread_id: tid } }
    );
    console.log(`  [${tid}] ${msg}`);
    console.log(`        -> ${r.reply}`);
    console.log(
      `        档案=${JSON.stringify(r.profile)}  历史=${r.episodes.length}条  规矩=${r.rules.length}条`
    );
  }
}

// ---------------------------------------------------------------- 三个坑
line("三个坑的实测");
{
  const store = new InMemoryStore();
  const ns = ["1", "memories"];

  // 坑 1：同 key 再 put 是整条覆盖
  await store.put(ns, "k0", { i: 0 });
  await store.put(ns, "k0", { i: 999 });
  console.log("  同 key 覆盖:", (await store.get(ns, "k0"))!.value);

  // 坑 2：search 默认只给 10 条
  for (let i = 0; i < 25; i++) await store.put(ns, `m${i}`, { i });
  console.log("  写 25 条，默认 search 回来:", (await store.search(ns)).length, "条");
  console.log("  显式 limit: 50 回来:", (await store.search(ns, { limit: 50 })).length, "条");

  // 坑 3：不挂 store 时，config.store 是 undefined
  const State = Annotation.Root({ x: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }) });
  const g = new StateGraph(State)
    .addNode("n", async (_s, cfg: LangGraphRunnableConfig) => {
      const st = cfg.store;
      if (st == null) throw new TypeError("Cannot read properties of undefined (reading 'search')");
      return { x: 1 };
    })
    .addEdge(START, "n")
    .addEdge("n", END)
    .compile();
  try {
    await g.invoke({ x: 0 });
  } catch (e: any) {
    console.log("  不挂 store:", e.name + ":", e.message);
  }
}
