import { FakeDatabase, ToolProvider } from "./src/execute/tools.js";
import { AgentDefinitionSchema } from "./src/definition/agent-definition.js";
import { compileAgent, StateAnnotation } from "./src/compile/compiler.js";
import { FileSaver } from "./src/account/file-saver.js";

const db = new FakeDatabase();
const provider = ToolProvider.builtin(db);
const base = AgentDefinitionSchema.parse({
  key: "k", name: "n", version: 1, prompt: "p",
  model: { provider: "fake" },
  tools: ["querySql", "executeSql"],
  policies: { requireApprovalFor: ["executeSql"] },
});

// A. 有审批策略：写操作必须挂起
const withPolicy = compileAgent({ definition: base, db, provider }, new FileSaver(".ckpt-a"));
const ra: any = await withPolicy.graph.invoke(
  { messages: ["请在 orders 表加列 flag"] },
  { configurable: { thread_id: "a1" } }
);
console.log("A 有审批策略 → 是否挂起:", Array.isArray(ra.__interrupt__) && ra.__interrupt__.length > 0);

// B. 去掉审批策略（把 requireApprovalFor 置空）：同样的输入应直接执行完
const noPolicy = AgentDefinitionSchema.parse({
  ...base,
  policies: { requireApprovalFor: [] },
});
const withoutPolicy = compileAgent({ definition: noPolicy, db, provider }, new FileSaver(".ckpt-b"));
const rb: any = await withoutPolicy.graph.invoke(
  { messages: ["请在 orders 表加列 flag"] },
  { configurable: { thread_id: "b1" } }
);
console.log(
  "B 去掉审批策略 → 是否挂起:",
  Array.isArray(rb.__interrupt__) && rb.__interrupt__.length > 0,
  "| 执行结果:",
  JSON.stringify(rb.result)
);

// C. 拒绝：显式 resume 一个非 approve 的值（用独立 db，确保"没写入"可判定）
const dbC = new FakeDatabase();
const providerC = ToolProvider.builtin(dbC);
const rejectSaver = new FileSaver(".ckpt-c");
const forReject = compileAgent({ definition: base, db: dbC, provider: providerC }, rejectSaver);
const rc: any = await forReject.graph.invoke(
  { messages: ["请在 orders 表加列 flag"] },
  { configurable: { thread_id: "c1" } }
);
console.log("C1 先挂起:", Array.isArray(rc.__interrupt__) && rc.__interrupt__.length > 0);
console.log("C1 挂起时 orders 结构:", dbC.schemaOf("orders").join(","), "（应无 flag）");

const { Command } = await import("@langchain/langgraph");
const rd: any = await forReject.graph.invoke(new Command({ resume: "reject" }), {
  configurable: { thread_id: "c1" },
});
console.log("C2 拒绝后结果:", JSON.stringify(rd.result));
console.log("C2 拒绝后 orders 结构:", dbC.schemaOf("orders").join(","), "（应仍无 flag）");

// D. 通道归约：approval 取新、messages 追加
console.log("D 通道默认:", JSON.stringify(StateAnnotation.spec));
