/**
 * 课 13《Testing 与 Observability》TS 复刻脚本
 *
 * 对应 Python 的 playground/lesson-13-*-lab.py 系列与 playground/tests_l13/ 测试套件。
 * 本脚本用 LangChain.js 官方测试/评估栈复现课 13 的各层测试与可观测性演示：
 *   - 单元测试层：fakeModel（langchain 包）替换模型 + MemorySaver 内存持久化
 *   - 轨迹匹配层：agentevals 包 createTrajectoryMatchEvaluator（strict/unordered/subset/superset）
 *   - LLM 裁判层：agentevals 包 createTrajectoryLLMAsJudge（接自定义端点模型）
 *   - 可观测性：BaseCallbackHandler 自建迷你 trace 收集器（对应 Python set_debug / callback）
 *
 * 运行方式（接本地 OpenAI 兼容 mock，端口 8931）：
 *   BAILIAN_BASE_URL=http://127.0.0.1:8931/v1 BAILIAN_API_KEY=mock \
 *     npx tsx 13-testing-lab.ts | tee lc-l13-ts-output.txt
 *
 * LangChain.js 官方写法核对来源：
 *   docs.langchain.com/oss/javascript/langchain/test/unit-testing（fakeModel）
 *   docs.langchain.com/oss/javascript/langchain/test/evals（agentevals）
 */

import { fakeModel, initChatModel, createAgent } from "langchain";
import { AIMessage, HumanMessage, ToolMessage, BaseMessage } from "@langchain/core/messages";
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { MemorySaver } from "@langchain/langgraph";
import { BaseCallbackHandler } from "@langchain/core/callbacks/base";
import {
  createTrajectoryMatchEvaluator,
  createTrajectoryLLMAsJudge,
  TRAJECTORY_ACCURACY_PROMPT,
} from "agentevals";

// ============ 工具定义（与 Python 侧 get_weather / query_order 等对应） ============
const getWeather = tool(
  async ({ city }) => `北京：晴，${city} 22°C。`,
  {
    name: "get_weather",
    description: "查询城市天气",
    schema: z.object({ city: z.string() }),
  }
);

const queryOrder = tool(
  async ({ order_id }: { order_id: string }) =>
    `订单 ${order_id}：已发货，承运商=顺丰，运单号 SF10086`,
  {
    name: "query_order",
    description: "查询订单状态",
    schema: z.object({ order_id: z.string() }),
  }
);
const queryLogistics = tool(
  async ({ order_id }: { order_id: string }) => `订单 ${order_id}：正在派送中`,
  {
    name: "query_logistics",
    description: "查询物流信息",
    schema: z.object({ order_id: z.string() }),
  }
);
const applyReturn = tool(
  async ({ order_id }: { order_id: string }) =>
    `已为订单 ${order_id} 发起退货申请，退货单号=R20240916`,
  {
    name: "apply_return",
    description: "发起退货申请",
    schema: z.object({ order_id: z.string() }),
  }
);

// ============ 知识点 1：三种打脸的认识（非确定性）. 用 fakeModel 造「路径变」 ============
// 说明：真实模型的路径分岔是概率性的（Python 侧已实测 5 跑出 4 种路径）；
// TS 侧用假模型「剧本」精确制造同一场景下走/不走「办退货」的两条轨迹，用于说明断言对象。

function makeReturnTrajectory(didReturn: boolean): BaseMessage[] {
  const msgs: BaseMessage[] = [
    new HumanMessage("这个订单 A12345 我不想要了，帮我处理一下"),
    new AIMessage({
      content: "",
      tool_calls: [{ name: "query_order", args: { order_id: "A12345" }, id: "c1" }],
    }),
    new ToolMessage({ content: "订单 A12345：已发货，顺丰，SF10086", tool_call_id: "c1" }),
  ];
  if (didReturn) {
    msgs.push(
      new AIMessage({
        content: "",
        tool_calls: [{ name: "apply_return", args: { order_id: "A12345" }, id: "c2" }],
      }),
      new ToolMessage({ content: "已发起退货申请，R20240916", tool_call_id: "c2" }),
      new AIMessage("已为您发起退货申请……")
    );
  } else {
    msgs.push(
      new AIMessage({
        content: "",
        tool_calls: [{ name: "query_logistics", args: { order_id: "A12345" }, id: "c2" }],
      }),
      new ToolMessage({ content: "订单 A12345：正在派送中", tool_call_id: "c2" }),
      new AIMessage("订单正在派送中，给您两个选择……")
    );
  }
return msgs as BaseMessage[];
}

