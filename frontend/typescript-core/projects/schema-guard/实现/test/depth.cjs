// 测量 Infer<S> 能撑多少层嵌套（阶段 5 课 13 结论在本项目里的落地）。
//
// 三种模式，因为「推导不出来」有两种不同的失败方式：
//   instantiate —— 只强制实例化（自身赋值，不做结构比较）→ 失败通常是 TS2589
//   compare     —— 用 Equals 做结构比较（更接近真实用法）    → 失败通常是 TS2321
//
// 两种嵌套形状（行为不同！）：
//   array  —— array(array(...array(string())))
//   object —— object({ a: object({ a: ... string() ... }) })
//
// 用法：node depth.cjs <instantiate|compare> <array|object> [起始] [结束]
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const TSC = path.join(__dirname, "..", "node_modules", "typescript", "bin", "tsc");
const TMP = path.join(__dirname, ".depth");

const mode = process.argv[2] ?? "compare";
const shape = process.argv[3] ?? "array";
const from = Number(process.argv[4] ?? 44);
const to = Number(process.argv[5] ?? 52);

const nestedSchema =
  shape === "array"
    ? (n) => `${"array(".repeat(n)}string()${")".repeat(n)}`
    : (n) => `${"object({ a: ".repeat(n)}string()${" })".repeat(n)}`;

const expectedType =
  shape === "array"
    ? (n) => "string" + "[]".repeat(n)
    : (n) => `${"{ a: ".repeat(n)}string${" }".repeat(n)}`;

function buildFile(n) {
  // 生成的文件在 test/.depth/ 下，src 要往上两级
  return `import { ${shape === "array" ? "array" : "object"}, string } from "../../src/index.js";
import type { Infer } from "../../src/index.js";

const s = ${nestedSchema(n)};
type Got = Infer<typeof s>;

${
  mode === "compare"
    ? `type Equals<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends <T>() => T extends Y ? 1 : 2 ? true : false;
type Expect<T extends true> = T;
// 用 Equals 强制「结构比较」：推导或比较失败都会在这里暴露
type _ = Expect<Equals<Got, ${expectedType(n)}>>;`
    : `// 只强制实例化：自身赋值，不做结构比较
declare const v: Got;
export const out: Got = v;`
}
`;
}

function compile(n) {
  const file = path.join(TMP, `d${n}.ts`);
  writeFileSync(file, buildFile(n));
  try {
    // ⚠️ 两个命令行坑：
    //   1) 必须加 --ignoreConfig：当前目录有 tsconfig.json 时不能传文件路径（TS5112，课 10 实测）
    //   2) 不要传 --types []：TS 会把 "[]" 当成类型包名（TS2688，课 13 实测）。默认就是 []，不传即可。
    execFileSync(
      "node",
      [TSC, "--noEmit", "--strict", "--target", "esnext", "--module", "nodenext",
       "--moduleResolution", "nodenext", "--lib", "esnext",
       "--skipLibCheck", "--ignoreConfig", file],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
    return { n, ok: true, err: "" };
  } catch (e) {
    const out = (e.stdout ?? "") + (e.stderr ?? "");
    return { n, ok: false, err: out.match(/TS\d+/)?.[0] ?? "ERR" };
  }
}

rmSync(TMP, { recursive: true, force: true });
mkdirSync(TMP, { recursive: true });

const results = [];
for (let n = from; n <= to; n++) results.push(compile(n));

console.log(`mode = ${mode}, shape = ${shape}\n`);
console.log("depth  result   error");
console.log("-----  -------  -----");
for (const r of results) {
  console.log(`${String(r.n).padEnd(5)}  ${(r.ok ? "OK" : "FAIL").padEnd(7)}  ${r.err}`);
}

const oks = results.filter((r) => r.ok).map((r) => r.n);
const fails = results.filter((r) => !r.ok).map((r) => r.n);
if (oks.length > 0 && fails.length > 0) {
  const firstFail = Math.min(...fails);
  console.log(`\n=> 最大可用深度 = ${Math.max(...oks)} 层（${firstFail} 层起报 ${results.find((r) => r.n === firstFail)?.err}）`);
} else {
  console.log(`\n=> 本区间内全部 ${oks.length > 0 ? "通过" : "失败"}，请调整深度区间`);
}

rmSync(TMP, { recursive: true, force: true });
