/**
 * 课 12 · 异步与动态子代理 —— TypeScript 侧实测探针
 *
 * 对齐 Python 侧探针 1-8，但每条都要重新验，因为两侧差异很大：
 *   1) graphId 才是分流开关（Python 是 graph_id），只写 url 不算
 *   2) 工具清单：8 → 13，五个异步工具的名字一字不差
 *   3) 中间件栈：异步中间件插在 patchToolCalls 之后
 *   4) 假 Agent Protocol 服务：start → check → update → cancel → list 全链路
 *   5) 未知 agentName / 未知 taskId 的错误形态
 *   6) 不写 url 会怎样：TS 没有 ASGI 进程内传输
 *   7) 动态子代理：eval 全局、task() 桥接、并发上限、失败传播、驼峰键
 *   8) 上下文体积与速度对照
 * 假服务起在 127.0.0.1 的随机端口，模型是桩，全程不发真实网络请求。
 *
 * 运行：npm run l12
 */
import { createDeepAgent, isAsyncSubAgent, type AsyncTask } from "deepagents";
import { createCodeInterpreterMiddleware } from "@langchain/quickjs";
import { AIMessage, ToolMessage, type BaseMessage } from "@langchain/core/messages";
import { BaseChatModel } from "@langchain/core/language_models/chat_models";
import { MemorySaver } from "@langchain/langgraph";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

const section = (n: number, t: string) => console.log(`\n====== ${n}) ${t} ======`);

/* ------------------------------------------------------------------ */
/* 桩：脚本化聊天模型 / 回声模型 / JSON 模型                              */
/* ------------------------------------------------------------------ */

type AnyAgent = {
	options: { middleware?: readonly unknown[] };
	invoke: (input: unknown, config?: unknown) => Promise<Record<string, unknown>>;
};

class ScriptModel extends BaseChatModel {
	script: AIMessage[];
	seen: BaseMessage[][] = [];
	boundTools: string[] = [];

	constructor(script: AIMessage[]) {
		super({});
		this.script = [...script];
	}

	_llmType(): string {
		return "script";
	}

	bindTools(tools: unknown[]): this {
		this.boundTools = (tools ?? []).map((t) => String((t as { name?: string }).name ?? "?"));
		return this;
	}

	async _generate(messages: BaseMessage[]) {
		this.seen.push([...messages]);
		const msg = this.script.shift() ?? new AIMessage("done");
		return { generations: [{ text: String(msg.content), message: msg }] };
	}
}

/** 把最后一条 human 消息原样带回，用来观察派发了什么。 */
class EchoModel extends BaseChatModel {
	seen: BaseMessage[][] = [];
	inflight = 0;
	peak = 0;
	static peakGlobal = 0;
	delayMs: number;

	constructor(delayMs = 0) {
		super({});
		this.delayMs = delayMs;
	}

	_llmType(): string {
		return "echo";
	}

	bindTools(): this {
		return this;
	}

	async _generate(messages: BaseMessage[]) {
		this.seen.push([...messages]);
		this.inflight += 1;
		EchoModel.peakGlobal = Math.max(EchoModel.peakGlobal, this.inflight);
		if (this.delayMs > 0) await new Promise((r) => setTimeout(r, this.delayMs));
		this.inflight -= 1;
		const last = [...messages].reverse().find((m) => m.getType() === "human");
		const text = last ? textOf(last) : "(无输入)";
		return { generations: [{ text, message: new AIMessage(`worker 完成: ${text}`) }] };
	}
}

/** 固定返回一段 JSON 的模型，用来验 responseSchema。 */
class JsonModel extends BaseChatModel {
	payload: string;
	constructor(payload: string) {
		super({});
		this.payload = payload;
	}
	_llmType(): string {
		return "json";
	}
	bindTools(): this {
		return this;
	}
	async _generate() {
		return { generations: [{ text: this.payload, message: new AIMessage(this.payload) }] };
	}
}

/** 必定抛错的模型，用来验失败传播。 */
class BoomModel extends BaseChatModel {
	constructor() {
		super({});
	}

