// 生成「JS → TS 渐进迁移」的各个阶段，每个阶段都能单独编译。
//
// 依赖方向：app → middle → leaf（leaf 是叶子模块）
//
// 埋的 bug：app.js 把字符串 "3" 传给了要求 number 的 lineTotal。
//   这个 bug 只有在 middle 被标注之后才会暴露 —— 而 middle 要能被标注，
//   又得先让 leaf 有真实类型。这就是「从叶子开始」的由来。
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const path = require("node:path");

const ROOT = __dirname;

// ---------- 各文件的 JS / TS 版本 ----------
const LEAF_JS = `// 叶子模块：不依赖任何东西
/**
 * @param {number} amount
 * @param {string} currency
 * @returns {string}
 */
export function formatMoney(amount, currency) {
  return currency + " " + amount.toFixed(2);
}
`;

const LEAF_TS = `// 叶子模块：不依赖任何东西
export function formatMoney(amount: number, currency: string): string {
  return currency + " " + amount.toFixed(2);
}
`;

const MIDDLE_JS = `// 中间层：依赖 leaf，暂时没有任何类型标注
import { formatMoney } from "./leaf.js";

export function lineTotal(qty, unitPrice) {
  return formatMoney(qty * unitPrice, "CNY");
}
`;

const MIDDLE_TS = `// 中间层：依赖 leaf，已迁移到 TS
import { formatMoney } from "./leaf.js";

export function lineTotal(qty: number, unitPrice: number): string {
  return formatMoney(qty * unitPrice, "CNY");
}
`;

const APP_JS = `// 入口：依赖 middle。这里埋了一个 bug —— qty 是字符串
import { lineTotal } from "./middle.js";

export const label = lineTotal("3", 10);
`;

const APP_TS_FIXED = `// 入口：已迁移到 TS，并且把那个 bug 修好了
import { lineTotal } from "./middle.js";

export const label = lineTotal(3, 10);
`;

const APP_TS_BUGGY = `// 入口：已迁移到 TS，但 bug 还在
import { lineTotal } from "./middle.js";

export const label = lineTotal("3", 10);
`;

const VARIANTS = {
  leaf: { js: LEAF_JS, ts: LEAF_TS },
  middle: { js: MIDDLE_JS, ts: MIDDLE_TS },
  app: { js: APP_JS, ts: APP_TS_FIXED },
};

// ---------- 各阶段 ----------
const STAGES = {
  // 起点：全是 JS，checkJs 打开但 strict 关着（老项目开不动 strict）
  "stage0-all-js": { leaf: "js", middle: "js", app: "js", strict: false },
  // 第 1 步：先迁叶子
  "stage1-leaf-ts": { leaf: "ts", middle: "js", app: "js", strict: false },
  // 第 2 步：再迁中间层 —— 此时 app 的 bug 才暴露出来
  "stage2-middle-ts": { leaf: "ts", middle: "ts", app: "js", strict: false },
  // 第 3 步：迁入口并修掉 bug
  "stage3-all-ts": { leaf: "ts", middle: "ts", app: "ts", strict: false },
  // 第 4 步：全部迁完之后，才把 strict 打开（对应课 10 的渐进收紧）
  "stage4-strict-on": { leaf: "ts", middle: "ts", app: "ts", strict: true },
  // ⚠️ 反例：跳过叶子，先迁入口 —— 类型信息还没建立，什么都查不出来
  "order-app-first": { leaf: "js", middle: "js", app: "ts-buggy", strict: false },
};

for (const [name, cfg] of Object.entries(STAGES)) {
  const dir = path.join(ROOT, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(path.join(dir, "src"), { recursive: true });

  for (const mod of ["leaf", "middle", "app"]) {
    let src;
    if (mod === "app" && cfg.app === "ts-buggy") {
      src = APP_TS_BUGGY;
    } else {
      src = VARIANTS[mod][cfg[mod]];
    }
    const ext = cfg[mod].startsWith("ts") ? "ts" : "js";
    writeFileSync(path.join(dir, "src", `${mod}.${ext}`), src);
  }

  writeFileSync(
    path.join(dir, "tsconfig.json"),
    JSON.stringify(
      {
        compilerOptions: {
          target: "esnext",
          module: "nodenext",
          moduleResolution: "nodenext",
          allowJs: true,
          checkJs: true,
          strict: cfg.strict,
          types: [],
          lib: ["esnext"],
          noEmit: true,
        },
        include: ["./src"],
      },
      null,
      2,
    ),
  );
  writeFileSync(path.join(dir, "package.json"), JSON.stringify({ type: "module" }, null, 2));
}

console.log(`generated ${Object.keys(STAGES).length} migration stages`);
