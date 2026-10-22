/**
 * 课 10 · 任务规划与子代理 —— TypeScript 侧实测探针
 *
 * 对齐 Python 侧探针 1-6：
 *   1) write_todos 的 opt-in（默认 9 个工具，加 todoListMiddleware 后 10 个）
 *   2) isolated vs fork 的消息构成
 *   3) 只回最后一条有文本的 AIMessage
 *   4) 递归拒绝、非法 mode、handoff 别名、fork + skills
 *   5) 关掉 task：TS 没有 Python 的 profile 那条路
 *   6) 子代理工具清单：tools 只换自定义部分，文件工具独立
 * 全程离线构造，模型是桩，不发网络请求。
 *
 * 运行：npm run l10
 */
import { createDeepAgent, createFilesystemMiddleware, createSubAgentMiddleware } from "deepagents";
import { todoListMiddleware } from "langchain";
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { AIMessage, type BaseMessage } from "@langchain/core/messages";
import { BaseChatModel } from "@langchain/core/language_models/chat_models";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const section = (n: number, t: string) => console.log(`\n====== ${n}) ${t} ======`);

/* ------------------------------------------------------------------ */
/* 桩：脚本化聊天模型                                                    */
/* ------------------------------------------------------------------ */

type AnyAgent = { options: { middleware?: readonly unknown[] } };

class ScriptModel extends BaseChatModel {
	script: AIMessage[];
	seen: BaseMessage[][] = [];
	boundTools: string[] = [];
	tag: string;

	constructor(script: AIMessage[], tag = "model") {
		super({});
		this.script = [...script];
		this.tag = tag;
	}

	_llmType(): string {
		return this.tag;
	}

	bindTools(tools: unknown[]): this {
		this.boundTools = (tools ?? []).map((t) => String((t as { name?: string }).name ?? "?"));
		return this;
	}

	async _generate(messages: BaseMessage[]) {
		this.seen.push(messages);
		const msg = this.script.shift() ?? new AIMessage("done");
		return { generations: [{ text: String(msg.content), message: msg }] };
	}
}

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

const taskToolOf = (a: AnyAgent) => {
	for (const mw of (a.options.middleware ?? []) as Array<{ tools?: unknown }>) {
		const t = mw.tools;
		if (!t) continue;
		const arr = typeof t === "function" ? (t as () => unknown[])() : (t as unknown[]);
		for (const x of arr ?? []) if ((x as { name?: string }).name === "task") return x as { description?: string };
	}
	return undefined;
};

/** 取一段消息的可读正文（TS 侧 content 常是 block 数组）。 */
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

/** 造一个只会派一次活的主代理模型。 */
const mainScript = (subagentType: string, args: Record<string, unknown> = {}) =>
	new ScriptModel([
		new AIMessage({
			content: "",
			tool_calls: [{ name: "task", args: { description: "去查资料", subagent_type: subagentType, ...args }, id: "t1" }],
		}),
		new AIMessage("收到报告。"),
	], "main");

const parentHistory = [
	{ role: "user" as const, content: "请帮我调研一下子代理机制" },
	{ role: "assistant" as const, content: "好的，我派个人去查。" },
	{ role: "user" as const, content: "顺便说下我叫小明，项目叫 Alpha" },
];