	_llmType(): string {
		return "boom";
	}
	bindTools(): this {
		return this;
	}
	async _generate(): Promise<never> {
		throw new Error("worker 内部炸了");
	}
}

/* ------------------------------------------------------------------ */
/* 辅助                                                                */
/* ------------------------------------------------------------------ */

const textOf = (m: BaseMessage): string => {
	const c = m.content as unknown;
	if (Array.isArray(c)) {
		return c
			.map((b) => {
				const blk = b as { type?: string; text?: string };
				return blk.type === "text" ? (blk.text ?? "") : `[${blk.type}]`;
			})
			.join("");
	}
	return String(c);
};

const stackOf = (a: AnyAgent): string[] =>
	((a.options.middleware ?? []) as Array<{ name?: string }>).map((m) => m.name ?? "<unnamed>");

const toolsOf = (a: AnyAgent): string[] => {
	const out: string[] = [];
	for (const mw of (a.options.middleware ?? []) as Array<{ tools?: unknown }>) {
		const t = mw.tools;
		if (!t) continue;
		const arr = typeof t === "function" ? (t as () => unknown[])() : (t as unknown[]);
		for (const x of arr ?? []) {
			const n = (x as { name?: string }).name;
			if (n) out.push(n);
		}
	}
	return [...new Set(out)].sort();
};

const lastTool = (out: Record<string, unknown>, name?: string): ToolMessage | undefined => {
	const msgs = (out.messages ?? []) as BaseMessage[];
	const tools = msgs.filter((m) => m.getType() === "tool") as ToolMessage[];
	if (!name) return tools.pop();
	const named = tools.filter((m) => (m as unknown as { name?: string }).name === name);
	return named.length > 0 ? named.pop() : tools.pop();
};

/** 抓会话里所有 tool 消息的内容，按顺序。 */
const toolTexts = (out: Record<string, unknown>): string[] =>
	((out.messages ?? []) as BaseMessage[])
		.filter((m) => m.getType() === "tool")
		.map((m) => textOf(m));

/* ------------------------------------------------------------------ */
/* 假 Agent Protocol 服务                                              */
/* ------------------------------------------------------------------ */

type RunRecord = { runId: string; threadId: string; graphId: string; status: string };

const FAKE = {
	threadSeq: 0,
	runs: new Map<string, RunRecord>(),
	stateByThread: new Map<string, unknown>(),
	cancelCalls: [] as string[],
	runCreateCalls: [] as Array<{ threadId: string; graphId: string; multitask: string }>,
	graphIds: new Set<string>(),
};

const readBody = (req: IncomingMessage): Promise<string> =>
	new Promise((resolve) => {
		let buf = "";
		req.on("data", (c) => (buf += String(c)));
		req.on("end", () => resolve(buf));
	});

const json = (res: ServerResponse, code: number, payload: unknown) => {
	const body = JSON.stringify(payload);
	res.writeHead(code, { "content-type": "application/json" });
	res.end(body);
};

