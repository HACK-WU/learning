/**
 * 课 11《人在环中》TypeScript 探针。
 *
 * 全离线：模型是脚本桩，checkpointer 用 MemorySaver（进程内存）。
 * 每个 section 对应课文「第四幕 4.1」里的一组探针，输出存档见 l11-ts-output.txt。
 *
 * 跑法：npx tsx l11-hitl.ts
 */

import { createDeepAgent } from "deepagents";
import { MemorySaver, Command } from "@langchain/langgraph";
import { humanInTheLoopMiddleware, type HITLRequest, type Interrupt } from "langchain";
import { AIMessage, HumanMessage, type BaseMessage } from "@langchain/core/messages";
import { BaseChatModel } from "@langchain/core/language_models/chat_models";
import { section } from "./_shared.js";

/** 脚本模型：按顺序吐预设消息，不看输入。 */
class ScriptModel extends BaseChatModel {
	script: AIMessage[];

	constructor(script: AIMessage[]) {
		super({});
		this.script = script;
	}

	_llmType(): string {
		return "script";
	}

	/** 必须实现：中间件会调它绑定工具。 */
	bindTools(_tools: unknown[]): this {
		return this;
	}

	async _generate(_messages: BaseMessage[]) {
		const msg = this.script.shift() ?? new AIMessage("done");
		return { generations: [{ text: String(msg.content), message: msg }] };
	}
}

type AnyAgent = {
	invoke: (input: unknown, config?: unknown) => Promise<Record<string, unknown>>;
	getState: (config: unknown) => Promise<{ values: Record<string, unknown> }>;
};

const writeCall = (path: string, content: string, id = "w1") =>
	new AIMessage({
		content: "",
		tool_calls: [{ name: "write_file", args: { file_path: path, content }, id }],
	});

const twoWrites = new AIMessage({
	content: "",
	tool_calls: [
		{ name: "write_file", args: { file_path: "/a.txt", content: "A" }, id: "w1" },
		{ name: "write_file", args: { file_path: "/b.txt", content: "B" }, id: "w2" },
	],
});

const cfg = (threadId: string) => ({ configurable: { thread_id: threadId } });

const mk = (script: AIMessage[], opts: Record<string, unknown> = {}): AnyAgent =>
	createDeepAgent({
		model: new ScriptModel(script),
		checkpointer: new MemorySaver(),
		...opts,
	} as never) as unknown as AnyAgent;

/** 从一次调用结果里取出待批请求。 */
const interruptsOf = (out: Record<string, unknown>) =>
	(out.__interrupt__ ?? []) as Array<Interrupt<HITLRequest> & { id?: string }>;

/** 把 state.files 压成 {路径: 内容} 便于打印。 */
const filesOf = (out: Record<string, unknown>) => {
	const files = (out.files ?? {}) as Record<string, { content?: unknown }>;
	return Object.fromEntries(
		Object.entries(files).map(([k, v]) => [k, String(v?.content ?? "")]),
	);
};

/** 取所有工具结果消息。 */
const toolMsgsOf = (out: Record<string, unknown>) =>
	(out.messages as BaseMessage[]).filter((m) => m.getType() === "tool");

/** 1) 没有 checkpointer 会怎样 */
async function probe1() {
	section("1) 没有 checkpointer：TS 连中断都产生不了");
	const agent = createDeepAgent({
		model: new ScriptModel([writeCall("/a.txt", "hello"), new AIMessage("写完了")]),
		interruptOn: { write_file: true },
	} as never) as unknown as AnyAgent;
	try {
		const out = await agent.invoke({ messages: [new HumanMessage("写")] });
		console.log(`  居然没报错，keys=${Object.keys(out).join(",")}`);
	} catch (e) {
		const err = e as Error;
		console.log(`  抛错 ${err.constructor.name}: ${String(err.message).split("\n")[0]}`);
		console.log(`  → 不是"中断能产生但恢复失败"，而是第一次 invoke 就抛`);
	}
}

