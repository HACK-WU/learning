import { FakeDatabase, ToolProvider, mergeProviders } from "./src/execute/tools.js";
import { validateDefinition } from "./src/definition/agent-definition.js";
import { InvocationRuntime } from "./src/account/runtime.js";

const db = new FakeDatabase();
const p = mergeProviders(ToolProvider.builtin(db), ToolProvider.remote());

console.log("① 工具清单:", p.listNames().join(", "));
console.log("② 只读查询:", db.query("select * from orders"));
console.log("③ 写操作:", db.execute("ALTER TABLE users ADD COLUMN last_login TEXT"));
console.log("④ 变更后结构:", db.schemaOf("users").join(", "));

try {
  p.get("executeSql")!.parse({ sql: "DROP TABLE orders" });
  console.log("⑤ 危险语句: 未被拦截 ❌");
} catch (e) {
  console.log("⑤ 危险语句被拦:", (e as Error).message);
}

try {
  p.get("querySql")!.parse({ sql: "delete from orders" });
  console.log("⑥ querySql 越权: 未被拦截 ❌");
} catch (e) {
  console.log("⑥ querySql 越权被拦:", (e as Error).message);
}

console.log("⑦ 定义校验（审批引用不存在的工具）:");
console.log(
  "   ",
  validateDefinition({
    key: "k", name: "n", version: 1, prompt: "p",
    model: { provider: "fake" },
    tools: ["querySql"],
    policies: { requireApprovalFor: ["executeSql"] },
  }).join(" | ")
);

console.log("⑧ 定义校验（非法结构）:");
console.log("   ", validateDefinition({ key: "", name: "n", version: 0 }).slice(0, 3).join(" | "));

const rt = new InvocationRuntime();
const { ledger } = rt.create("req-1", { sql: "A" });
rt.addUsage(ledger.invocationId, { inputTokens: 100, toolCalls: 1 });
rt.finish(ledger.invocationId, "succeeded", { sql: "A" });
const dup = rt.create("req-1", { sql: "A" });
console.log("⑨ 同键同输入重复提交 → duplicated:", dup.duplicated, "| 得到旧账本:", dup.ledger.invocationId === ledger.invocationId);

try {
  rt.create("req-1", { sql: "B" });
  console.log("⑩ 同键异输入: 未被拒绝 ❌");
} catch (e) {
  console.log("⑩ 同键异输入被拒:", (e as Error).message);
}
