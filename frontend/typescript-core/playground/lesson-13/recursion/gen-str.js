// 生成一个「指定长度字符串」的字符串递归探测文件，看两种写法各能撑多长。
// 用法：node gen-str.js <naive|acc> <N>
const { writeFileSync, mkdirSync } = require("node:fs");
const { execFileSync } = require("node:child_process");

const TSC = "D:/projects/learning/frontend/typescript-core/playground/node_modules/typescript/bin/tsc";

const mode = process.argv[2];
const n = Number(process.argv[3]);

const text = "a".repeat(n);

const PRELUDE = `
// 朴素版：递归结果被并进联合类型 → 非尾递归
type GetCharsNaive<S extends string> =
  S extends \`\${infer Char}\${infer Rest}\` ? Char | GetCharsNaive<Rest> : never;

// 累加器版：尾递归
type GetChars<S extends string> = GetCharsHelper<S, never>;
type GetCharsHelper<S extends string, Acc> =
  S extends \`\${infer Char}\${infer Rest}\` ? GetCharsHelper<Rest, Char | Acc> : Acc;
`;

const body =
  PRELUDE +
  (mode === "naive"
    ? `
type R = GetCharsNaive<"${text}">;
declare const r: R;
export const check: "a" = r;
`
    : `
type R = GetChars<"${text}">;
declare const r: R;
export const check: "a" = r;
`);

mkdirSync(`${__dirname}/strdepth`, { recursive: true });
const file = `${__dirname}/strdepth/${mode}-${n}.ts`;
writeFileSync(file, body);

let out = "";
let code = 0;
try {
  out = execFileSync("node", [TSC, "--noEmit", "--strict", "--target", "esnext", "--lib", "esnext", file], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (e) {
  code = e.status ?? 1;
  out = (e.stdout ?? "") + (e.stderr ?? "");
}

const hit = out.includes("TS2589") ? "TS2589" : out.trim().split("\n")[0] ?? "";
console.log(`${mode}\t${n}\texit=${code}\t${code === 0 ? "OK" : hit}`);