/** 2) 四种决策 */
async function probe2() {
	section("2) 四种决策：approve / edit / reject / respond");
	const cases: Array<[string, unknown]> = [
		["approve", { type: "approve" }],
		[
			"edit",
			{
				type: "edit",
				editedAction: { name: "write_file", args: { file_path: "/safe.txt", content: "改过的内容" } },
			},
		],
		["reject（带 message）", { type: "reject", message: "不许写这个文件" }],
		["reject（不带 message）", { type: "reject" }],
		["respond", { type: "respond", message: "我来处理这封邮件" }],
	];

	for (const [label, decision] of cases) {
		const agent = mk([writeCall("/a.txt", "x"), new AIMessage("收到")], {
			interruptOn: { write_file: true },
		});
		const c = cfg(`d-${label}`);
		await agent.invoke({ messages: [new HumanMessage("写")] }, c);
		const out = await agent.invoke(new Command({ resume: { decisions: [decision] } }), c);
		const t = toolMsgsOf(out)[0];
		console.log(`  ${label}:`);
		console.log(`      files = ${JSON.stringify(filesOf(out))}`);
		console.log(`      tool  = ${JSON.stringify(String(t?.content)).slice(0, 150)}`);
		console.log(`      status= ${JSON.stringify((t as unknown as { status?: string })?.status)}`);
	}
}

/** 3) when 谓词 + 谓词抛异常 */
async function probe3() {
	section("3) when 谓词：按参数条件拦，而不是按工具名");
	const onlySecrets = (req: { toolCall: { args: Record<string, unknown> } }) =>
		String(req.toolCall.args?.file_path ?? "").startsWith("/secrets/");

	for (const path of ["/public/ok.txt", "/secrets/key.txt"]) {
		const agent = mk([writeCall(path, "x"), new AIMessage("好")], {
			interruptOn: { write_file: { allowedDecisions: ["approve", "reject"], when: onlySecrets } },
		});
		const out = await agent.invoke({ messages: [new HumanMessage("写")] }, cfg(`w-${path}`));
		const intr = interruptsOf(out);
		console.log(`  写 ${path} → 中断 ${intr.length > 0}`);
		if (intr.length > 0) {
			const reqs = intr[0].value.actionRequests;
			console.log(`      待批 ${reqs.length} 条: ${reqs.map((r) => `${r.name}(${JSON.stringify(r.args)})`).join(", ")}`);
		}
	}

	const boom = () => {
		throw new Error("谓词炸了");
	};
	const agent = mk([writeCall("/a.txt", "x"), new AIMessage("好")], {
		interruptOn: { write_file: { allowedDecisions: ["approve"], when: boom } },
	});
	try {
		await agent.invoke({ messages: [new HumanMessage("写")] }, cfg("w-boom"));
		console.log("  谓词抛异常 → 被吞掉了");
	} catch (e) {
		console.log(`  谓词抛异常 → ${(e as Error).constructor.name}: ${String((e as Error).message).slice(0, 60)}`);
	}
}

/** 4) permissions 与 interruptOn 的叠加、以及 TS 没有 mode:"interrupt" */
async function probe4() {
	section("4) permissions 只有 allow/deny；没有 mode:'interrupt'");

	// A) 只配 deny：不中断，直接拒
	{
		const agent = mk([writeCall("/secrets/key.txt", "k"), new AIMessage("好")], {
			permissions: [{ operations: ["write"], paths: ["/secrets/**"], mode: "deny" }],
		});
		const out = await agent.invoke({ messages: [new HumanMessage("写密钥")] }, cfg("p-a"));
		console.log(`  A) 只 deny → 中断 ${interruptsOf(out).length > 0}，files=${JSON.stringify(filesOf(out))}`);
		console.log(`      tool = ${JSON.stringify(String(toolMsgsOf(out)[0]?.content))}`);
	}

	// B) deny + interruptOn：仍然中断，批准后照样被拒
	{
		const agent = mk([writeCall("/secrets/key.txt", "k"), new AIMessage("好")], {
			interruptOn: { write_file: true },
			permissions: [{ operations: ["write"], paths: ["/secrets/**"], mode: "deny" }],
		});
		const c = cfg("p-b");
		const out = await agent.invoke({ messages: [new HumanMessage("写密钥")] }, c);
		console.log(`  B) deny + interruptOn → 中断 ${interruptsOf(out).length > 0}（Python 这里不中断）`);
		const out2 = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), c);
		console.log(`      批准后 files=${JSON.stringify(filesOf(out2))}`);
		console.log(`      tool = ${JSON.stringify(String(toolMsgsOf(out2)[0]?.content))}`);
		console.log(`      → deny 不是"不问就拒"，而是"问了也拒"`);
	}

	// C) mode:"interrupt" 是 Python 写法，TS 会静默当 allow
	{
		const agent = mk([writeCall("/secrets/key.txt", "k"), new AIMessage("好")], {
			permissions: [{ operations: ["write"], paths: ["/secrets/**"], mode: "interrupt" }],
		});
		const out = await agent.invoke({ messages: [new HumanMessage("写密钥")] }, cfg("p-c"));
		console.log(`  C) mode:"interrupt" → 创建不报错，中断 ${interruptsOf(out).length > 0}`);
		console.log(`      files=${JSON.stringify(filesOf(out))}  ← 文件真的写进去了`);
	}
}