const startFakeServer = async (): Promise<{ url: string; close: () => Promise<void> }> => {
	const server = createServer(async (req, res) => {
		const url = new URL(req.url ?? "/", "http://127.0.0.1");
		const parts = url.pathname.split("/").filter(Boolean);
		const method = req.method ?? "GET";
		const body = await readBody(req);
		const payload = body ? (JSON.parse(body) as Record<string, unknown>) : {};

		// POST /threads
		if (method === "POST" && parts.length === 1 && parts[0] === "threads") {
			FAKE.threadSeq += 1;
			const threadId = `t-${FAKE.threadSeq}`;
			return json(res, 200, { thread_id: threadId, created_at: new Date().toISOString(), metadata: {} });
		}

		// POST /threads/{tid}/runs
		if (method === "POST" && parts.length === 3 && parts[0] === "threads" && parts[2] === "runs") {
			const threadId = parts[1];
			const graphId = String(payload.assistant_id ?? "?");
			FAKE.graphIds.add(graphId);
			FAKE.runCreateCalls.push({
				threadId,
				graphId,
				multitask: String(payload.multitask_strategy ?? "(默认)"),
			});
			const runId = `r-${FAKE.runs.size + 1}`;
			FAKE.runs.set(`${threadId}/${runId}`, { runId, threadId, graphId, status: "pending" });
			// 记住输入，check 成功时当结果回吐
			const input = payload.input as { messages?: Array<{ content?: string }> } | undefined;
			FAKE.stateByThread.set(threadId, {
				messages: [
					{
						type: "ai",
						content: `远程图 ${graphId} 完成，收到任务：${input?.messages?.[0]?.content ?? "(空)"}`,
					},
				],
			});
			return json(res, 200, {
				run_id: runId,
				thread_id: threadId,
				assistant_id: graphId,
				status: "pending",
				created_at: new Date().toISOString(),
			});
		}

		// GET /threads/{tid}/runs/{rid}
		if (method === "GET" && parts.length === 4 && parts[0] === "threads" && parts[2] === "runs") {
			const key = `${parts[1]}/${parts[3]}`;
			const run = FAKE.runs.get(key);
			if (!run) return json(res, 404, { detail: "run not found" });
			return json(res, 200, {
				run_id: run.runId,
				thread_id: run.threadId,
				assistant_id: run.graphId,
				status: run.status,
				created_at: new Date().toISOString(),
			});
		}

		// POST /threads/{tid}/runs/{rid}/cancel
		if (method === "POST" && parts.length === 5 && parts[0] === "threads" && parts[4] === "cancel") {
			const key = `${parts[1]}/${parts[3]}`;
			FAKE.cancelCalls.push(key);
			const run = FAKE.runs.get(key);
			if (run) run.status = "cancelled";
			res.writeHead(204);
			return res.end();
		}

		// GET /threads/{tid}/state
		if (method === "GET" && parts.length === 3 && parts[0] === "threads" && parts[2] === "state") {
			return json(res, 200, { values: FAKE.stateByThread.get(parts[1]) ?? {}, next: [], metadata: {} });
		}

		return json(res, 404, { detail: `未实现的路由: ${method} ${url.pathname}` });
	});

	await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
	const port = (server.address() as AddressInfo).port;
	return {
		url: `http://127.0.0.1:${port}`,
		close: () =>
			new Promise<void>((resolve) => {
				server.close(() => resolve());
			}),
	};
};

/* ------------------------------------------------------------------ */
/* 主流程                                                              */
/* ------------------------------------------------------------------ */

const AI_ONLY = [new AIMessage("收到。")];

