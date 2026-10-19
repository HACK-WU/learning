// 课 13 · Deployment 与 Observability（TypeScript 侧）
// 对照：../../playground/13_deployment.py（Python 侧）
// 运行：npm run l13
//
// 本脚本只覆盖"不需要 Docker 构建、不需要真密钥"的部分：
//   ① langgraph.json 的字段校验边界（node_version 只认 "20"/"22"，python_version 被静默忽略）
//   ② `langgraphjs dockerfile` 生成的真实契约（基础镜像、LANGSERVE_GRAPHS、npm i）
//   ③ 起内嵌服务实测 /ok、/info、/docs、/openapi.json、/metrics 与 SSE
// Docker 构建与启动时那三道门（REDIS_URI / POSTGRES_URI / License）需要 docker 与真实
// Redis/Postgres，课文里直接给出实测文本，不塞进这个脚本。
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const line = (t: string) => console.log(`\n===== ${t} =====`);
const CLI = ["-y", "@langchain/langgraph-cli@latest"];

const GRAPH_TS = `import { Annotation, END, START, StateGraph } from "@langchain/langgraph";
const S = Annotation.Root({ n: Annotation<number>({ reducer: (_p, x) => x, default: () => 0 }) });
export const graph = new StateGraph(S)
  .addNode("n1", () => ({ n: 1 }))
  .addEdge(START, "n1").addEdge("n1", END).compile();
`;