/** 5) 一次中断带多个待批调用；决策条数对不上会怎样 */
async function probe5() {
	section("5) batched 模式：一个中断打包多个待批调用");

	// 5-A 全部批准：两个都执行
	{
		const agent = mk([twoWrites, new AIMessage("都写完了")], { interruptOn: { write_file: true } });
		const c = cfg("b-all");
		const out = await agent.invoke({ messages: [new HumanMessage("写两个")] }, c);
		const intr = interruptsOf(out);
		console.log(`  中断 ${intr.length} 个，待批 ${intr[0].value.actionRequests.length} 条`);
		for (const r of intr[0].value.actionRequests) {
			console.log(`      ${r.name} ${JSON.stringify(r.args)}`);
		}
		console.log(`  reviewConfigs[0]: ${JSON.stringify(intr[0].value.reviewConfigs[0])}`);
		await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }, { type: "approve" }] } }), c);
		const st = await agent.getState(c);
		console.log(`  全批准 → files=${JSON.stringify(filesOf(st.values))}`);
	}

	// 5-B 混合决策：这是 TS 侧最危险的一处，approve 的调用被整条丢弃
	{
		const agent = mk([twoWrites, new AIMessage("都写完了")], { interruptOn: { write_file: true } });
		const c = cfg("b-mix");
		await agent.invoke({ messages: [new HumanMessage("写两个")] }, c);
		const out = await agent.invoke(
			new Command({ resume: { decisions: [{ type: "approve" }, { type: "reject", message: "第二个不许" }] } }),
			c,
		);
		const st = await agent.getState(c);
		console.log(`  批准第一个 + 拒绝第二个 → files=${JSON.stringify(filesOf(st.values))}`);
		const msgs = out.messages as BaseMessage[];
		console.log(`      消息数 ${msgs.length}（全批准时是 5 条）`);
		const aiWithCalls = msgs.filter((m) => ((m as unknown as { tool_calls?: unknown[] }).tool_calls ?? []).length > 0);
		for (const m of aiWithCalls) {
			const ids = ((m as unknown as { tool_calls: Array<{ id: string }> }).tool_calls ?? []).map((t) => t.id);
			console.log(`      ai 消息里的 tool_calls 只剩: ${ids.join(",") || "（空）"}`);
		}
		console.log(`      → 被批准的第一个调用连 ToolMessage 都没有，整个消失`);
	}

	// 5-C 决策条数对不上 / 恢复时换 thread_id
	{
		const a2 = mk([twoWrites, new AIMessage("都写完了")], { interruptOn: { write_file: true } });
		const c2 = cfg("b-empty");
		await a2.invoke({ messages: [new HumanMessage("写两个")] }, c2);
		try {
			await a2.invoke(new Command({ resume: { decisions: [] } }), c2);
			console.log("  传空 decisions → 没报错");
		} catch (e) {
			console.log(`  传空 decisions → ${String((e as Error).message).slice(0, 110)}`);
		}

		const a3 = mk([writeCall("/a.txt", "x"), new AIMessage("好")], { interruptOn: { write_file: true } });
		await a3.invoke({ messages: [new HumanMessage("写")] }, cfg("t-orig"));
		const out3 = await a3.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), cfg("t-other"));
		console.log(`  换 thread_id 恢复 → 不报错，files=${JSON.stringify(filesOf(out3))}  ← 什么都没发生`);
	}
}

