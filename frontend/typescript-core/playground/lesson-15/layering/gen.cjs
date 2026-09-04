// 生成两个「体量相同、但类型放置方式不同」的 monorepo，用于测量「改一个类型要重建多少」。
//
//   godtypes/  —— 所有类型集中在一个 packages/shared 里，业务包全部依赖它
//   layered/   —— 每个业务包自带类型，包间只通过窄接口通信
//
// 用法：node gen.cjs [包数] [每包文件数]
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const path = require("node:path");

const ROOT = __dirname;
const N_PKGS = Number(process.argv[2] ?? 8);
const N_FILES = Number(process.argv[3] ?? 40);

const PKG_TSCONFIG = (refs) =>
  JSON.stringify(
    {
      compilerOptions: {
        target: "esnext",
        module: "nodenext",
        moduleResolution: "nodenext",
        strict: true,
        types: [],
        lib: ["esnext"],
        skipLibCheck: true,
        composite: true,
        declaration: true,
        rootDir: "./src",
        outDir: "./dist",
      },
      include: ["./src"],
      references: refs,
    },
    null,
    2,
  );

const ROOT_TSCONFIG = (refs) =>
  JSON.stringify({ files: [], references: refs }, null, 2);

const PKG_JSON = (name) => JSON.stringify({ name, private: true, type: "module" }, null, 2);

// ---------- godtypes 变体：类型全在 shared ----------
function buildGodTypes() {
  const dir = path.join(ROOT, "godtypes");
  rmSync(dir, { recursive: true, force: true });

  // shared：一个「上帝类型文件」
  const sharedLines = ["// 全项目共用的类型集中在这里 —— 任何一处改动都会触发所有包重建", ""];
  for (let i = 0; i < N_PKGS; i++) {
    sharedLines.push(`export interface Entity${i} {`);
    sharedLines.push(`  id: string;`);
    sharedLines.push(`  name: string;`);
    sharedLines.push(`  amount: number;`);
    sharedLines.push(`  tags: string[];`);
    sharedLines.push(`  meta: { createdAt: string; updatedAt: string };`);
    sharedLines.push(`}`);
    sharedLines.push("");
  }
  mkdirSync(path.join(dir, "packages", "shared", "src"), { recursive: true });
  writeFileSync(path.join(dir, "packages", "shared", "src", "index.ts"), sharedLines.join("\n"));
  writeFileSync(path.join(dir, "packages", "shared", "tsconfig.json"), PKG_TSCONFIG([]));
  writeFileSync(path.join(dir, "packages", "shared", "package.json"), PKG_JSON("shared"));

  const refs = [{ path: "./packages/shared" }];
  for (let p = 0; p < N_PKGS; p++) {
    const pkgDir = path.join(dir, "packages", `p${p}`);
    mkdirSync(path.join(pkgDir, "src"), { recursive: true });
    writeFileSync(path.join(pkgDir, "tsconfig.json"), PKG_TSCONFIG([{ path: "../shared" }]));
    writeFileSync(path.join(pkgDir, "package.json"), PKG_JSON(`p${p}`));
    for (let f = 0; f < N_FILES; f++) {
      const lines = [
        `import type { Entity${p} } from "../../shared/dist/index.js";`,
        "",
        `export function handle${f}(e: Entity${p}): string {`,
        `  return e.id + ":" + e.name + ":" + e.amount + ":" + e.tags.length + ":" + e.meta.createdAt;`,
        `}`,
        "",
        `export const sample${f}: Entity${p} = {`,
        `  id: "e${p}-${f}",`,
        `  name: "entity ${p} ${f}",`,
        `  amount: ${f},`,
        `  tags: ["t${f}"],`,
        `  meta: { createdAt: "2026-01-01", updatedAt: "2026-01-02" },`,
        `};`,
      ];
      writeFileSync(path.join(pkgDir, "src", `f${f}.ts`), lines.join("\n"));
    }
    refs.push({ path: `./packages/p${p}` });
  }
  writeFileSync(path.join(dir, "tsconfig.json"), ROOT_TSCONFIG(refs));
  writeFileSync(path.join(dir, "package.json"), PKG_JSON("godtypes"));
}

// ---------- layered 变体：每个包自带类型 ----------
function buildLayered() {
  const dir = path.join(ROOT, "layered");
  rmSync(dir, { recursive: true, force: true });

  const refs = [];
  for (let p = 0; p < N_PKGS; p++) {
    const pkgDir = path.join(dir, "packages", `p${p}`);
    mkdirSync(path.join(pkgDir, "src"), { recursive: true });
    // 没有 shared 依赖：类型自己带
    writeFileSync(path.join(pkgDir, "tsconfig.json"), PKG_TSCONFIG([]));
    writeFileSync(path.join(pkgDir, "package.json"), PKG_JSON(`p${p}`));

    // types.ts：本包自己的类型（改动只会影响本包）
    writeFileSync(
      path.join(pkgDir, "src", "types.ts"),
      [
        "// 本包自己的类型 —— 改动只会触发本包重建",
        "export interface Entity {",
        "  id: string;",
        "  name: string;",
        "  amount: number;",
        "  tags: string[];",
        "  meta: { createdAt: string; updatedAt: string };",
        "}",
      ].join("\n"),
    );

    for (let f = 0; f < N_FILES; f++) {
      const lines = [
        `import type { Entity } from "./types.js";`,
        "",
        `export function handle${f}(e: Entity): string {`,
        `  return e.id + ":" + e.name + ":" + e.amount + ":" + e.tags.length + ":" + e.meta.createdAt;`,
        `}`,
        "",
        `export const sample${f}: Entity = {`,
        `  id: "e${p}-${f}",`,
        `  name: "entity ${p} ${f}",`,
        `  amount: ${f},`,
        `  tags: ["t${f}"],`,
        `  meta: { createdAt: "2026-01-01", updatedAt: "2026-01-02" },`,
        `};`,
      ];
      writeFileSync(path.join(pkgDir, "src", `f${f}.ts`), lines.join("\n"));
    }
    refs.push({ path: `./packages/p${p}` });
  }
  writeFileSync(path.join(dir, "tsconfig.json"), ROOT_TSCONFIG(refs));
  writeFileSync(path.join(dir, "package.json"), PKG_JSON("layered"));
}

buildGodTypes();
buildLayered();
console.log(`generated ${N_PKGS} pkgs x ${N_FILES} files x 2 variants (godtypes / layered)`);
