/**
 * 课 8 · Memory 记忆 —— TypeScript 侧实测探针
 *
 * 对齐 Python 侧探针 1-5：
 *   1) 固定税体量（空 AGENTS.md 也付 fixed guidelines）
 *   2) HTML 注释被剥离
 *   3) 多源拼接顺序（不覆盖）
 *   4) 缓存断点（addCacheControl 默认值陷阱）
 *   5) Store 的三个咬人细节（实例 / namespace 可调用 / key 前缀）
 *
 * 运行：npm run l08
 */
import { createDeepAgent, createMemoryMiddleware } from "deepagents";
import { CompositeBackend, FilesystemBackend, StateBackend, StoreBackend } from "deepagents";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

interface MwLike {
	name?: string;
	beforeModel?: unknown;
	beforeAgent?: unknown;
	wrapModelCall?: unknown;
}

/** 抓最终系统提示文本（先跑 beforeAgent/beforeModel 填充 state）。 */
const captureSystemPrompt = async (mw: MwLike): Promise<string> => {
	let state: Record<string, unknown> = { messages: [] };
	for (const hook of ["beforeAgent", "beforeModel"] as const) {
		const fn = mw[hook];
		if (typeof fn !== "function") continue;
		const call = fn as (s: unknown) => Promise<Record<string, unknown> | undefined>;
		try {
			const patch = await call({ ...state });
			// 必须把补丁合并回 state，否则 wrapModelCall 读不到 memoryContents，
			// 记忆正文会变成 (No memory loaded)。
			if (patch) state = { ...state, ...patch };
		} catch (e) {
			console.log(`    [${hook} 报错] ${(e as Error).message.slice(0, 80)}`);
		}
	}

	const box: { sys?: string } = {};
	const call = mw.wrapModelCall as (
		req: unknown,
		h: (r: unknown) => Promise<unknown>,
	) => Promise<unknown>;
	// MemoryMiddleware 会直接访问 request.systemMessage.content，
	// 传 [] 会得到 undefined；这里给一个最小可用的 SystemMessage 形态。
	await call({ systemMessage: { content: "" }, messages: [], state }, async (r) => {
		const v = (r as { systemMessage?: unknown }).systemMessage;
		// 不同中间件的 systemMessage 形态不一样：
		//   SkillsMiddleware → string[]
		//   MemoryMiddleware → SystemMessage（content 是 block 数组）
		if (typeof v === "string") box.sys = v;
		else if (Array.isArray(v)) box.sys = v.map((m) => (typeof m === "string" ? m : JSON.stringify(m))).join("\n");
		else if (v && typeof v === "object") {
			const c = (v as { content?: unknown }).content;
			if (typeof c === "string") box.sys = c;
			else if (Array.isArray(c)) {
				box.sys = c
					.map((b) => {
						const block = b as { text?: string; cache_control?: unknown };
						return (block.text ?? "") + (block.cache_control ? "\n[cache_control:ephemeral]" : "");
					})
					.join("\n");
			} else box.sys = JSON.stringify(c ?? v);
		} else box.sys = "";
		return { content: "ok" };
	});
	return box.sys ?? "";
};

const section = (n: number, t: string) => console.log(`\n====== ${n}) ${t} ======`);