const main = async (): Promise<void> => {
	const ver = (await import("deepagents/package.json", { with: { type: "json" } })).default.version;
	const qjsVer = (await import("@langchain/quickjs/package.json", { with: { type: "json" } })).default.version;
	console.log(`deepagents: ${ver} ｜ @langchain/quickjs: ${qjsVer}`);

	/* ---------------------------------------------------------------- */
	section(1, "graphId 才是分流开关，只写 url 不算");
	{
		const cases: Array<[string, Record<string, unknown>]> = [
			["{name, graphId}", { name: "a", description: "x", graphId: "g" }],
			["{name, url}", { name: "b", description: "x", url: "http://x" }],
			["{name}", { name: "c", description: "x" }],
			["{name, runnable}", { name: "d", description: "x", runnable: {} }],
		];
		for (const [label, spec] of cases) {
			console.log(`  ${label.padEnd(22)} isAsyncSubAgent = ${isAsyncSubAgent(spec as never)}`);
		}

		// graphId 为空串呢？
		console.log(`  {"graphId":""}          isAsyncSubAgent = ${isAsyncSubAgent({ name: "e", description: "x", graphId: "" } as never)}`);
		console.log(`  （判据是 "graphId" in spec，不做非空校验）`);

		// 空数组 / 重复名
		const tryCreate = (label: string, specs: unknown[]) => {
			try {
				createDeepAgent({ model: "openai:gpt-4o-mini", tools: [], subagents: specs } as never);
				console.log(`  ${label.padEnd(22)} 创建成功`);
			} catch (e) {
				console.log(`  ${label.padEnd(22)} 抛错: ${(e as Error).message.slice(0, 90)}`);
			}
		};
		tryCreate("subagents=[]", []);
		tryCreate("重复 graphId 名", [
			{ name: "dup", description: "1", graphId: "g1" },
			{ name: "dup", description: "2", graphId: "g2" },
		]);
	}

	/* ---------------------------------------------------------------- */
	section(2, "工具清单：8 → 13，五个异步工具名一字不差");
	{
		const base = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] }) as unknown as AnyAgent;
		const syncOnly = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			subagents: [{ name: "editor", description: "改本地代码" }],
		} as never) as unknown as AnyAgent;
		const withAsync = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			subagents: [{ name: "researcher", description: "远程研究", graphId: "research_agent", url: "http://127.0.0.1:1" }],
		} as never) as unknown as AnyAgent;

		const tb = toolsOf(base);
		const ts = toolsOf(syncOnly);
		const ta = toolsOf(withAsync);
		console.log(`  无子代理      ${tb.length} 个: ${tb.join(", ")}`);
		console.log(`  同步子代理    ${ts.length} 个，比基线多: ${ts.filter((x) => !tb.includes(x)).join(", ") || "(无)"}`);
		console.log(`  异步子代理    ${ta.length} 个，比基线多: ${ta.filter((x) => !tb.includes(x)).join(", ")}`);
		console.log(`  异步规格里有 task 工具吗: ${ta.includes("task")}（同步子代理在，task 就在）`);

		// 混装
		const mixed = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			subagents: [
				{ name: "editor", description: "改本地代码" },
				{ name: "researcher", description: "远程研究", graphId: "research_agent", url: "http://127.0.0.1:1" },
			],
		} as never) as unknown as AnyAgent;
		const tm = toolsOf(mixed);
		console.log(`  混装          ${tm.length} 个（task + 五个异步工具并存）`);
		console.log(`    含 task: ${tm.includes("task")}  含 start_async_task: ${tm.includes("start_async_task")}`);
	}

	/* ---------------------------------------------------------------- */
	section(3, "中间件栈：异步中间件插在 patchToolCalls 之后");
	{
		const base = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] }) as unknown as AnyAgent;
		const withAsync = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			subagents: [{ name: "r", description: "远程", graphId: "g", url: "http://127.0.0.1:1" }],
		} as never) as unknown as AnyAgent;
		console.log(`  不配异步 ${stackOf(base).length} 条: ${stackOf(base).join(" → ")}`);
		console.log(`  配了异步 ${stackOf(withAsync).length} 条: ${stackOf(withAsync).join(" → ")}`);
		const added = stackOf(withAsync).filter((x) => !stackOf(base).includes(x));
		console.log(`  新增: ${added.join(", ")}`);
	}

	/* ---------------------------------------------------------------- */
	section(4, "假 Agent Protocol 服务：start → check → update → cancel → list");
	const fake = await startFakeServer();
	try {
		const saver = new MemorySaver();
		const mk = (script: AIMessage[]): AnyAgent =>
			createDeepAgent({
				model: new ScriptModel(script) as never,
				tools: [],
				checkpointer: saver,
				subagents: [
					{ name: "researcher", description: "远程深度调研", graphId: "research_agent", url: fake.url },
					{ name: "writer", description: "远程写作", graphId: "writer_agent", url: fake.url },
				],
			} as never) as unknown as AnyAgent;

		const call = (name: string, args: Record<string, unknown>, id: string) =>
			new AIMessage({ content: "", tool_calls: [{ name, args, id }] });

		// 全部走同一个 thread，asyncTasks 靠 checkpointer 跨 invoke 存活
		const TH = { configurable: { thread_id: "th-main" } };
		const step = async (label: string, msg: AIMessage, toolName: string) => {
			const out = await mk([msg, ...AI_ONLY]).invoke({ messages: [{ role: "user", content: label }] }, TH);
			return { out, text: textOf(lastTool(out, toolName) as BaseMessage) };
		};

		// 4-A start
		const s1 = await step("提交竞品 A 调研", call("start_async_task", { description: "查竞品 A", agentName: "researcher" }, "s1"), "start_async_task");
		console.log(`  4-A start          tool = ${JSON.stringify(s1.text)}`);
		const taskId = /taskId: (\S+)/.exec(s1.text)?.[1] ?? "";
		const tasks1 = (s1.out.asyncTasks ?? {}) as Record<string, AsyncTask>;
		const tk = tasks1[taskId];
		console.log(`      taskId = threadId? ${tk ? tk.taskId === tk.threadId : "取不到"}｜状态=${tk?.status}｜agent=${tk?.agentName}`);
		console.log(`      假服务收到的 run 请求: graphId=${FAKE.runCreateCalls.at(-1)?.graphId} multitask=${FAKE.runCreateCalls.at(-1)?.multitask}`);

		// 4-B check（run 还停在 pending）
		const s2 = await step("查进度", call("check_async_task", { taskId }, "s2"), "check_async_task");
		console.log(`  4-B check(pending) tool = ${s2.text}`);

		// 4-C check（成功后能拿到结果）
		for (const r of FAKE.runs.values()) r.status = "success";
		const s3 = await step("再查一次", call("check_async_task", { taskId }, "s3"), "check_async_task");
		console.log(`  4-C check(success) tool = ${s3.text}`);
		console.log(`      状态是否回写进 asyncTasks: ${((s3.out.asyncTasks ?? {}) as Record<string, AsyncTask>)[taskId]?.status}`);

		// 4-D update：同 thread 开新 run，taskId 不变、runId 变
		const beforeRunId = ((s3.out.asyncTasks ?? {}) as Record<string, AsyncTask>)[taskId]?.runId;
		const s4 = await step("改需求", call("update_async_task", { taskId, message: "改成查竞品 A 的定价" }, "s4"), "update_async_task");
		const afterTask = ((s4.out.asyncTasks ?? {}) as Record<string, AsyncTask>)[taskId];
		console.log(`  4-D update         tool = ${s4.text}`);
		console.log(`      taskId 是否不变: ${taskId === afterTask?.taskId}｜runId 是否变了: ${beforeRunId !== afterTask?.runId}（${beforeRunId} → ${afterTask?.runId}）`);
		console.log(`      假服务收到的 multitask 策略 = ${FAKE.runCreateCalls.at(-1)?.multitask}`);

		// 4-E list
		const s5 = await step("列一下", call("list_async_tasks", {}, "s5"), "list_async_tasks");
		console.log(`  4-E list           tool = ${s5.text.replace(/\n/g, " / ")}`);

		// 4-F list 带状态筛选
		const s6 = await step("只看 running 的", call("list_async_tasks", { statusFilter: "running" }, "s6"), "list_async_tasks");
		console.log(`  4-F list(running)  tool = ${s6.text.replace(/\n/g, " / ")}`);
		console.log(`      按"缓存状态"筛，不是按实时状态筛`);

		// 4-G cancel
		const s7 = await step("不查了", call("cancel_async_task", { taskId }, "s7"), "cancel_async_task");
		console.log(`  4-G cancel         tool = ${s7.text}｜远程 cancel 调用次数 = ${FAKE.cancelCalls.length}`);

		// 4-H 未知 agentName / 未知 taskId
		const s8 = await step("派个不存在的", call("start_async_task", { description: "x", agentName: "nobody" }, "s8"), "start_async_task");
		console.log(`  4-H 未知 agentName  tool = ${s8.text}`);
		const s9 = await step("查个不存在的", call("check_async_task", { taskId: "t-999" }, "s9"), "check_async_task");
		console.log(`  4-I 未知 taskId     tool = ${s9.text}`);
		console.log(`      → 两种都是普通字符串返回，流程不中断、不抛错`);
	} finally {
		await fake.close();
	}

	/* ---------------------------------------------------------------- */
	section(5, "不写 url：TS 没有 ASGI 进程内传输");
	{
		const agent = createDeepAgent({
			model: new ScriptModel([
				new AIMessage({
					content: "",
					tool_calls: [
						{ name: "start_async_task", args: { description: "x", agentName: "r" }, id: "z1" },
					],
				}),
				...AI_ONLY,
			]) as never,
			tools: [],
			checkpointer: new MemorySaver(),
			subagents: [{ name: "r", description: "无 url", graphId: "g_only" }],
		} as never) as unknown as AnyAgent;
		const out = await agent.invoke({ messages: [{ role: "user", content: "开始" }] }, { configurable: { thread_id: "th-u" } });
		const tx = textOf(lastTool(out, "start_async_task") as BaseMessage);
		console.log(`  tool = ${tx.slice(0, 160)}`);
		console.log(`  有没有 "requires async invocation" 提示: ${/requires async invocation/i.test(tx)}`);
		console.log(`  → SDK 在 url 缺失时回落到 http://localhost:8123，报的是连接失败，不是"必须用 ainvoke"`);
	}

	/* ---------------------------------------------------------------- */
	section(6, "动态子代理：eval 全局、task() 桥接、并发、失败传播");
	{
		const mkDyn = (script: AIMessage[], opts: { concurrency?: number; child?: BaseChatModel } = {}) =>
			createDeepAgent({
				model: new ScriptModel(script) as never,
				tools: [],
				checkpointer: new MemorySaver(),
				subagents: [
					{ name: "worker", description: "干活的小工", systemPrompt: "干活。", model: (opts.child ?? new EchoModel()) as never },
				],
				middleware: [
					createCodeInterpreterMiddleware(
						opts.concurrency ? { maxSubagentConcurrency: opts.concurrency } : {},
					) as never,
				],
			} as never) as unknown as AnyAgent;

		const evalCall = (code: string, id = "e1") =>
			new AIMessage({ content: "", tool_calls: [{ name: "eval", args: { code }, id }] });

		const runCode = async (label: string, code: string, opts: { concurrency?: number; child?: BaseChatModel } = {}) => {
			const agent = mkDyn([evalCall(code), ...AI_ONLY], opts);
			const out = await agent.invoke({ messages: [{ role: "user", content: "跑" }] }, { configurable: { thread_id: `th-${label}` } });
			const res = textOf(lastTool(out, "eval") as BaseMessage);
			console.log(`  ${label}:`);
			res.split("\n").forEach((line) => console.log(`    ${line}`));
			return { out, res };
		};

		// 6-A 全局对象与边界
		await runCode(
			"6-A 解释器全局 + 边界",
			`console.log(Object.keys(globalThis).sort().join(","));
[typeof require, typeof process, typeof fetch, typeof Deno].join(" | ")`,
		);

		// 6-B task() 派发
		const { out: outB } = await runCode(
			"6-B task() 并发派三个",
			`const rs = await Promise.all(["A","B","C"].map(x => task({ description: \`处理 \${x}\`, subagentType: "worker" })));
rs.join(" | ")`,
		);
		console.log(`    主上下文消息数: ${(outB.messages as BaseMessage[]).length}`);
		console.log(`    主上下文 tool 结果数: ${toolTexts(outB).length}`);

		// 6-C 并发上限
		EchoModel.peakGlobal = 0;
		const slow = new EchoModel(60);
		const t0 = Date.now();
		await runCode(
			"6-C 并发上限（默认 vs 2，每个子代理 60ms）",
			`const rs = await Promise.all(Array.from({length: 8}, (_, i) => task({ description: \`项\${i}\`, subagentType: "worker" })));
rs.length`,
			{ child: slow },
		);
		console.log(`    默认并发峰值 = ${EchoModel.peakGlobal}  耗时 ${((Date.now() - t0) / 1000).toFixed(2)}s`);

		EchoModel.peakGlobal = 0;
		const slow2 = new EchoModel(60);
		const t1 = Date.now();
		const agent2 = mkDyn(
			[evalCall(`const rs = await Promise.all(Array.from({length: 8}, (_, i) => task({ description: \`项\${i}\`, subagentType: "worker" }))); rs.length`), ...AI_ONLY],
			{ concurrency: 2, child: slow2 },
		);
		await agent2.invoke({ messages: [{ role: "user", content: "跑" }] }, { configurable: { thread_id: "th-c2" } });
		console.log(`    maxSubagentConcurrency=2 峰值 = ${EchoModel.peakGlobal}  耗时 ${((Date.now() - t1) / 1000).toFixed(2)}s`);

		// 6-D 失败传播
		await runCode(
			"6-D 子代理抛异常",
			`try {
  const r = await task({ description: "会炸的任务", subagentType: "worker" });
  console.log("没抛，返回值是: " + JSON.stringify(r).slice(0, 120));
  return "ok";
} catch (e) {
  console.log("抛到 JS 侧了: " + e.message.slice(0, 120));
  return "caught";
}`,
			{ child: new BoomModel() },
		);

		// 6-E 键名宽容度
		await runCode(
			"6-E 键名：驼峰 / 下划线 / 未知键",
			`const a = await task({ description: "snake 写法", subagent_type: "worker" });
console.log("subagent_type 可用: " + a);
try { await task({ description: "x", subagentType: "worker", bogus: 1 }); } catch (e) { console.log("未知键: " + e.message.slice(0, 90)); }
"done"`,
		);

		// 6-F responseSchema
		const jsonChild = new JsonModel('{"severity":"high","issues":["SQL 注入","硬编码密钥"]}');
		await runCode(
			"6-F responseSchema 返回结构化对象",
			`const r = await task({ description: "审 auth.ts", subagentType: "worker", responseSchema: { type: "object", properties: { severity: { type: "string" }, issues: { type: "array", items: { type: "string" } } } } });
console.log("typeof = " + typeof r + "  severity = " + r.severity + "  issues = " + r.issues.length);
r.severity`,
			{ child: jsonChild },
		);
	}

	/* ---------------------------------------------------------------- */
	section(7, "上下文体积与速度：并行 task vs 动态 eval");
	{
		const bigReport = "报告".repeat(300); // 600 字，对齐 Python 探针
		class FixedModel extends BaseChatModel {
			body: string;
			constructor(body: string) {
				super({});
				this.body = body;
			}
			_llmType(): string {
				return "fixed";
			}
			bindTools(): this {
				return this;
			}
			async _generate() {
				return { generations: [{ text: this.body, message: new AIMessage(this.body) }] };
			}
		}

		const N = 8;
		// 7-A 并行 task tool_calls
		const parallelCalls = Array.from({ length: N }, (_, i) => ({
			name: "task",
			args: { description: `任务 ${i}`, subagent_type: "worker" },
			id: `p${i}`,
		}));
		const aPar = createDeepAgent({
			model: new ScriptModel([new AIMessage({ content: "", tool_calls: parallelCalls }), new AIMessage("汇总完成")]) as never,
			tools: [],
			checkpointer: new MemorySaver(),
			subagents: [{ name: "worker", description: "干活", systemPrompt: "干活。", model: new FixedModel(bigReport) as never }],
		} as never) as unknown as AnyAgent;
		const tPar0 = Date.now();
		const oPar = await aPar.invoke({ messages: [{ role: "user", content: "查 8 个" }] }, { configurable: { thread_id: "th-par" } });
		const parMs = Date.now() - tPar0;
		const parMsgs = oPar.messages as BaseMessage[];
		const parChars = parMsgs.reduce((s, m) => s + textOf(m).length, 0);

		// 7-B 动态 eval
		const dynCode = `const items = Array.from({length: ${N}}, (_, i) => i);
const rs = await Promise.all(items.map(i => task({ description: \`任务 \${i}\`, subagentType: "worker" })));
rs.length`;
		const aDyn = createDeepAgent({
			model: new ScriptModel([
				new AIMessage({ content: "", tool_calls: [{ name: "eval", args: { code: dynCode }, id: "d1" }] }),
				new AIMessage("汇总完成"),
			]) as never,
			tools: [],
			checkpointer: new MemorySaver(),
			subagents: [{ name: "worker", description: "干活", systemPrompt: "干活。", model: new FixedModel(bigReport) as never }],
			middleware: [createCodeInterpreterMiddleware() as never],
		} as never) as unknown as AnyAgent;
		const tDyn0 = Date.now();
		const oDyn = await aDyn.invoke({ messages: [{ role: "user", content: "查 8 个" }] }, { configurable: { thread_id: "th-dyn" } });
		const dynMs = Date.now() - tDyn0;
		const dynMsgs = oDyn.messages as BaseMessage[];
		const dynChars = dynMsgs.reduce((s, m) => s + textOf(m).length, 0);

		console.log(`  并行 task × ${N}：消息 ${parMsgs.length} 条，tool 结果 ${toolTexts(oPar).length} 条，总字符 ${parChars}，耗时 ${parMs}`);
		console.log(`  动态 eval × ${N}：消息 ${dynMsgs.length} 条，tool 结果 ${toolTexts(oDyn).length} 条，总字符 ${dynChars}，耗时 ${dynMs}`);
		console.log(`  字符比 ${(parChars / Math.max(dynChars, 1)).toFixed(0)}:1  耗时比 ${(dynMs / Math.max(parMs, 1)).toFixed(2)}x`);

		// 7-C 小规模速度：重复 3 次取中位数，子代理带 20ms 固定延迟（模拟真实推理）
		const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)];
		const bench = async (n: number) => {
			const parRuns: number[] = [];
			const dynRuns: number[] = [];
			for (let rep = 0; rep < 3; rep += 1) {
				const calls = Array.from({ length: n }, (_, i) => ({
					name: "task",
					args: { description: `t${i}`, subagent_type: "worker" },
					id: `q${rep}-${i}`,
				}));
				const a = createDeepAgent({
					model: new ScriptModel([new AIMessage({ content: "", tool_calls: calls }), new AIMessage("ok")]) as never,
					tools: [],
					checkpointer: new MemorySaver(),
					subagents: [{ name: "worker", description: "干活", systemPrompt: "干活。", model: new EchoModel(20) as never }],
				} as never) as unknown as AnyAgent;
				const s = Date.now();
				await a.invoke({ messages: [{ role: "user", content: "go" }] }, { configurable: { thread_id: `th-b${n}-${rep}` } });
				parRuns.push(Date.now() - s);

				const code = `const rs = await Promise.all(Array.from({length: ${n}}, (_, i) => task({ description: \`t\${i}\`, subagentType: "worker" }))); rs.length`;
				const b = createDeepAgent({
					model: new ScriptModel([
						new AIMessage({ content: "", tool_calls: [{ name: "eval", args: { code }, id: `e${rep}` }] }),
						new AIMessage("ok"),
					]) as never,
					tools: [],
					checkpointer: new MemorySaver(),
					subagents: [{ name: "worker", description: "干活", systemPrompt: "干活。", model: new EchoModel(20) as never }],
					middleware: [createCodeInterpreterMiddleware() as never],
				} as never) as unknown as AnyAgent;
				const s2 = Date.now();
				await b.invoke({ messages: [{ role: "user", content: "go" }] }, { configurable: { thread_id: `th-d${n}-${rep}` } });
				dynRuns.push(Date.now() - s2);
			}
			const par = median(parRuns);
			const dyn = median(dynRuns);
			console.log(
				`  N=${String(n).padStart(2)}  并行 ${(par / 1000).toFixed(3)}s  vs  动态 ${(dyn / 1000).toFixed(3)}s  → 动态${dyn >= par ? "慢" : "快"} ${(Math.max(dyn, par) / Math.min(dyn, par)).toFixed(2)}x（3 次中位数）`,
			);
		};
		for (const n of [4, 12, 30]) await bench(n);
	}

	console.log("\n全部探针跑完。");
};

main().catch((e) => {
	console.error("探针失败:", e);
	process.exit(1);
});
