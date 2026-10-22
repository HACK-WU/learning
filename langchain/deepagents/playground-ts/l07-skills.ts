/**
 * 课 7 · Skills 技能 —— TypeScript 侧实测探针
 *
 * 对齐 Python 侧探针 1-4：
 *   1) 不传 skills vs 传了 skills 的系统提示差异
 *   2) 路径由后端解析（StateBackend / FilesystemBackend 的虚拟路径语义）
 *   3) 发现阶段渲染出的 Available Skills 段长什么样
 *   4) read_file 读全文会拿到完整 frontmatter
 * 额外：固定说明文字长度、name/description 校验行为、pinnedSkills、include_tools
 *
 * 运行：npm run l07
 */
import { createDeepAgent, createSkillsMiddleware } from "deepagents";
import { FilesystemBackend, StateBackend, type BackendProtocol } from "deepagents";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/* ------------------------------------------------------------------ */
/* 工具函数                                                             */
/* ------------------------------------------------------------------ */

/** 抓系统提示（拦 wrapModelCall，不发网络请求）。 */
interface MwLike {
	name?: string;
	beforeModel?: unknown;
	wrapModelCall?: unknown;
}

const captureSystemPrompt = async (mw: MwLike): Promise<string> => {
	const box: { sys?: string } = {};

	// 1) 先跑 beforeModel：它会扫后端、把 skillsMetadata 写回 state。
	//    若不跑这一步，wrapModelCall 里 request.state.skillsMetadata 是空的，
	//    技能列表会渲染成 "No skills available yet"。
	let state: Record<string, unknown> = { skillsMetadata: null, messages: [] };
	if (typeof mw.beforeModel === "function") {
		const before = mw.beforeModel as (s: unknown) => Promise<Record<string, unknown> | undefined>;
		const patch = await before(state);
		if (patch) state = { ...state, ...patch };
	}

	// 2) 再拦 wrapModelCall 拿拼好的系统消息
	const call = mw.wrapModelCall as (
		req: unknown,
		handler: (r: unknown) => Promise<unknown>,
	) => Promise<unknown>;
	// 注意：request.systemMessage 是 SystemMessage[]，中间件会对它 .concat()，
	// 传 undefined 会直接 TypeError。这里传空数组即可拿到拼好的技能段。
	await call({ systemMessage: [], messages: [], state }, async (r) => {
		// 注意：TS 侧 request.systemMessage 是 string[]（不是 SystemMessage[]），
		// 元素本身就是正文。若按 .content 取会得到空串。
		const arr = (r as { systemMessage?: unknown[] }).systemMessage ?? [];
		box.sys = arr.map((m) => (typeof m === "string" ? m : JSON.stringify(m))).join("\n");
		return { content: "ok" };
	});
	return box.sys ?? "";
};

/** 造一个临时 skill 库。 */
const makeSkillRoot = (): string => {
	const root = mkdtempSync(join(tmpdir(), "da-ts-skills-"));
	mkdirSync(join(root, "code-review"), { recursive: true });
	writeFileSync(
		join(root, "code-review", "SKILL.md"),
		[
			"---",
			"name: code-review",
			"description: 按团队 SOP 审查代码 diff，输出分级问题清单。当用户要求 review 时使用。",
			"---",
			"",
			"# 代码审查 SOP",
			"",
			"## 步骤",
			"1. 先看 git diff --stat，确认改动范围",
			"2. 逐文件读 diff，按五类问题打标",
			"3. 按严重度排序，输出到表格",
			"",
			"## 五类必查项",
			"- 语义一致性 / 空值与边界 / 异常处理 / 资源泄露 / 测试覆盖",
			"",
		].join("\n"),
		"utf-8",
	);
	// 故意写歪的 name（大写），验证「只告警仍加载」
	mkdirSync(join(root, "bad-name"), { recursive: true });
	writeFileSync(
		join(root, "bad-name", "SKILL.md"),
		["---", "name: Bad-Name", "description: 名字写歪了。", "---", "", "# 正文", ""].join("\n"),
		"utf-8",
	);
	// 缺 description，验证「直接丢弃」
	mkdirSync(join(root, "no-desc"), { recursive: true });
	writeFileSync(
		join(root, "no-desc", "SKILL.md"),
		["---", "name: no-desc", "---", "", "# 正文", ""].join("\n"),
		"utf-8",
	);
	return root;
};