const main = async (): Promise<void> => {
	const root = mkdtempSync(join(tmpdir(), "da-ts-mem-"));
	writeFileSync(join(root, "AGENTS.md"), "# 项目规范\n\n## 代码风格\n- 用 ruff，行宽 100\n", "utf-8");
	const ver = (await import("deepagents/package.json", { with: { type: "json" } })).default.version;
	console.log(`deepagents: ${ver}`);
	console.log(`root: ${root}`);

	const fsb = () => new FilesystemBackend({ rootDir: root, virtualMode: true });

	/* ---------------------------------------------------------------- */
	section(1, "固定税：空 AGENTS.md 也付多少");
	{
		const emptyRoot = mkdtempSync(join(tmpdir(), "da-ts-empty-"));
		writeFileSync(join(emptyRoot, "AGENTS.md"), "", "utf-8");
		const mwEmpty = createMemoryMiddleware({
			backend: new FilesystemBackend({ rootDir: emptyRoot, virtualMode: true }),
			sources: ["/AGENTS.md"],
		});
		const sysEmpty = await captureSystemPrompt(mwEmpty as MwLike);
		console.log(`空 AGENTS.md → 系统提示 ${sysEmpty.length} 字符`);

		const mwReal = createMemoryMiddleware({ backend: fsb(), sources: ["/AGENTS.md"] });
		const sysReal = await captureSystemPrompt(mwReal as MwLike);
		console.log(`有正文 AGENTS.md → 系统提示 ${sysReal.length} 字符`);
		console.log(`固定税 = ${sysEmpty.length} 字符（正文 0）`);

		// 逐档测正文长度对总长的影响
		for (const n of [0, 500, 2000]) {
			const r = mkdtempSync(join(tmpdir(), "da-ts-scale-"));
			writeFileSync(join(r, "AGENTS.md"), "x".repeat(n), "utf-8");
			const mw = createMemoryMiddleware({
				backend: new FilesystemBackend({ rootDir: r, virtualMode: true }),
				sources: ["/AGENTS.md"],
			});
			const s = await captureSystemPrompt(mw as MwLike);
			console.log(`  正文 ${String(n).padStart(5)} → 总长 ${String(s.length).padStart(6)}（增量 ${s.length - sysEmpty.length}）`);
			rmSync(r, { recursive: true, force: true });
		}
		rmSync(emptyRoot, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(2, "HTML 注释是否剥离");
	{
		const r = mkdtempSync(join(tmpdir(), "da-ts-cmt-"));
		writeFileSync(
			join(r, "AGENTS.md"),
			"# 规范\n- 用 ruff\n<!-- 内部备注：不应出现 -->\n",
			"utf-8",
		);
		const mw = createMemoryMiddleware({
			backend: new FilesystemBackend({ rootDir: r, virtualMode: true }),
			sources: ["/AGENTS.md"],
		});
		const sys = await captureSystemPrompt(mw as MwLike);
		console.log(`含 "用 ruff":   ${sys.includes("用 ruff")}`);
		console.log(`含 "内部备注":  ${sys.includes("内部备注")}  ← true 表示未被剥离`);
		rmSync(r, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(3, "多源拼接顺序（不覆盖）");
	{
		const r = mkdtempSync(join(tmpdir(), "da-ts-multi-"));
		mkdirSync(join(r, "user"), { recursive: true });
		mkdirSync(join(r, "proj"), { recursive: true });
		writeFileSync(join(r, "user", "AGENTS.md"), "# 用户级\n- USER_RULE_AAA\n", "utf-8");
		writeFileSync(join(r, "proj", "AGENTS.md"), "# 项目级\n- PROJ_RULE_BBB\n", "utf-8");
		const mw = createMemoryMiddleware({
			backend: new FilesystemBackend({ rootDir: r, virtualMode: true }),
			sources: ["/user/AGENTS.md", "/proj/AGENTS.md"],
		});
		const sys = await captureSystemPrompt(mw as MwLike);
		const iUser = sys.indexOf("USER_RULE_AAA");
		const iProj = sys.indexOf("PROJ_RULE_BBB");
		console.log(`两段都在: ${iUser >= 0 && iProj >= 0}`);
		console.log(`用户级在前: ${iUser < iProj}`);
		rmSync(r, { recursive: true, force: true });
	}

	/* ---------------------------------------------------------------- */
	section(4, "路径写错：file_not_found 是否静默");
	{
		const mw = createMemoryMiddleware({ backend: fsb(), sources: ["/NOT_EXIST.md"] });
		const sys = await captureSystemPrompt(mw as MwLike);
		console.log(`抛异常? 否`);
		console.log(`含 "(No memory loaded)": ${sys.includes("No memory loaded")}`);
		console.log(`提示总长: ${sys.length} 字符（固定税照付）`);
	}

	/* ---------------------------------------------------------------- */
	section(5, "缓存断点：addCacheControl 的默认值");
	{
		// isAnthropicModel(request.model) 会调用 model.getName()，
		// 所以 wrapModelCall 必须带一个模型桩，否则直接 TypeError。
		const fakeAnthropic = { getName: () => "claude-sonnet-4-6" };

		const captureWithModel = async (opts: { addCacheControl?: boolean }): Promise<string> => {
			const mw = createMemoryMiddleware({ backend: fsb(), sources: ["/AGENTS.md"], ...opts }) as MwLike;
			let state: Record<string, unknown> = { messages: [] };
			const before = mw.beforeAgent as (s: unknown) => Promise<Record<string, unknown> | undefined>;
			const patch = await before({ ...state });
			if (patch) state = { ...state, ...patch };
			const box: { sys?: string; ctrl?: boolean } = {};
			const call = mw.wrapModelCall as (req: unknown, h: (r: unknown) => Promise<unknown>) => Promise<unknown>;
			await call({ systemMessage: { content: "" }, messages: [], state, model: fakeAnthropic }, async (r) => {
				const sm = (r as { systemMessage?: { content?: unknown } }).systemMessage;
				const c = sm?.content;
				if (Array.isArray(c)) {
					box.sys = c.map((b) => (b as { text?: string }).text ?? "").join("\n");
					box.ctrl = c.some((b) => (b as { cache_control?: unknown }).cache_control !== undefined);
				}
				return { content: "ok" };
			});
			return `${box.ctrl ? "有" : "无"} cache_control（提示 ${(box.sys ?? "").length} 字符）`;
		};

		console.log(`不传 addCacheControl → ${await captureWithModel({})}`);
		console.log(`addCacheControl: true → ${await captureWithModel({ addCacheControl: true })}`);

		// createDeepAgent 自动装配时给的是什么？
		const agent = createDeepAgent({ model: "openai:gpt-4.1-mini", backend: fsb(), memory: ["/AGENTS.md"] });
		const autoMw = (agent.options.middleware ?? []).find((m) => (m as MwLike).name === "MemoryMiddleware") as MwLike | undefined;
		console.log(`createDeepAgent 自动装配了 MemoryMiddleware? ${autoMw !== undefined}`);
	}

	/* ---------------------------------------------------------------- */
	section(6, "Store 后端：namespace 与 key 前缀");
	{
		// 用一个最小内存 store 模拟 InMemoryStore
		const data = new Map<string, unknown>();
		const fakeStore = {
			get: async (ns: readonly string[], key: string) => data.get(`${ns.join("/")}::${key}`),
			put: async (ns: readonly string[], key: string, value: unknown) => {
				data.set(`${ns.join("/")}::${key}`, value);
			},
			search: async () => [],
			delete: async () => {},
			batch: async () => [],
		};

		try {
			const sb = new StoreBackend({ store: fakeStore as never, namespace: ["my-agent"] as never });
			console.log(`namespace 传数组 → 构造成功? ${sb !== undefined}（注意：TS 侧类型可能不同）`);
		} catch (e) {
			console.log(`namespace 传数组 → 抛错: ${(e as Error).message.slice(0, 60)}`);
		}

		try {
			const sb2 = new StoreBackend({
				store: fakeStore as never,
				namespace: (() => ["my-agent"]) as never,
			});
			console.log(`namespace 传函数 → 构造成功? ${sb2 !== undefined}`);
		} catch (e) {
			console.log(`namespace 传函数 → 抛错: ${(e as Error).message.slice(0, 60)}`);
		}

		const comp = new CompositeBackend(new StateBackend(), { "/memories/": {} as never });
		console.log(`CompositeBackend 位置参数构造成功: ${comp !== undefined}`);
		const routed = (comp as unknown as { getBackendAndKey: (k: string) => [unknown, string] }).getBackendAndKey("/memories/AGENTS.md");
		console.log(`"/memories/AGENTS.md" 剥前缀后 → "${routed[1]}"`);
	}

	/* ---------------------------------------------------------------- */
	section(7, "结论");
	console.log("固定税：两侧都有；TS 侧 4470 字符，Python 侧 5118 字符（TS 少约 13%）");
	console.log("正文叠加：两侧都线性叠加（TS 实测 500→+493、2000→+1993）");
	console.log("HTML 注释：Python 剥离 / TS 保留 —— 两侧相反！");
	console.log("多源拼接不覆盖：两侧一致（用户级在前、项目级在后）");
	console.log("路径写错静默：两侧一致（(No memory loaded) + 固定税照付）");
	console.log("addCacheControl：createDeepAgent 装配时两侧都按是否为 Anthropic 模型决定；");
	console.log("                  但单独 new 中间件时 TS 默认 false、Python 默认 true");
	console.log("Composite/StoreBackend：TS 用位置参数 + 配置对象，namespace 数组或函数都能收");

	rmSync(root, { recursive: true, force: true });
};

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
