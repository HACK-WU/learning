// 对应课 6《Store 长期记忆》
// 运行：npm run l06
import {
  StateGraph,
  Annotation,
  START,
  END,
  MemorySaver,
  InMemoryStore,
  type LangGraphRunnableConfig,
} from "@langchain/langgraph";

const State = Annotation.Root({
  user_id: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  // 反例：把"这个人是谁"塞进 State
  profile: Annotation<Record<string, string>>({
    reducer: (_p, n) => n,
    default: () => ({}),
  }),
  notes: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
});

// ── 1. Store 不挂图也能用（官方 basic usage）
const store = new InMemoryStore();
const ns = ["1", "memories"];
await store.put(ns, "m1", { food_preference: "I like pizza" });
await store.put(ns, "m2", { food_preference: "I like sushi" });
const one = await store.get(ns, "m1");
console.log("get:", JSON.stringify(one));
console.log("search:", (await store.search(ns)).map((i) => `${i.key}=${JSON.stringify(i.value)}`));

// ── 2. 挂到图上：节点第二参数里的 store
const buildGraph = (st: InMemoryStore) =>
  new StateGraph(State)
    .addNode("remember", async (s, config: LangGraphRunnableConfig) => {
      const store2 = config.store!; // ← TS 侧从 config 取，不是函数签名声明
      const found = await store2.search([s.user_id, "memories"], { limit: 20 });
      // 热路径写入：本轮的"问候"记到这个用户名下
      await store2.put([s.user_id, "memories"], `g${found.length + 1}`, {
        said: `来自 thread 的问候 #${found.length + 1}`,
      });
      return { notes: [`本轮读到 ${found.length} 条`] };
    })
    .addEdge(START, "remember")
    .addEdge("remember", END)
    .compile({ checkpointer: new MemorySaver(), store: st });

// ── 3. 跨 thread 累积（同一个 user_id，用一个干净的 store）
const sharedStore = new InMemoryStore();
const graph = buildGraph(sharedStore);
for (const t of ["session-A", "session-B", "session-C"]) {
  const r = await graph.invoke({ user_id: "1", profile: {}, notes: [] }, {
    configurable: { thread_id: t },
  });
  const items = await sharedStore.search(["1", "memories"]);
  console.log(`thread=${t}: 本轮=${JSON.stringify(r.notes)} 长期共 ${items.length} 条`);
}
// 换 user_id（命名空间不同）
const other = await graph.invoke({ user_id: "2", profile: {}, notes: [] }, {
  configurable: { thread_id: "session-D" },
});
console.log(`user=2 thread=session-D: ${JSON.stringify(other.notes)}`);

// ── 4. 坑：把 thread_id 当命名空间第一层
const bad = new InMemoryStore();
await bad.put(["session-A", "prefs"], "lang", { v: "Python" });
await bad.put(["session-B", "prefs"], "lang", { v: "Go" });
console.log("新会话搜 session-C:", (await bad.search(["session-C", "prefs"])).length, "条");

// ── 5. 三类记忆：语义 / 情景 / 程序
await store.put(["u1", "profile"], "profile", {
  name: "小王", prefers: "邮件沟通", timezone: "Asia/Shanghai",
});
await store.put(["u1", "episodes"], "2026-10-08-refund", {
  event: "申请退款被拒", reason: "超过 7 天无理由期限",
});
await store.put(["u1", "episodes"], "2026-10-12-rebuy", { event: "再次下单" });
await store.put(["u1", "rules"], "greeting", { rule: "回复前先确认订单号", enabled: true });

const profile = await store.get(["u1", "profile"], "profile");
const episodes = await store.search(["u1", "episodes"], { limit: 20 });
const rules = await store.search(["u1", "rules"], { filter: { enabled: true } });
console.log("profile.value:", JSON.stringify(profile?.value));
console.log("episodes:", episodes.map((i) => i.key));
console.log("rules(filter enabled):", rules.map((i) => i.key));

// ── 6. filter 对照
const f = new InMemoryStore();
await f.put(["u", "m"], "a", { kind: "preference" });
await f.put(["u", "m"], "b", { kind: "episode" });
console.log("filter kind=preference:", (await f.search(["u", "m"], { filter: { kind: "preference" } })).map((i) => i.key));
console.log("无 filter:", (await f.search(["u", "m"])).map((i) => i.key));

// ── 7. limit 默认 10 静默截断
const bulk = new InMemoryStore();
for (let i = 0; i < 25; i++) await bulk.put(["bulk"], `k${i}`, { i });
console.log("写 25 条，不带 limit:", (await bulk.search(["bulk"])).length, "带 limit=100:", (await bulk.search(["bulk"], { limit: 100 })).length);

// ── 8. 不配 embedding 就传 query：静默忽略
const q = new InMemoryStore();
await q.put(["1", "memories"], "q1", { food: "pizza" });
await q.put(["1", "memories"], "q2", { other: 1 });
console.log("无 query:", (await q.search(["1", "memories"])).map((i) => i.key));
console.log("query='pizza':", (await q.search(["1", "memories"], { query: "pizza" })).map((i) => i.key));

// ── 9. 覆盖语义 + delete
await store.put(["u", "m"], "k0", { i: 0 });
await store.put(["u", "m"], "k0", { i: 999, edited: true });
console.log("同 key 再 put:", JSON.stringify((await store.get(["u", "m"], "k0"))?.value));
await store.delete(["u", "m"], "k0");
console.log("delete 后 get:", await store.get(["u", "m"], "k0"));

// ── 10. 反例：只挂 checkpointer，节点里拿不到 store
const noStore = new StateGraph(State)
  .addNode("n", async (_s, config: LangGraphRunnableConfig) => {
    console.log("不挂 store 时 config.store:", config.store);
    try {
      await config.store!.get(["1", "memories"], "m1");
    } catch (e) {
      console.log("直接使用报错:", (e as Error).message.slice(0, 90));
    }
    return {};
  })
  .addEdge(START, "n")
  .addEdge("n", END)
  .compile({ checkpointer: new MemorySaver() });

await noStore.invoke({}, { configurable: { thread_id: "t-nostore" } });

// ── 11. TTL：TS 侧 put 没有 ttl 参数（类型层面就没有）
console.log("InMemoryStore.put 参数个数:", InMemoryStore.prototype.put.length);
console.log("listNamespaces:", JSON.stringify(await store.listNamespaces({ prefix: ["1"] })));