/** 6) per_call 模式：每个闸门一个独立中断，按中断 id 回复 */
async function probe6() {
	section("6) per_call 模式：一调用一中断，回复要带中断 id");
	const agent = createDeepAgent({
		model: new ScriptModel([twoWrites, new AIMessage("都写完了")]),
		checkpointer: new MemorySaver(),
		middleware: [humanInTheLoopMiddleware({ interruptOn: { write_file: true }, interruptMode: "per_call" })],
	} as never) as unknown as AnyAgent;
	const c = cfg("pc1");
	const out = await agent.invoke({ messages: [new HumanMessage("写两个")] }, c);
	const intr = interruptsOf(out);
	console.log(`  中断 ${intr.length} 个（batched 模式这里只有 1 个）`);
	for (const i of intr) {
		const v = i.value as unknown as { type: string; tool_call_id: string; name: string; args: unknown };
		console.log(`      id=${String(i.id).slice(0, 8)}… type=${v.type} tool_call_id=${v.tool_call_id} args=${JSON.stringify(v.args)}`);
	}
	// 按 id 逐个回复
	let last: Record<string, unknown> = out;
	for (const i of intr) {
		last = await agent.invoke(
			new Command({
				resume: {
					[String(i.id)]: { type: "approve" },
				},
			}),
			c,
		);
	}
	const st = await agent.getState(c);
	console.log(`  逐个批准后 files=${JSON.stringify(filesOf(st.values))}`);
	console.log(`  最后一轮是否还有中断: ${interruptsOf(last).length > 0}`);

	// editNotice 只在 per_call 生效
	{
		const a2 = createDeepAgent({
			model: new ScriptModel([writeCall("/a.txt", "x"), new AIMessage("好")]),
			checkpointer: new MemorySaver(),
			middleware: [
				humanInTheLoopMiddleware({ interruptOn: { write_file: true }, interruptMode: "per_call", editNotice: "【人改过了】" }),
			],
		} as never) as unknown as AnyAgent;
		const c2 = cfg("pc-edit");
		const o1 = await a2.invoke({ messages: [new HumanMessage("写")] }, c2);
		const id = String(interruptsOf(o1)[0].id);
		const o2 = await a2.invoke(
			new Command({
				resume: {
					[id]: { type: "edit", edited_action: { name: "write_file", args: { file_path: "/safe2.txt", content: "改过2" } } },
				},
			}),
			c2,
		);
		console.log(`  per_call + edit → tool = ${JSON.stringify(String(toolMsgsOf(o2)[0]?.content)).slice(0, 220)}`);
	}

	// batched 会丢的混合决策，per_call 不会丢
	{
		const a3 = createDeepAgent({
			model: new ScriptModel([twoWrites, new AIMessage("都写完了")]),
			checkpointer: new MemorySaver(),
			middleware: [humanInTheLoopMiddleware({ interruptOn: { write_file: true }, interruptMode: "per_call" })],
		} as never) as unknown as AnyAgent;
		const c3 = cfg("pc-mix");
		const o1 = await a3.invoke({ messages: [new HumanMessage("写两个")] }, c3);
		const list = interruptsOf(o1);
		const second = list.find((i) => (i.value as unknown as { tool_call_id: string }).tool_call_id === "w2")!;
		const first = list.find((i) => (i.value as unknown as { tool_call_id: string }).tool_call_id === "w1")!;
		await a3.invoke(new Command({ resume: { [String(second.id)]: { type: "reject", message: "第二个不许" } } }), c3);
		await a3.invoke(new Command({ resume: { [String(first.id)]: { type: "approve" } } }), c3);
		const st = await a3.getState(c3);
		console.log(`  per_call 混合决策（拒一个批一个）→ files=${JSON.stringify(filesOf(st.values))}`);
		console.log(`      → batched 在这里会把 /a.txt 整条丢掉，per_call 保住了`);
	}
}