const main = async (): Promise<void> => {
	const ver = (await import("deepagents/package.json", { with: { type: "json" } })).default.version;
	console.log(`deepagents: ${ver}`);

	/* ---------------------------------------------------------------- */
	section(1, "write_todos 是 opt-in：默认 9 个工具，加回来 10 个");
	{
		const base = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] }) as unknown as AnyAgent;
		const withTodo = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			middleware: [todoListMiddleware()],
		}) as unknown as AnyAgent;

		const tb = toolsOf(base);
		const tt = toolsOf(withTodo);
		console.log(`  默认        ${tb.length} 个: ${tb.join(", ")}`);
		console.log(`  含 write_todos: ${tb.includes("write_todos")}`);
		console.log(`  加 todo 后  ${tt.length} 个，新增: ${tt.filter((x) => !tb.includes(x)).join(", ")}`);
		console.log(`  中间件来自: langchain 包的 todoListMiddleware()（deepagents 不导出）`);
	}

	/* ---------------------------------------------------------------- */
	section(2, "isolated vs fork：子代理到底收到几条消息");
	{
		const runOne = async (label: string, spec: Record<string, unknown>) => {
			const child = new ScriptModel([new AIMessage("报告")], "child");
			const agent = createDeepAgent({
				model: mainScript(String(spec.name)) as never,
				tools: [],
				subagents: [{ ...spec, model: child as never }],
			} as never);
			await (agent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: parentHistory });
			const seen = child.seen[0] ?? [];
			console.log(`  ${label.padEnd(28)} ${seen.length} 条`);
			seen.forEach((m, i) => {
				const t = textOf(m);
				console.log(`     ${i}. [${m.getType()}] len=${t.length} | ${JSON.stringify(t.slice(0, 62))}`);
			});
			return seen;
		};

		const iso = await runOne("isolated（默认）", { name: "researcher", description: "检索专家", systemPrompt: "你是检索专家。" });
		const hasSecret = iso.some((m) => /小明|Alpha/.test(textOf(m)));
		console.log(`     → 看得到父对话里的"小明 / Alpha": ${hasSecret}`);

		const fk = await runOne("fork", { name: "writer", description: "写报告", mode: "fork" });
		console.log(`     → 看得到"小明 / Alpha": ${fk.some((m) => /小明|Alpha/.test(textOf(m)))}`);

		const fkSys = await runOne("fork + 自定义 systemPrompt", {
			name: "writer2",
			description: "写报告",
			mode: "fork",
			systemPrompt: "你是写作专家。",
		});
		console.log(`     → 前缀注入那段长度: ${textOf(fkSys[fkSys.length - 1]).length} 字符`);
		console.log(`     → TS 侧不写 systemPrompt 时，fork 子代理一条 system 都不带（${fk.length} 条里没有 system）`);
	}

	/* ---------------------------------------------------------------- */
	section(3, "只回最后一条有文本的 AIMessage");
	{
		const child = new ScriptModel([
			new AIMessage({ content: "先查一下", tool_calls: [{ name: "ls", args: { path: "/" }, id: "c1" }] }),
			new AIMessage({ content: "再看看", tool_calls: [{ name: "ls", args: { path: "/" }, id: "c2" }] }),
			new AIMessage("最终报告：找到 3 条要点。"),
		], "child");
		const agent = createDeepAgent({
			model: mainScript("r") as never,
			tools: [],
			subagents: [{ name: "r", description: "报告提取", systemPrompt: "干活。", model: child as never }],
		} as never);
		const out = (await (agent as unknown as { invoke: (i: unknown) => Promise<{ messages: BaseMessage[] }> }).invoke({
			messages: [{ role: "user", content: "开始" }],
		})) as { messages: BaseMessage[] };
		const tm = out.messages.find((m) => m.getType() === "tool");
		console.log(`  子代理跑了 ${child.seen.length} 轮，中间两轮都在调工具`);
		console.log(`  父代理拿到的报告: ${JSON.stringify(textOf(tm as BaseMessage))}`);
		console.log(`  父对话总消息数: ${out.messages.length}（user + 空 ai + tool + ai）`);

		const child2 = new ScriptModel([
			new AIMessage({ content: "过程", tool_calls: [{ name: "ls", args: { path: "/" }, id: "c1" }] }),
			new AIMessage("最终报告甲"),
			new AIMessage(""),
		], "child2");
		const agent2 = createDeepAgent({
			model: mainScript("r2") as never,
			tools: [],
			subagents: [{ name: "r2", description: "尾部空消息", systemPrompt: "干活。", model: child2 as never }],
		} as never);
		const out2 = (await (agent2 as unknown as { invoke: (i: unknown) => Promise<{ messages: BaseMessage[] }> }).invoke({
			messages: [{ role: "user", content: "开始" }],
		})) as { messages: BaseMessage[] };
		const tm2 = out2.messages.find((m) => m.getType() === "tool");
		console.log(`  尾部再挂一条空 AIMessage → 父代理仍拿到: ${JSON.stringify(textOf(tm2 as BaseMessage))}`);
	}

	/* ---------------------------------------------------------------- */
	section(4, "递归拒绝、非法 mode、handoff 别名、fork + skills");
	{
		const child = new ScriptModel([
			new AIMessage({
				content: "",
				tool_calls: [{ name: "task", args: { description: "再派一层", subagent_type: "writer" }, id: "t2" }],
			}),
			new AIMessage("我不能再派了。"),
		], "fork-child");
		const agent = createDeepAgent({
			model: mainScript("writer") as never,
			tools: [],
			subagents: [{ name: "writer", description: "写报告", mode: "fork", model: child as never }],
		} as never);
		await (agent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: parentHistory });
		const round2 = child.seen[1] ?? [];
		const refuseMsg = round2.find((m) => m.getType() === "tool");
		console.log("  A) fork 子代理再派 task →", JSON.stringify(textOf(refuseMsg as BaseMessage)));
		console.log(`     子代理工具里有 task 吗: ${child.boundTools.includes("task")}`);

		const isoChild = new ScriptModel([new AIMessage("报告")], "iso-child");
		const isoAgent = createDeepAgent({
			model: mainScript("solo") as never,
			tools: [],
			subagents: [{ name: "solo", description: "单干", systemPrompt: "自己干。", model: isoChild as never }],
		} as never);
		await (isoAgent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: parentHistory });
		console.log(`  B) isolated 子代理工具: ${isoChild.boundTools.join(", ")}`);
		console.log(`     含 task: ${isoChild.boundTools.includes("task")}`);

		for (const [label, mode] of [["bogus", "bogus"], ["handoff（旧别名）", "handoff"]] as const) {
			try {
				createDeepAgent({
					model: "openai:gpt-4o-mini",
					tools: [],
					subagents: [{ name: "a", description: "x", mode: mode as never }],
				} as never);
				console.log(`  C) mode=${label} → 通过`);
			} catch (e) {
				console.log(`  C) mode=${label} → ${(e as Error).message.split("\n")[0]}`);
			}
		}

		try {
			createDeepAgent({
				model: "openai:gpt-4o-mini",
				tools: [],
				subagents: [{ name: "fk", description: "x", mode: "fork", skills: ["/skills/"] }],
			} as never);
			console.log("  D) fork + skills → 通过（不应该）");
		} catch (e) {
			console.log(`  D) fork + skills → ${(e as Error).message.split("\n")[0]}`);
		}

		const badMain = mainScript("nobody");
		const badAgent = createDeepAgent({
			model: badMain as never,
			tools: [],
			subagents: [
				{ name: "r", description: "x", systemPrompt: "x", model: new ScriptModel([new AIMessage("ok")], "c") as never },
			],
		} as never);
		try {
			await (badAgent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: [{ role: "user", content: "开始" }] });
			console.log("  E) 未知 subagent_type → 未抛错（不应该）");
		} catch (e) {
			console.log(`  E) 未知 subagent_type → 抛错: ${(e as Error).message.split("\n")[0]}`);
		}
	}

	/* ---------------------------------------------------------------- */
	section(5, "关掉 task：TS 没有 Python 的 profile 那条路");
	{
		for (const [label, opts] of [
			["默认", {}],
			["subagents: []", { subagents: [] }],
			["generalPurposeAgent: false（不在 createDeepAgent 参数里）", { generalPurposeAgent: false }],
			["两者都给", { subagents: [], generalPurposeAgent: false }],
		] as Array<[string, Record<string, unknown>]>) {
			const a = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [], ...opts } as never) as unknown as AnyAgent;
			const ts = toolsOf(a);
			console.log(`  ${label.padEnd(52)} 工具 ${ts.length} 个，含 task: ${ts.includes("task")}`);
		}

		const hacked = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			middleware: [{ name: "subAgentMiddleware", tools: [] } as never],
		} as never) as unknown as AnyAgent;
		console.log(`  用裸对象顶掉 subAgentMiddleware                         工具 ${toolsOf(hacked).length} 个，含 task: ${toolsOf(hacked).includes("task")}`);

		const custom = createDeepAgent({
			model: "openai:gpt-4o-mini",
			tools: [],
			middleware: [
				createSubAgentMiddleware({
					defaultModel: "openai:gpt-4o-mini",
					subagents: [],
					generalPurposeAgent: false,
				}) as never,
			],
		} as never) as unknown as AnyAgent;
		const ct = toolsOf(custom);
		console.log(`  createSubAgentMiddleware(GP=false, subagents=[])          工具 ${ct.length} 个，含 task: ${ct.includes("task")}`);
		const desc = String(taskToolOf(custom)?.description ?? "");
		const availBlock = desc.split("Available agent types and the tools they have access to:")[1]?.split("Specify subagent_type")[0] ?? "";
		const availLines = availBlock.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- "));
		console.log(`    task 描述总长 ${desc.length} 字符；"Available agent types" 下的条目: ${availLines.length} 条`);
		console.log(`    → 关掉 GP 后 task 工具还在，只是那一栏是空的（模型仍可能去调）`);

		const mm = mainScript("general-purpose");
		const strictAgent = createDeepAgent({
			model: mm as never,
			tools: [],
			middleware: [
				createSubAgentMiddleware({
					defaultModel: mm as never,
					subagents: [],
					generalPurposeAgent: false,
				}) as never,
			],
		} as never);
		try {
			await (strictAgent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: [{ role: "user", content: "开始" }] });
			console.log("    调 task → 未抛错（不应该）");
		} catch (e) {
			console.log(`    调 task → 抛错: ${(e as Error).message.split("\n")[0]}`);
		}
	}

	/* ---------------------------------------------------------------- */
	section(6, "子代理工具清单：tools 只换自定义部分，文件工具独立");
	{
		const queryDb = tool(async () => "3 rows", {
			name: "query_db",
			description: "只读查询",
			schema: z.object({ sql: z.string() }),
		});
		const sendEmail = tool(async () => "sent", {
			name: "send_email",
			description: "发邮件",
			schema: z.object({ to: z.string() }),
		});

		const spawn = async (label: string, spec: Record<string, unknown>, parentTools: unknown[] = []) => {
			const child = new ScriptModel([new AIMessage("报告")], "child");
			const agent = createDeepAgent({
				model: mainScript(String(spec.name)) as never,
				tools: parentTools as never,
				subagents: [{ ...spec, model: child as never }],
			} as never);
			await (agent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: [{ role: "user", content: "开始" }] });
			console.log(`  ${label}`);
			console.log(`    子代理工具(${child.boundTools.length}): ${child.boundTools.join(", ")}`);
			return child;
		};

		await spawn("A) tools=[query_db]，父有 query_db + send_email", { name: "dba", description: "库专家", systemPrompt: "只查。", tools: [queryDb] }, [queryDb, sendEmail]);
		console.log(`    → send_email 没进来（自定义部分被替换），但 7 个文件工具仍在`);
		await spawn("B) 不传 tools，父有 query_db + send_email", { name: "dba2", description: "库专家", systemPrompt: "只查。" }, [queryDb, sendEmail]);
		console.log(`    → 不传 tools 时继承父代理全部工具`);

		const child = new ScriptModel([new AIMessage("报告")], "restricted");
		const restricted = createDeepAgent({
			model: mainScript("ro") as never,
			tools: [],
			subagents: [{
				name: "ro",
				description: "只读",
				systemPrompt: "只读。",
				tools: [queryDb],
				middleware: [createFilesystemMiddleware({ tools: ["read_file", "ls"] }) as never],
				model: child as never,
			}],
		} as never);
		await (restricted as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: [{ role: "user", content: "开始" }] });
		console.log(`  C) tools=[query_db] + FilesystemMiddleware(tools=[read_file, ls])`);
		console.log(`    子代理工具(${child.boundTools.length}): ${child.boundTools.join(", ")}`);

		const plainChild = new ScriptModel([new AIMessage("报告")], "plain");
		const plainAgent = createDeepAgent({
			model: mainScript("plain") as never,
			tools: [sendEmail] as never,
			subagents: [{ name: "plain", description: "什么都不配", systemPrompt: "干活。", model: plainChild as never }],
		} as never);
		await (plainAgent as unknown as { invoke: (i: unknown) => Promise<unknown> }).invoke({ messages: [{ role: "user", content: "开始" }] });
		const base = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] }) as unknown as AnyAgent;
		console.log(`  D) 主代理默认 ${toolsOf(base).length} 个（含 execute）`);
		console.log(`     子代理默认 ${plainChild.boundTools.length} 个: ${plainChild.boundTools.join(", ")}`);
		console.log(`     → 子代理默认文件工具里没有 execute，也不带 task（isolated）`);
	}

	const defaultBase = createDeepAgent({ model: "openai:gpt-4o-mini", tools: [] }) as unknown as AnyAgent;
	console.log("\n====== 结论 ======");
	console.log("1. write_todos 两侧都是 opt-in；TS 从 langchain 包取 todoListMiddleware()");
	console.log("2. TS 默认工具 9 个（比 Python 多 execute），加 todo 后 10 个");
	console.log("3. fork 不写 systemPrompt 时 TS 一条 system 都不带；Python 带一条空 system");
	console.log("4. TS 关不掉 task 工具，只能用 createSubAgentMiddleware 把可用类型清空");
	console.log("5. 未知 subagent_type：Python 回 error 字符串，TS 直接抛异常");
	console.log("6. tools 语义两侧一致：只换自定义部分，文件工具由 FilesystemMiddleware 独立装配");
	console.log(`栈（默认）: ${stackOf(defaultBase).join(" → ")}`);
};

main().catch((e) => {
	console.error("验证失败:", e);
	process.exit(1);
});