// ============ 知识点 2-①：单元测试层（fakeModel 替换模型） ============
async function testUnitLayer() {
  console.log("\n===== 单元测试层：fakeModel 替换模型（对应知识点 2 第一层）=====");
  // 剧本：第一条消息发起工具调用，第二条给出最终回答（与 Python GenericFakeChatModel 对应）
  // 关键差异：fakeModel 自动支持 bindTools，无需 Python 侧的 ScriptedToolModel 补丁
  const model = fakeModel()
    .respondWithTools([
      { name: "get_weather", args: { city: "北京" }, id: "call_1" },
    ])
    .respond(new AIMessage("北京今天晴，22 度。"));
  const agent = createAgent({ model, tools: [getWeather] });
  const result = await agent.invoke({
    messages: [new HumanMessage("北京天气？")],
  });
  const msgs = result.messages;
  const types = msgs.map((m: any) => m._getType()).join(" → ");
  console.log("断言① 消息序列（应为 human → ai → tool → ai）:", types);
  console.log("  → 序列断言:", types === "human → ai → tool → ai");
  const toolType = msgs[2]._getType();
  console.log("断言② 第 3 条是工具结果（type 应为 tool）:", toolType);
  console.log("  → 类型断言:", toolType === "tool");
  console.log("断言③ 工具被调用且内容非空（结构断言的核心）:", (msgs[2] as ToolMessage).content.length > 0);
  console.log("  → 结构断言(3/3):", types === "human → ai → tool → ai" && toolType === "tool" && (msgs[2] as any).content.length > 0);
  console.log("📌 TS 差异: fakeModel 自动实现 bindTools（官方文档快照核对），"
    + "Python 侧 GenericFakeChatModel 挂工具到 create_agent 会抛 NotImplementedError 需补子类。");
  console.log("   model.callCount（spy 断言调用次数）:", model.callCount);

  // 多轮记忆（MemorySaver 对应 Python InMemorySaver）
  console.log("--- 多轮记忆（MemorySaver）---");
  const m2 = fakeModel()
    .respond(new AIMessage("我叫小明"))
    .respond(new AIMessage("是啊，刚才说过了"));
  const agent2 = createAgent({ model: m2, tools: [], checkpointer: new MemorySaver() });
  const cfg = { configurable: { thread_id: "t1" } };
  const a = await agent2.invoke({ messages: [new HumanMessage("你叫什么")] }, cfg);
  const b = await agent2.invoke({ messages: [new HumanMessage("再叫一次")] }, cfg);
  console.log("首轮输入消息数:", a.messages.length, "| 次轮输入消息数:", b.messages.length, "(记忆接续)");
}

// ============ 知识点 2-④：轨迹匹配（agentevals，确定性，无需模型） ============
async function testTrajectoryMatch() {
  console.log("\n===== 轨迹匹配层：agentevals createTrajectoryMatchEvaluator（对应知识点 2 第三层）=====");
  // 参考轨迹：期望行为 = 查订单 → 发起退货 → 告知结果
  const reference = makeReturnTrajectory(true);
  // 「没办成事」：只查了订单 + 物流，没有 apply_return
  const missed = makeReturnTrajectory(false);

  const superset = createTrajectoryMatchEvaluator({ trajectoryMatchMode: "superset" });
  const sup = await superset({ outputs: missed, referenceOutputs: reference });
  console.log("superset 判「没办成」轨迹  →", sup.score, "(应 false：缺必要动作 apply_return)");

  const strict = createTrajectoryMatchEvaluator({ trajectoryMatchMode: "strict" });
  const unordered = createTrajectoryMatchEvaluator({ trajectoryMatchMode: "unordered" });
  // strict：语义是「结构一致、顺序一致」——这里换了一条顺序不同的轨迹
  const reversed = [reference[0], reference[5], reference[1], reference[2], reference[3], reference[4]];
  const st = await strict({ outputs: reversed, referenceOutputs: reference });
  const un = await unordered({ outputs: makeReturnTrajectory(true), referenceOutputs: reference });
  console.log("strict 换序（应 false，顺序敏感）:", st.score);
  console.log("unordered 同构（应 true，顺序无关）:", un.score);

  // subset：实际调用 ⊆ 参考（防多动作）；给「多查了一个物流」的轨迹
  const sub = createTrajectoryMatchEvaluator({ trajectoryMatchMode: "subset" });
  const subResult = await sub({ outputs: makeReturnTrajectory(false), referenceOutputs: reference });
  console.log("subset 实际含参考外动作（应 false，超范围）:", subResult.score);
}