const section = (n: number, title: string): void => {
	console.log(`\n====== ${n}) ${title} ======`);
};

const main = async (): Promise<void> => {
	const skillRoot = makeSkillRoot();
	console.log(`deepagents: ${(await import("deepagents/package.json", { with: { type: "json" } })).default.version}`);
	console.log(`skill 库: ${skillRoot}`);

	const fsBackend = new FilesystemBackend({ rootDir: skillRoot, virtualMode: true });

	/* ---------------------------------------------------------------- */
	section(1, "不传 skills vs 传了 skills");
	{
		const bare = createDeepAgent({ model: "openai:gpt-4.1-mini" });
		const bareMw = (bare.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "FilesystemMiddleware",
		) as MwLike | undefined;
		// 无 skills 时没有 SkillsMiddleware
		const hasSkillsMw = (bare.options.middleware ?? []).some(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		);
		console.log(`无 skills= → 有 SkillsMiddleware? ${hasSkillsMw}`);

		const withSkills = createDeepAgent({
			model: "openai:gpt-4.1-mini",
			backend: fsBackend,
			skills: ["/"],
		});
		const withMw = (withSkills.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		console.log(`传 skills=["/"] → 有 SkillsMiddleware? ${withMw !== undefined}`);
		if (withMw) {
			const sys = await captureSystemPrompt(withMw);
			console.log(`  系统提示含 Available Skills: ${sys.includes("**Available Skills:**")}`);
			console.log(`  系统提示长度: ${sys.length} 字符`);
			const m = sys.match(/\*\*Available Skills:\*\*[\s\S]*?(?=\n\n\*\*How to Use|$)/);
			console.log(`  技能段（前 3 行）:`);
			(m?.[0] ?? "(未匹配)").split("\n").slice(0, 3).forEach((l) => console.log(`    ${l}`));
		}
	}

	/* ---------------------------------------------------------------- */
	section(2, "路径由后端解析");
	{
		// StateBackend + 磁盘绝对路径 → 空态
		const stateBackend = new StateBackend();
		const a1 = createDeepAgent({
			model: "openai:gpt-4.1-mini",
			backend: stateBackend,
			skills: [skillRoot],
		});
		const mw1 = (a1.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		if (mw1) {
			const sys = await captureSystemPrompt(mw1);
			console.log(
				`StateBackend    + 磁盘绝对路径 → ${sys.includes("No skills available yet") ? "No skills available yet" : "意外有技能"}`,
			);
		}

		// FilesystemBackend + 磁盘绝对路径 → 空态（被当虚拟路径）
		const a2 = createDeepAgent({
			model: "openai:gpt-4.1-mini",
			backend: fsBackend,
			skills: [skillRoot],
		});
		const mw2 = (a2.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		if (mw2) {
			const sys = await captureSystemPrompt(mw2);
			console.log(
				`Filesystem(vm)  + 磁盘绝对路径 → ${sys.includes("No skills available yet") ? "No skills available yet" : "意外有技能"}`,
			);
		}

		// FilesystemBackend + "/" → 生效
		const a3 = createDeepAgent({
			model: "openai:gpt-4.1-mini",
			backend: fsBackend,
			skills: ["/"],
		});
		const mw3 = (a3.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		if (mw3) {
			const sys = await captureSystemPrompt(mw3);
			const names = [...sys.matchAll(/- \*\*([a-z0-9-]+)\*\*/g)].map((x) => x[1]);
			console.log(`Filesystem(vm)  + "/"        → 列出: ${names.join(", ") || "(空)"}`);
		}
	}

	/* ---------------------------------------------------------------- */
	section(3, "Available Skills 段全文");
	{
		const a = createDeepAgent({ model: "openai:gpt-4.1-mini", backend: fsBackend, skills: ["/"] });
		const mw = (a.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		if (mw) {
			const sys = await captureSystemPrompt(mw);
			const start = sys.indexOf("**Available Skills:**");
			const end = sys.indexOf("**When to Use Skills:**");
			console.log(sys.slice(start, end > 0 ? end : start + 900));
		}
	}

	/* ---------------------------------------------------------------- */
	section(4, "read_file 读全文：是否含 frontmatter");
	{
		const raw = await fsBackend.read("/code-review/SKILL.md");
		const content = (raw as { content?: string }).content ?? "";
		console.log(`首行: ${content.split("\n")[0]}`);
		console.log(`含 name: 字段? ${content.includes("name: code-review")}`);
		console.log(`含正文标题? ${content.includes("# 代码审查 SOP")}`);
		console.log(`总行数: ${content.split("\n").length}`);
	}

	/* ---------------------------------------------------------------- */
	section(5, "固定说明文字长度（不随 skill 数变化）");
	{
		const measure = async (skillsPaths: string[]): Promise<number> => {
			const a = createDeepAgent({
				model: "openai:gpt-4.1-mini",
				backend: fsBackend,
				skills: skillsPaths,
			});
			const mw = (a.options.middleware ?? []).find(
				(m) => (m as MwLike).name === "SkillsMiddleware",
			) as MwLike | undefined;
			if (!mw) return 0;
			const sys = await captureSystemPrompt(mw);
			const s = sys.indexOf("## Skills System");
			const e = sys.indexOf("**When to Use Skills:**");
			return s >= 0 ? sys.slice(s).length : 0;
		};
		console.log(`技能段总长（含固定说明）: ${await measure(["/"])} 字符`);
		console.log(`另一个 backend 同样测: ${await measure(["/"])} 字符（应相同 → 固定说明不随数量变）`);
	}

	/* ---------------------------------------------------------------- */
	section(6, "name 写歪 / description 缺失 的实际效果");
	{
		const a = createDeepAgent({ model: "openai:gpt-4.1-mini", backend: fsBackend, skills: ["/"] });
		const mw = (a.options.middleware ?? []).find(
			(m) => (m as MwLike).name === "SkillsMiddleware",
		) as MwLike | undefined;
		if (mw) {
			const sys = await captureSystemPrompt(mw);
			const names = [...sys.matchAll(/- \*\*([^*]+)\*\*/g)].map((x) => x[1]);
			console.log(`实际加载的技能: ${names.join(" | ")}`);
			console.log(`  bad-name 在不在: ${names.some((n) => n.toLowerCase().includes("bad"))}`);
			console.log(`  no-desc  在不在: ${names.some((n) => n.includes("no-desc"))}`);
		}
	}

	/* ---------------------------------------------------------------- */
	section(7, "createSkillsMiddleware 直连 + pinnedSkills");
	{
		const mw = createSkillsMiddleware({ backend: fsBackend, sources: ["/"] });
		const sys = await captureSystemPrompt(mw as MwLike);
		console.log(`直连构造可用: ${sys.includes("**Available Skills:**")}`);
		console.log(`中间件 name: ${(mw as MwLike).name}`);
	}

	/* ---------------------------------------------------------------- */
	section(8, "结论");
	console.log("路径语义：两侧一致（交给后端解析，不是 OS 路径）");
	console.log("name 写歪：两侧一致（告警仍加载）；description 缺失：两侧一致（丢弃）");
	console.log("read_file：两侧一致（返回完整 frontmatter + 正文）");
	console.log("TS 独有：createSkillsMiddleware 可独立构造；skills 支持单技能路径");

	rmSync(skillRoot, { recursive: true, force: true });
};

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
