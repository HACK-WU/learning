// 测量「类型推导体操」的编译期代价 —— `设计决策.md` 决策点 2 的实测证据。
//
// 两个项目，运行时校验逻辑**完全相同**（都走 src/check.ts），
// 唯一的区别是编译期怎么拿到类型：
//   gym/    —— parse(s, v)          → ParseResult<Infer<typeof s>>   （类型推导）
//   manual/ —— parseAs<Shape>(s, v)  → ParseResult<Shape>             （手写 interface）
//
// 用法：node cost.cjs [文件数] [重复次数]
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const ROOT = path.join(__dirname, "..");
const TSC = path.join(ROOT, "node_modules", "typescript", "bin", "tsc");
const TMP = path.join(__dirname, ".cost");

const N_FILES = Number(process.argv[2] ?? 150);
const REPEAT = Number(process.argv[3] ?? 3);

// 每个文件里的 schema：6 个字段 + 1 层嵌套
const FIELDS = [
  ["name", "string()", "string"],
  ["age", "number(0)", "number"],
  ["active", "boolean()", "boolean"],
  ["tags", "array(string())", "string[]"],
  ["score", "number()", "number"],
  ["profile", 'object({ email: string(), level: number() })', "{ email: string; level: number }"],
];

function schemaLiteral() {
  return `object({ ${FIELDS.map(([k, s]) => `${k}: ${s}`).join(", ")} })`;
}

function interfaceBody() {
  return `{\n${FIELDS.map(([k, , t]) => `  ${k}: ${t};`).join("\n")}\n}`;
}

// 生成的文件在 test/.cost/<variant>/src/ 下，要往上四级才能到项目的 src/
const UP = "../../../../src";

function buildGymFile(i) {
  return `import { array, boolean, number, object, string, parse } from "${UP}/index.js";

const s${i} = ${schemaLiteral()};
const raw${i}: unknown = JSON.parse('{}');

// 类型由 Infer<S> 推导，调用方什么都不用写
const r${i} = parse(s${i}, raw${i});

let out${i}: string;
if (r${i}.ok) {
  const v${i} = r${i}.value;
  out${i} = v${i}.name + v${i}.age + v${i}.profile.level;
} else {
  out${i} = String(r${i}.errors.length);
}
export { out${i} };
`;
}

function buildManualFile(i) {
  return `import { array, boolean, number, object, string } from "${UP}/index.js";
import { parseAs } from "./parse-as.js";

interface Shape${i} ${interfaceBody()}

const s${i} = ${schemaLiteral()};
const raw${i}: unknown = JSON.parse('{}');

// 类型由调用方手写（对照组）
const r${i} = parseAs<Shape${i}>(s${i}, raw${i});

let out${i}: string;
if (r${i}.ok) {
  const v${i} = r${i}.value;
  out${i} = v${i}.name + v${i}.age + v${i}.profile.level;
} else {
  out${i} = String(r${i}.errors.length);
}
export { out${i} };
`;
}

const PARSE_AS = `// 决策点 2 的对照组：不做类型推导，由调用方手写 interface。
// 运行时校验**完全复用** src/check.ts —— 所以两个项目的差异只来自编译期。
import { check } from "${UP}/check.js";
import type { Schema } from "${UP}/index.js";
import { err, ok, type ParseResult } from "${UP}/result.js";

export function parseAs<T>(schema: Schema, value: unknown): ParseResult<T> {
  const errors = check(schema, value, "");
  return errors.length > 0 ? err(errors) : (ok(value as T) as ParseResult<T>);
}
`;

const TSCONFIG = JSON.stringify(
  {
    compilerOptions: {
      target: "esnext",
      module: "nodenext",
      moduleResolution: "nodenext",
      strict: true,
      noUncheckedIndexedAccess: true,
      exactOptionalPropertyTypes: true,
      noEmit: true,
      types: ["node"],
      lib: ["esnext"],
      skipLibCheck: true,
      verbatimModuleSyntax: true,
    },
    include: ["./src"],
  },
  null,
  2,
);

rmSync(TMP, { recursive: true, force: true });
for (const variant of ["gym", "manual"]) {
  const src = path.join(TMP, variant, "src");
  mkdirSync(src, { recursive: true });
  for (let i = 0; i < N_FILES; i++) {
    writeFileSync(
      path.join(src, `f${i}.ts`),
      variant === "gym" ? buildGymFile(i) : buildManualFile(i),
    );
  }
  if (variant === "manual") writeFileSync(path.join(src, "parse-as.ts"), PARSE_AS);
  writeFileSync(path.join(TMP, variant, "tsconfig.json"), TSCONFIG);
  writeFileSync(path.join(TMP, variant, "package.json"), JSON.stringify({ type: "module" }, null, 2));
}

function compile(variant) {
  const t0 = process.hrtime.bigint();
  execFileSync("node", [TSC, "-p", path.join(TMP, variant)], {
    cwd: ROOT,
    stdio: ["ignore", "ignore", "pipe"],
  });
  return Number(process.hrtime.bigint() - t0) / 1e6;
}

function minOf(variant, n) {
  let best = Infinity;
  for (let i = 0; i < n; i++) best = Math.min(best, compile(variant));
  return best;
}

console.log(`生成 ${N_FILES} 个文件 x 2 个变体（gym / manual），运行时校验逻辑完全相同\n`);

// 预热
compile("gym");
compile("manual");

const gymMs = minOf("gym", REPEAT);
const manualMs = minOf("manual", REPEAT);

console.log(`gym    （Infer<S> 推导）  = ${gymMs.toFixed(0)} ms  (min of ${REPEAT})`);
console.log(`manual （手写 interface）= ${manualMs.toFixed(0)} ms  (min of ${REPEAT})`);
console.log(`差值 = ${(gymMs - manualMs).toFixed(0)} ms，比值 = ${(gymMs / manualMs).toFixed(2)}x`);
console.log("\n注：绝对值含 node+tsc 启动开销（约 135ms，课 13 实测），看差值更准。");

rmSync(TMP, { recursive: true, force: true });