/** 7) 子代理的审批会拦住整张父图 */
async function probe7() {
	section("7) 子代理配 interruptOn：父图整体暂停");
	const parent = new ScriptModel([
		new AIMessage({
			content: "",
			tool_calls: [{ name: "task", args: { description: "写个文件", subagent_type: "writer" }, id: "t1" }],
		}),
		new AIMessage("好"),
	]);
	const child = new ScriptModel([writeCall("/from-child.txt", "子代理写的"), new AIMessage("写完了")]);
	const agent = createDeepAgent({
		model: parent,
		checkpointer: new MemorySaver(),
		subagents: [{ name: "writer", description: "写文件", model: child, interruptOn: { write_file: true } }],
	} as never) as unknown as AnyAgent;
	const c = cfg("sa1");
	const out = await agent.invoke({ messages: [new HumanMessage("派活")] }, c);
	const intr = interruptsOf(out);
	console.log(`  父图中断 ${intr.length > 0}`);
	if (intr.length > 0) {
		console.log(`      待批动作: ${intr[0].value.actionRequests.map((r) => r.name).join(",")}`);
		const out2 = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), c);
		const st = await agent.getState(c);
		console.log(`      批准后 files=${JSON.stringify(filesOf(st.values))}`);
		console.log(`      子代理报告 = ${JSON.stringify(String(toolMsgsOf(out2)[0]?.content)).slice(0, 80)}`);
	}

	// 中断后不改主意、直接插一句新话
	{
		const a2 = mk([writeCall("/a.txt", "x"), new AIMessage("好")], { interruptOn: { write_file: true } });
		const c2 = cfg("sa2");
		await a2.invoke({ messages: [new HumanMessage("写")] }, c2);
		const o = await a2.invoke({ messages: [new HumanMessage("算了别写了")] }, c2);
		const msgs = o.messages as BaseMessage[];
		console.log(`  中断后插新消息 → 消息数 ${msgs.length}`);
		for (const t of toolMsgsOf(o)) {
			console.log(`      补的 tool = ${JSON.stringify(String(t.content)).slice(0, 160)}`);
		}
	}
}

/** 8) 中间件栈：配了才装 HumanInTheLoopMiddleware */
async function probe8() {
	section("8) HITL 中间件只在配了 interruptOn 时才进栈");
	const m = new ScriptModel([new AIMessage("hi")]);
	for (const [label, opts] of [
		["不配", {}],
		["配了 interruptOn", { interruptOn: { write_file: true } }],
	] as Array<[string, Record<string, unknown>]>) {
		const a = createDeepAgent({ model: m, ...opts } as never) as unknown as {
			options?: { middleware?: Array<{ name?: string }> };
		};
		const names = (a.options?.middleware ?? []).map((x) => x?.name ?? "?");
		console.log(`  ${label}: ${names.length} 条`);
		console.log(`      ${names.join(" → ")}`);
	}
}

async function main() {
	console.log("课 11 TypeScript 探针 · 全离线（脚本桩模型 + 内存 checkpointer）");
	await probe1();
	await probe2();
	await probe3();
	await probe4();
	await probe5();
	await probe6();
	await probe7();
	await probe8();

	section("结论：TS 与 Python 的七处硬差异");
	console.log("1. batched 混合决策会丢调用：TS 只要有一条 reject，同批所有 approve 的调用整条消失（连 ToolMessage 都没有）；Python 正常执行被批准的");
	console.log("2. 无 checkpointer：Python 中断能产生、恢复才报错；TS 第一次 invoke 就抛 GraphValueError");
	console.log("3. permissions 没有 interrupt 模式：写 mode:'interrupt' 不报错，被当 allow，文件直接写进去了");
	console.log("4. deny + interruptOn 叠加：Python deny 赢、不中断；TS 仍然中断，批准后才发现被拒");
	console.log("5. batched 模式 edit：Python 会加 'Note: a human reviewer replaced...' 前缀；TS 不加（原样返回工具结果）");
	console.log("6. reject 不带 message：Python 给完整解释（Do not retry...）；TS 只有 'User rejected the tool call for `write_file` with id w1'");
	console.log("7. 悬空调用修补文案：Python 'did not complete - no result was recorded'；TS 'was cancelled - another message came in'");
}

main().catch((e) => {
	console.error("FATAL", e);
	process.exit(1);
});