// 在临时目录造最小工程并生成 Dockerfile。
// ⚠️ 关键：CLI 配置校验失败时**退出码仍是 0**，报错打在 stdout 且不落文件，
//    所以判断成功与否只能看文件是否存在，不能看退出码。
function genDockerfile(cfg: unknown): { ok: boolean; text: string; dir: string } {
  const dir = mkdtempSync(join(tmpdir(), "lgjs-l13-"));
  writeFileSync(join(dir, "package.json"), JSON.stringify({ name: "probe", type: "module" }));
  writeFileSync(join(dir, "langgraph.json"), JSON.stringify(cfg, null, 2));
  writeFileSync(join(dir, "graph.ts"), GRAPH_TS);
  const out = join(dir, "Dockerfile");
  const r = spawnSync("npx", [...CLI, "dockerfile", out, "--config", join(dir, "langgraph.json")], {
    cwd: dir,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  const raw = ((r.stdout ?? "") + (r.stderr ?? "")).replace(/\u001b\[[0-9;]*m/g, "");
  try {
    return { ok: true, text: readFileSync(out, "utf8"), dir };
  } catch {
    const keep = raw
      .split("\n")
      .filter((l) => !/^\s+at |node_modules\//.test(l))
      .slice(0, 16)
      .join("\n");
    rmSync(dir, { recursive: true, force: true });
    return { ok: false, text: keep, dir: "" };
  }
}

// ---------------------------------------------------------------- 验证一
line("验证一：dockerfile 子命令的默认契约（不写 node_version）");
{
  const r = genDockerfile({ dependencies: ["."], graphs: { my_agent: "./graph.ts:graph" } });
  console.log("  生成成功:", r.ok);
  console.log(r.text.split("\n").slice(0, 6).join("\n"));
  console.log("  -> 基础镜像默认 langgraphjs-api:20（Node 20），且模板用的是 npm i");
  rmSync(r.dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 验证二
line('验证二：node_version 只认字符串 "20" / "22"');
for (const v of ["22", 20, "18"] as const) {
  const r = genDockerfile({
    node_version: v,
    dependencies: ["."],
    graphs: { my_agent: "./graph.ts:graph" },
  });
  if (r.ok) {
    console.log(`  node_version=${JSON.stringify(v)} -> 通过 | ${r.text.split("\n")[0]}`);
    rmSync(r.dir, { recursive: true, force: true });
  } else {
    const expected = (r.text.match(/"expected":\s*"[^"]*"/g) ?? []).join(" / ");
    console.log(`  node_version=${JSON.stringify(v)} -> 被拒 | ${expected || r.text.split("\n")[0]}`);
  }
}
console.log('  -> "22" 通过；数字 20 与 "18" 都被 Zod 拒绝（expected "20" / "22"）');

// ---------------------------------------------------------------- 验证三
line("验证三：python_version 在 TS 侧被静默忽略");
{
  const r = genDockerfile({
    python_version: "3.12",
    dependencies: ["."],
    graphs: { my_agent: "./graph.ts:graph" },
  });
  console.log("  带 python_version 仍成功:", r.ok);
  console.log("  基础镜像 =", r.text.split("\n")[0]);
  console.log("  -> 不报错也不生效，别把 Python 的键照搬过来");
  if (r.ok) rmSync(r.dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 验证四
line("验证四：dependencies 可省略");
{
  const r = genDockerfile({ graphs: { my_agent: "./graph.ts:graph" } });
  console.log("  成功:", r.ok, "| 首行 =", r.text.split("\n")[0]);
  console.log("  -> TS 侧不强制 dependencies（Python 侧省略直接报错）");
  if (r.ok) rmSync(r.dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 验证五
line("验证五：dockerfile_lines 插在 ADD 之前");
{
  const r = genDockerfile({
    dependencies: ["."],
    graphs: { my_agent: "./graph.ts:graph" },
    dockerfile_lines: ["RUN echo 'custom line' > /tmp/custom.txt"],
  });
  const rows = r.text.split("\n");
  const idx = rows.findIndex((l) => l.includes("custom line"));
  const addIdx = rows.findIndex((l) => l.startsWith("ADD "));
  console.log(`  自定义行在第 ${idx + 1} 行，ADD 在第 ${addIdx + 1} 行`);
  console.log("  -> 更靠前，适合在装依赖前补系统包");
  if (r.ok) rmSync(r.dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 验证六
line("验证六：graphs 的导出名写错，CLI 不报（运行期才炸）");
{
  const r = genDockerfile({
    dependencies: ["."],
    graphs: { my_agent: "./graph.ts:not_exist" },
  });
  console.log("  dockerfile 仍生成:", r.ok);
  console.log("  -> 校验只到「字符串格式」，导出名对不对要等服务启动");
  if (r.ok) rmSync(r.dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------- 验证七
line("验证七：起内嵌服务，实测各端点");
{
  // 用本工程启动（已有 node_modules），临时目录解析不到依赖
  const here = dirname(fileURLToPath(import.meta.url));
  const port = 8199;
  const child = spawn(
    "npx",
    [...CLI, "dev", "--port", String(port), "--no-browser", "--config", join(here, "langgraph.json")],
    { cwd: here, env: { ...process.env, LANGSMITH_TRACING: "false" }, stdio: "ignore" }
  );

  const base = `http://127.0.0.1:${port}`;
  const up = async () => {
    for (let i = 0; i < 60; i += 1) {
      try {
        if ((await fetch(`${base}/ok`)).ok) return true;
      } catch {
        /* 还没起来 */
      }
      await new Promise((res) => setTimeout(res, 500));
    }
    return false;
  };

  try {
    const ok = await up();
    console.log("  服务起来了:", ok);
    if (ok) {
      for (const p of ["/ok", "/info", "/docs", "/openapi.json", "/metrics"]) {
        const r = await fetch(`${base}${p}`);
        const body = p === "/ok" || p === "/info" ? " " + (await r.text()) : "";
        console.log(`  GET ${p.padEnd(15)} -> ${r.status}${body}`);
      }
      const sse = await fetch(`${base}/runs/stream`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ assistant_id: "my_agent", input: { n: 0 }, stream_mode: ["updates"] }),
      });
      console.log("  POST /runs/stream ->", sse.status);
      const text = await sse.text();
      console.log(
        text
          .split("\n\n")
          .filter((b) => b.trim())
          .map((b) => "    " + b.replace(/\n/g, " | "))
          .join("\n")
      );
      console.log("  -> event: 是模式名，data: 是内容（标准 SSE，不是 JSON）");
    }
  } finally {
    child.kill("SIGTERM");
    await new Promise((res) => setTimeout(res, 1500));
  }
}

// ---------------------------------------------------------------- 验证八
line("验证八：TS 镜像里跑的仍是 Python 版 langgraph-api");
console.log("  基础镜像换成 langgraphjs-api，但容器内的服务端仍是 /api/langgraph_api（Python），");
console.log("  所以三道门 REDIS_URI / POSTGRES_URI / License 与 Python 侧一字不差。");
console.log("  -> 差异只在基础镜像的 Node 版本、npm i 与 tsx 预构建步骤");

// ---------------------------------------------------------------- 小结
line("小结：TS 侧与 Python 侧的关键差异");
console.log("  1. 基础镜像：langchain/langgraph-api:3.11 ↔ langchain/langgraphjs-api:20");
console.log('  2. 版本键：python_version（默认 3.11）↔ node_version（只认 "20"/"22"，默认 20）');
console.log("  3. dependencies：Python 必填 ↔ TS 可省");
console.log("  4. 命令：langgraph build ↔ langgraphjs build（包 @langchain/langgraph-cli）");
console.log("  5. 端点：两侧都有 /ok、/info、/runs/stream；TS 侧 /docs、/openapi.json、/metrics 全 404");
console.log('  6. /info 字段：Python 有 langgraph_py_version、host；TS 只有 langgraph_js_version、context:"js"');
console.log("  7. 失败语义：langgraphjs 配置校验失败时退出码仍为 0，只能靠「有没有产出文件」判断");
