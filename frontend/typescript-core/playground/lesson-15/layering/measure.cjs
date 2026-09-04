// 测量「改一个类型，要重建多少」。
//
//   godtypes  —— 改动落在 packages/shared（上帝类型文件）→ 所有依赖它的包都要重建
//   layered   —— 改动落在 packages/p0（本包自己的类型）→ 只有 p0 需要重建
//
// 用法：node measure.cjs [重复次数]
const { readFileSync, writeFileSync } = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const TSC = "D:/projects/learning/frontend/typescript-core/playground/node_modules/typescript/bin/tsc";
const ROOT = __dirname;
const REPEAT = Number(process.argv[2] ?? 3);

const GOD_SHARED = path.join(ROOT, "godtypes", "packages", "shared", "src", "index.ts");
const LAYERED_TYPES = path.join(ROOT, "layered", "packages", "p0", "src", "types.ts");

const originalGod = readFileSync(GOD_SHARED, "utf8");
const originalLayered = readFileSync(LAYERED_TYPES, "utf8");

function build(target) {
  const t0 = process.hrtime.bigint();
  execFileSync("node", [TSC, "--build", target], {
    cwd: ROOT,
    stdio: ["ignore", "ignore", "pipe"],
  });
  const t1 = process.hrtime.bigint();
  return Number(t1 - t0) / 1e6; // ms
}

function minOf(fn, n) {
  let best = Infinity;
  for (let i = 0; i < n; i++) best = Math.min(best, fn());
  return best;
}

// 给 Entity0 / Entity 加一个新字段（一次真实的类型变更）
function addField(src, ifaceName) {
  const marker = `export interface ${ifaceName} {`;
  if (!src.includes(marker)) throw new Error(`interface not found: ${ifaceName}`);
  return src.replace(marker, `${marker}\n  note?: string;`);
}

console.log("=== 冷启动构建（一次性） ===");
console.log(`godtypes  cold = ${build("godtypes").toFixed(0)} ms`);
console.log(`layered   cold = ${build("layered").toFixed(0)} ms`);

console.log("\n=== 无改动的增量构建（应当几乎不动） ===");
console.log(`godtypes  noop = ${minOf(() => build("godtypes"), 2).toFixed(0)} ms`);
console.log(`layered   noop = ${minOf(() => build("layered"), 2).toFixed(0)} ms`);

// ⚠️ node + tsc 的启动开销（约 135ms）会淹没小项目的重建差异 —— 课 13 第一版就栽在这里。
//    所以先测「无改动时的空转」作为基线，再看「改了之后的增量」比它多出多少。
const godNoop = minOf(() => build("godtypes"), REPEAT);
const layNoop = minOf(() => build("layered"), REPEAT);
console.log(`godtypes  noop = ${godNoop.toFixed(0)} ms`);
console.log(`layered   noop = ${layNoop.toFixed(0)} ms`);

function measureOnce(applyGod, applyLayered) {
  const god = [];
  const lay = [];
  for (let i = 0; i < REPEAT; i++) {
    applyGod(true);
    god.push(build("godtypes"));
    applyGod(false); // 复原
    build("godtypes"); // 让状态回到「最新」

    applyLayered(true);
    lay.push(build("layered"));
    applyLayered(false);
    build("layered");
  }
  return { god: Math.min(...god), lay: Math.min(...lay) };
}

const applyGod = (on) =>
  writeFileSync(GOD_SHARED, on ? addField(originalGod, "Entity0") : originalGod);
const applyLayered = (on) =>
  writeFileSync(LAYERED_TYPES, on ? addField(originalLayered, "Entity") : originalLayered);

console.log("\n=== 改一个类型之后的增量构建（min of " + REPEAT + "） ===");
const { god: godMs, lay: layMs } = measureOnce(applyGod, applyLayered);
const godDelta = godMs - godNoop;
const layDelta = layMs - layNoop;
console.log(`godtypes  改 shared/Entity0 = ${godMs.toFixed(0)} ms（比空转多 ${godDelta.toFixed(0)} ms）`);
console.log(`layered   改 p0/Entity      = ${layMs.toFixed(0)} ms（比空转多 ${layDelta.toFixed(0)} ms）`);
console.log(`净重建耗时比值 = ${(godDelta / layDelta).toFixed(1)}x`);