// ============ 知识点 2-④：LLM 裁判（agentevals，需真实模型，mock 文本不可作 json_schema 评分） ============
async function testLLMJudge() {
  console.log("\n===== LLM 裁判层：agentevals createTrajectoryLLMAsJudge（对应知识点 2 第三层）=====");
  // 与 Python 侧 create_trajectory_llm_as_judge 对应。TS 侧只接受「字符串模型标识」，
  // 内部经 initChatModel 解析 provider，端点/apiKey 从 OPENAI_BASE_URL / OPENAI_API_KEY 读取。
  // 实测路径：链路走得通（发出现带 json_schema 结构化输出的评分请求），
  // 但 mock 只返回固定文本、无法满足 json_schema 解析 —— 需接真实模型端点才能拿到 score。
  const judge = createTrajectoryLLMAsJudge({
    model: "openai:qwen3.8-flash",
    prompt: TRAJECTORY_ACCURACY_PROMPT,
  });
  const trajectory = makeReturnTrajectory(true);
  try {
    const result = await judge({ outputs: trajectory });
    console.log("judge key:", result.key);
    console.log("judge score:", result.score);
  } catch (e: any) {
    console.log("📌 judge 实测说明：链路已发起（带 response_format 结构化评分请求），"
      + "但本机 mock 返回非结构化文本，评分解析报:", e.message.slice(0, 60));
    console.log("   与 Python 侧一致——LLM 裁判需接真实模型端点（能回 json_schema），mock 不满足。");
    console.log("   TS 侧端口接法同 Python: model:'openai:qwen3.8-flash' + OPENAI_BASE_URL 指向真实端点");
  }
}

// ============ 知识点 3：可观测性（BaseCallbackHandler 迷你 trace 收集器） ============
class MiniTraceHandler extends BaseCallbackHandler {
  name = "MiniTraceHandler";
  events: string[] = [];
  private _prevTs = 0;
  constructor() { super(); this._prevTs = Date.now(); }

  async handleChatModelStart(_llm: any, messages: any[][]) {
    const dt = ((Date.now() - this._prevTs) / 1000).toFixed(2);
    this._prevTs = Date.now();
    this.events.push(`+${dt.padStart(6, '0')}s  ▶ LLM 调用（输入 ${messages[0].length} 条消息）`);
  }
  async handleLLMEnd(response: any) {
    const dt = ((Date.now() - this._prevTs) / 1000).toFixed(2);
    this._prevTs = Date.now();
    const toolCalls = response?.generations?.[0]?.[0]?.message?.tool_calls;
    if (toolCalls?.length) {
      const tc = toolCalls[0];
      this.events.push(`+${dt.padStart(6, '0')}s  ◀ LLM 返回：请求调用工具 → ${tc.name}(${JSON.stringify(tc.args)})`);
    } else {
      const text = response?.generations?.[0]?.[0]?.text;
      this.events.push(`+${dt.padStart(6, '0')}s  ◀ LLM 返回文本：${text}`);
    }
  }
  async handleToolStart(_tool: any, input: string) {
    const dt = ((Date.now() - this._prevTs) / 1000).toFixed(2);
    this._prevTs = Date.now();
    this.events.push(`+${dt.padStart(6, '0')}s  ▶ 工具执行${input ? " " + input.replace(/\s+/g, ' ').slice(0, 40) : ""}`);
  }
async handleToolEnd(output: unknown) {
    const dt = ((Date.now() - this._prevTs) / 1000).toFixed(2);
    this._prevTs = Date.now();
    const text = typeof output === "string" ? output : JSON.stringify(output);
    this.events.push(`+${dt.padStart(6, '0')}s  ◀ 工具返回：${text.slice(0, 30)}…`);
  }
}

async function testObservability() {
  console.log("\n===== 可观测性：BaseCallbackHandler 迷你 trace 收集器（对应知识点 3 本地替代）=====");
  // 等价于 Python 的知识点 3 手段 2（自建 callback 收集器）；fakeModel 完全离线，事件可精确断言
  const handler = new MiniTraceHandler();
  const model = fakeModel()
    .respondWithTools([{ name: "get_weather", args: { city: "北京" }, id: "call_1" }])
    .respond(new AIMessage("北京：晴，22 度。"));
  const agent = createAgent({ model, tools: [getWeather] });
  await agent.invoke(
    { messages: [new HumanMessage("北京天气？")] },
    { callbacks: [handler] }
  );
  console.log("收集到的 trace 时间线（一次真实运行的留痕）：");
  for (const e of handler.events) console.log("  " + e);
  console.log("📌 与 Python set_debug/callback 对应：TS 侧用 BaseCallbackHandler 子类，钩子为 handleChatModelStart/LLMEnd/ToolStart/ToolEnd。");
}

// ============ 主流程 ============
async function main() {
  console.log("=== 课 13 · TS 复刻：Testing 与 Observability ===");
  await testUnitLayer();
  await testTrajectoryMatch();
  await testLLMJudge();
  await testObservability();
  console.log("\n=== 课 13 全部板块运行完毕 ===");
}

main().catch((e) => {
  console.error("课 13 脚本失败:", e);
  process.exit(1);
});