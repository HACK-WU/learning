/**
 * 课 9 · 上下文工程 —— TypeScript 侧实测探针
 *
 * 对齐 Python 侧探针 1-6：
 *   1) 压缩默认阈值随模型变（computeSummarizationDefaults）
 *   2) 工具结果卸载：阈值、排除名单、只认 ToolMessage
 *   3) read_file 靠分页不靠卸载
 *   4) 输入段两道闸：工具参数裁剪 + HumanMessage 卸载
 *   5) 悬空调用修补（createPatchToolCallsMiddleware）
 *   6) 缓存：按模型装配，不是"全局都装"
 *
 * 运行：npm run l09
 */
import {
	createDeepAgent,
	createFilesystemMiddleware,
	createPatchToolCallsMiddleware,
	createSummarizationMiddleware,
	computeSummarizationDefaults,
	FilesystemBackend,
	StateBackend,
} from "deepagents";
import { AIMessage, HumanMessage, SystemMessage, ToolMessage } from "@langchain/core/messages";
import { existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const section = (n: number, t: string) => console.log(`\n====== ${n}) ${t} ======`);

/** 假模型桩：computeSummarizationDefaults / wrapModelCall 只需要能读 profile / getName。 */
const modelStub = (name: string, maxInputTokens?: number) => ({
	getName: () => name,
	profile: maxInputTokens ? { maxInputTokens } : undefined,
});

const main = async (): Promise<void> => {
	const ver = (await import("deepagents/package.json", { with: { type: "json" } })).default.version;
	console.log(`deepagents: ${ver}`);

	/* ---------------------------------------------------------------- */
	section(1, "压缩默认阈值随模型 profile 变");
	{
		for (const [label, m] of [
			["无 profile", modelStub("unknown-model")],
			["200k 窗口（类 Claude）", modelStub("claude-sonnet-4-6", 200_000)],
			["1.05M 窗口（类 GPT）", modelStub("gpt-5.4", 1_050_000)],
		] as const) {
			const d = computeSummarizationDefaults(m as never);
			console.log(`  ${label.padEnd(22)} trigger=${JSON.stringify(d.trigger)} keep=${JSON.stringify(d.keep)}`);
			console.log(`  ${"".padEnd(22)} truncateArgs.trigger=${JSON.stringify(d.truncateArgsSettings.trigger)}`);
		}
	}

	/* ---------------------------------------------------------------- */
	section(2, "工具结果卸载：阈值、排除名单、只认 ToolMessage");
	{
		const root = mkdtempSync(join(tmpdir(), "da-ts-ctx-"));
		const fsb = new FilesystemBackend({ rootDir: root, virtualMode: true });
		const mw = createFilesystemMiddleware({ backend: fsb }) as unknown as { wrapToolCall?: unknown };
		const call = mw.wrapToolCall as (req: unknown, h: (r: unknown) => Promise<unknown>) => Promise<unknown>;

		const mkReq = (id: string) => ({
			toolCall: { id, name: "third_party_api", args: {} },
			tool: {},
			state: {},
			runtime: {},
		});

		// A) 裸字符串结果：TS 只处理 ToolMessage / Command，字符串原样返回
		const rawOut = await call(mkReq("call_1"), async () => "X".repeat(400_000));
		const rawLen = typeof rawOut === "string" ? rawOut.length : JSON.stringify(rawOut).length;
		console.log(`  A) 裸字符串 400,000 字符 → 原样返回 ${rawLen.toLocaleString()} 字符（不卸载）`);

		// B) ToolMessage 结果：才进入卸载逻辑
		const big = new ToolMessage({ content: "Y".repeat(400_000), tool_call_id: "call_2", name: "third_party_api" });
		const res = await call(mkReq("call_2"), async () => big);
		const text = String((res as { content?: unknown })?.content ?? "");
		console.log(`  B) ToolMessage 400,000 字符 → 交给模型 ${text.length.toLocaleString()} 字符`);
		console.log(`     large_tool_results 目录被创建: ${existsSync(join(root, "large_tool_results"))}`);
		if (existsSync(join(root, "large_tool_results")))
			console.log(`     落盘文件: ${readdirSync(join(root, "large_tool_results")).join(", ")}`);
		console.log(`     替换文案前 180 字符:\n     ${text.slice(0, 180).replace(/\n/g, "\n     ")}`);

		rmSync(root, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(3, "read_file 靠分页，不靠卸载");
	{
		const root = mkdtempSync(join(tmpdir(), "da-ts-read-"));
		const fsb = new FilesystemBackend({ rootDir: root, virtualMode: true });
		const mw = createFilesystemMiddleware({ backend: fsb }) as unknown as {
			tools?: Array<{ name?: string; invoke: (a: unknown, cfg?: unknown) => Promise<unknown> }>;
		};
		const readTool = (mw.tools ?? []).find((t) => t.name === "read_file");
		const cfg = { configurable: {}, metadata: {}, config: {} } as never;
		const callRead = async (args: Record<string, unknown>): Promise<string> => {
			const r = await readTool!.invoke(args, cfg);
			const s = typeof r === "string" ? r : JSON.stringify(r);
			// 工具层返回 [{type:"text", text:"..."}]，取 text 部分计长
			try {
				const arr = JSON.parse(s) as Array<{ text?: string }>;
				return arr.map((b) => b.text ?? "").join("");
			} catch {
				return s;
			}
		};

		// 与 Python 侧探针同形状：600,015 字节（"LEADING_MARKER\n" + 60,000 行短行）
		const body = "LEADING_MARKER\n" + "行内容\n".repeat(60_000);
		writeFileSync(join(root, "big.txt"), body, "utf-8");
		console.log(`  文件: 600,015 字节 / 60,001 行`);

		const defaultRead = await callRead({ file_path: "/big.txt" });
		console.log(`  不传 limit（默认 100 行）→ 交给模型 ${defaultRead.length.toLocaleString()} 字符`);
		console.log(`    首行表头: ${defaultRead.split("\n")[0]}`);

		const three = await callRead({ file_path: "/big.txt", offset: 0, limit: 3 });
		console.log(`  limit=3 行 → 交给模型 ${three.length.toLocaleString()} 字符`);

		const all = await callRead({ file_path: "/big.txt", offset: 0, limit: 70_000 });
		console.log(`  limit=70,000 行（越过分页保护）→ ${all.length.toLocaleString()} 字符`);
		console.log(`    （截到 20,000 token ≈ 80,000 字符上限，与卸载阈值同一个数）`);

		console.log(`  large_tool_results 目录被创建: ${existsSync(join(root, "large_tool_results"))}`);

		rmSync(root, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(4, "输入段两道闸：工具参数裁剪 + HumanMessage 卸载");
	{
		const root = mkdtempSync(join(tmpdir(), "da-ts-input-"));
		const fsb = new FilesystemBackend({ rootDir: root, virtualMode: true });
		const BIG = "x = 1\n".repeat(30_000); // 180,000 字符

		// --- 4a) 工具参数裁剪 ---
		const summ = createSummarizationMiddleware({
			model: modelStub("gpt-4.1-mini") as never,
			backend: fsb,
			trigger: { type: "tokens", value: 10_000_000 } as never, // 绝不触发完整摘要
			keep: { type: "messages", value: 10 } as never,
			truncateArgsSettings: {
				trigger: { type: "tokens", value: 500 } as never,
				keep: { type: "messages", value: 2 } as never,
			} as never,
		}) as unknown as { wrapModelCall: unknown };
		const wrapSumm = summ.wrapModelCall as (r: unknown, h: (r: unknown) => Promise<unknown>) => Promise<unknown>;

		const mkHist = (toolName: string, argKey: string) => {
			const h: unknown[] = [
				new HumanMessage({ content: `调用 ${toolName}` }),
				new AIMessage({
					content: "",
					tool_calls: [{ name: toolName, args: { file_path: "/big.py", [argKey]: BIG }, id: "w1" }],
				}),
			];
			for (let i = 0; i < 6; i++) {
				h.push(new HumanMessage({ content: `后续问题 ${i}` }));
				h.push(new AIMessage({ content: `后续回答 ${i}` }));
			}
			return h;
		};

		const sendAs = async (hist: unknown[]) => {
			const box: { len: number; sample: string } = { len: -1, sample: "" };
			await wrapSumm(
				{
					systemMessage: new SystemMessage({ content: "" }),
					messages: [...hist],
					state: { messages: [...hist] },
					tools: [],
					model: modelStub("gpt-4.1-mini") as never,
					runtime: {},
				},
				async (r) => {
					for (const m of (r as { messages: unknown[] }).messages) {
						const ai = m as { type?: string; tool_calls?: Array<{ name?: string; args?: Record<string, unknown> }> };
						if (ai.type !== "ai" || !ai.tool_calls?.length) continue;
						for (const tc of ai.tool_calls) {
							const c = String((tc.args as Record<string, unknown>)?.["content"] ?? (tc.args as Record<string, unknown>)?.["payload"] ?? "");
							if (c) {
								box.len = c.length;
								box.sample = c.slice(0, 60);
							}
						}
					}
					return { content: "ok" };
				},
			);
			return box;
		};

		const wr = await sendAs(mkHist("write_file", "content"));
		console.log(`  A) write_file 的 180,000 字符 content 参数`);
		console.log(`     → 送给模型 ${wr.len} 字符: ${JSON.stringify(wr.sample)}`);

		const ed = await sendAs(mkHist("edit_file", "content"));
		console.log(`  B) edit_file 的 180,000 字符 content 参数 → ${ed.len} 字符`);

		const other = await sendAs(mkHist("huge_tool", "payload"));
		console.log(`  C) 自定义工具 huge_tool 的 180,000 字符参数 → ${other.len.toLocaleString()} 字符（不裁，只有 write/edit 在白名单）`);

		// --- 4b) HumanMessage 卸载 ---
		const fsMw = createFilesystemMiddleware({ backend: fsb }) as unknown as {
			beforeAgent?: unknown;
			wrapModelCall?: unknown;
		};
		const fsBefore = fsMw.beforeAgent as (s: unknown) => Promise<Record<string, unknown> | undefined>;
		const fsWrap = fsMw.wrapModelCall as (r: unknown, h: (r: unknown) => Promise<unknown>) => Promise<unknown>;

		const tryHuman = async (n: number) => {
			const human = new HumanMessage({ content: "H".repeat(n), id: "h1" });
			const patch = await fsBefore({ messages: [human] });
			const evictedTo = patch
				? String(((patch.messages as HumanMessage[])[0].additional_kwargs as Record<string, unknown>).lc_evicted_to ?? "")
				: "";
			if (!patch) {
				console.log(`  D) HumanMessage ${n.toLocaleString()} 字符 → 不卸载（未越 200,000 字符线）`);
				return;
			}
			const box: { len: number; head: string } = { len: -1, head: "" };
			await fsWrap(
				{
					systemMessage: new SystemMessage({ content: "" }),
					messages: patch.messages,
					state: { messages: patch.messages },
					tools: [],
					model: modelStub("gpt-4.1-mini") as never,
					runtime: {},
				},
				async (r) => {
					const m = (r as { messages: HumanMessage[] }).messages[0];
					const c = typeof m.content === "string" ? m.content : JSON.stringify(m.content);
					box.len = c.length;
					box.head = c.slice(0, 130);
					return { content: "ok" };
				},
			);
			console.log(`  D) HumanMessage ${n.toLocaleString()} 字符 → 卸载到 ${evictedTo}`);
			console.log(`     → 送给模型 ${box.len.toLocaleString()} 字符`);
			console.log(`     ${box.head.replace(/\n/g, " ")}`);
		};

		await tryHuman(150_000);
		await tryHuman(210_000);

		rmSync(root, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(5, "悬空调用修补");
	{
		const mw = createPatchToolCallsMiddleware() as unknown as {
			beforeAgent: (s: unknown) => Promise<Record<string, unknown> | undefined>;
		};

		// A) 干净历史 → 不打扰
		const clean = await mw.beforeAgent({
			messages: [new HumanMessage({ content: "hi" }), new AIMessage({ content: "hello" })],
		});
		console.log(`  A) 干净历史 → beforeAgent 返回 ${clean === undefined ? "undefined（不打扰）" : "补丁"}`);

		// B) 两个调用只回一个
		const dirty = [
			new HumanMessage({ content: "读两个文件" }),
			new AIMessage({
				content: "",
				tool_calls: [
					{ name: "read_file", args: { file_path: "/a.txt" }, id: "c1" },
					{ name: "read_file", args: { file_path: "/b.txt" }, id: "c2" },
				],
			}),
			new ToolMessage({ content: "A 的内容", name: "read_file", tool_call_id: "c1" }),
		];
		const out = await mw.beforeAgent({ messages: dirty });
		const arr = (out?.messages ?? []) as unknown[];
		const real = arr.filter((m) => (m as { type?: string }).type !== "remove");
		console.log(`  B) 原 3 条 → 返回 ${arr.length} 项（含 1 个 RemoveMessage）→ 实际 ${real.length} 条`);
		for (const m of real) {
			const mm = m as { type?: string; tool_call_id?: string; status?: string; content?: unknown };
			if (mm.type === "tool" && mm.tool_call_id === "c2")
				console.log(`     补的: id=${mm.tool_call_id} status=${mm.status}`);
			if (mm.type === "tool" && mm.tool_call_id === "c2")
				console.log(`     内容: ${String(mm.content).slice(0, 100)}`);
		}

		// C) 孤立 ToolMessage（有结果无调用）→ 反向也会被删
		const orphan = await mw.beforeAgent({
			messages: [
				new HumanMessage({ content: "x" }),
				new ToolMessage({ content: "无主结果", name: "read_file", tool_call_id: "ghost" }),
			],
		});
		const orphanReal = ((orphan?.messages ?? []) as unknown[]).filter((m) => (m as { type?: string }).type !== "remove");
		console.log(`  C) 孤立 ToolMessage → 修补后 ${orphanReal.length} 条（多出来的无主结果被删）`);
	}

	/* ---------------------------------------------------------------- */
	section(6, "缓存：按模型装配");
	{
		const stacks: Array<[string, string]> = [
			["anthropic:claude-sonnet-4-6", "Anthropic"],
			["openai:gpt-4.1-mini", "OpenAI"],
			["bedrock:us.anthropic.claude-sonnet-4-5-20250929-v1:0", "Bedrock"],
			["deepseek:deepseek-chat", "DeepSeek"],
		];
		for (const [model, label] of stacks) {
			const agent = createDeepAgent({ model, backend: new StateBackend() });
			const names = ((agent.options.middleware ?? []) as Array<{ name?: string }>).map((m) => m.name ?? "?");
			const caches = names.filter((n) => /Caching|CacheBreakpoint/i.test(n));
			console.log(`  ${label.padEnd(10)} 栈 ${names.length} 个 | 缓存相关: ${caches.length ? caches.join(", ") : "（无）"}`);
		}
		console.log(`  说明：缓存中间件按模型装配，非全 provider 统一装配`);
	}

	/* ---------------------------------------------------------------- */
	section(7, "结论");
	console.log("默认阈值：两侧同为 trigger fraction 0.85 / keep fraction 0.10；无 profile 时 170,000 token / 6 条");
	console.log("  差别：TS 无 profile 时 truncateArgs 用 messages 20；有 profile 时 fraction 0.85（与 Python 一致）");
	console.log("结果卸载：阈值 20,000 token ≈ 80,000 字符；排除 7 个文件工具（TS 是 FILESYSTEM_TOOL_NAMES 减 execute）");
	console.log("  差别：TS 只认 ToolMessage / Command，裸字符串原样返回（Python 无此限制）");
	console.log("read_file 分页：两侧一致，不靠卸载");
	console.log("参数裁剪：只对 write_file / edit_file，截到前 20 字符 + '...(argument truncated)'，两侧一致");
	console.log("HumanMessage 卸载：阈值 50,000 token = 200,000 字符，两侧一致，写入 /conversation_history/");
	console.log("悬空调用修补：两侧都补 status=error；TS 文案是 'was cancelled - another message came in'（Python 是 'did not complete'）");
	console.log("缓存：Python 装配 AnthropicPromptCachingMiddleware(ignore)；TS 只在 Anthropic 装 PromptCachingMiddleware + CacheBreakpointMiddleware，");
	console.log("      Bedrock 装 BedrockPromptCachingMiddleware，OpenAI/DeepSeek 完全不装");
};

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
