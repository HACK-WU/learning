// 生成一个「指定递归深度」的探测文件，然后用 tsc 编译它，看会不会撞上 TS2589。
// 用法：node gen.js <tail|nontail> <N>
const { writeFileSync, mkdirSync } = require("node:fs");
const { execFileSync } = require("node:child_process");

const TSC = "D:/projects/learning/frontend/typescript-core/playground/node_modules/typescript/bin/tsc";

const mode = process.argv[2];
const n = Number(process.argv[3]);

const zeros = Array.from({ length: n }, () => "0").join(", ");

// 尾递归：分支直接就是递归调用，结果不再被加工 → 可被 TS 4.5+ 优化
const TAIL = `type CountTail<T extends unknown[], Acc extends unknown[] = []> =
  T extends [unknown, ...infer Rest] ? CountTail<Rest, [...Acc, unknown]> : Acc;

type R = CountTail<[${zeros}]>;
declare const r: R;
export const check: ${n} = r.length;
`;

// 非尾递归：递归调用的结果被展开进新元组 → 结果被加工了，无法优化
const NONTAIL = `type CountNonTail<T extends unknown[]> =
  T extends [unknown, ...infer Rest] ? [...CountNonTail<Rest>, unknown] : [];

type R = CountNonTail<[${zeros}]>;
declare const r: R;
export const check: ${n} = r.length;
`;

mkdirSync(`${__dirname}/depth`, { recursive: true });
const file = `${__dirname}/depth/${mode}-${n}.ts`;
writeFileSync(file, mode === "tail" ? TAIL : NONTAIL);

let out = "";
let code = 0;
try {
  // 注意：不要在命令行传 --types [] —— TS 会把 "[]" 当成要找的类型包名（TS2688）。
  // TS 7 的 types 默认就是 ["" ] 的等价行为（不加载任何 @types），这里直接不传即可。
  out = execFileSync("node", [TSC, "--noEmit", "--strict", "--target", "esnext", "--lib", "esnext", file], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (e) {
  code = e.status ?? 1;
  out = (e.stdout ?? "") + (e.stderr ?? "");
}

const hit = out.includes("TS2589") ? "TS2589" : out.includes("TS2321") ? "TS2321" : out.trim().split("\n")[0] ?? "";
console.log(`${mode}\t${n}\texit=${code}\t${code === 0 ? "OK" : hit}`);
