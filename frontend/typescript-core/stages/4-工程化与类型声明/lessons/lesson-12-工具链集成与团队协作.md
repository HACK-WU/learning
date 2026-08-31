# 第 12 课：工具链集成与团队协作

> 所属阶段：阶段 4《工程化与类型声明》｜ 水平：零基础 TS
> 本课知识点：运行与构建工具分工、ESLint 与 typescript-eslint、类型检查进 CI 与团队规范
> 故事情节：项目构建飞快，类型却从头到尾没检查过一次——**CI 全绿，线上全红**
> ✅ 状态：⬜ 待编写 ｜ 实操环境：Node.js v22.14.0 + TypeScript 7.0.2

## 🎯 本课目标

- 分清 `tsc` / `tsx` / `ts-node` / esbuild / swc / Vite 的分工，知道哪一步会**悄悄跳过类型检查**
- 配好 TS 7 时代的 lint（7.0 无 API → 用 `@typescript/typescript6` 并存方案）
- 把 `tsc --noEmit` 接进 CI 与 pre-commit，并制定团队的类型严格度约定

## 📌 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 1 | 运行与构建工具分工 | `tsc` 检查 vs 转译 / `tsx`、`ts-node` / esbuild、swc、Vite 分工 / 别让类型检查被跳过 / JSDoc + `checkJs` 的轻量路线 | ⬜ |
| 2 | ESLint 与 typescript-eslint | TS 7 无 API → `@typescript/typescript6` 并存方案 / 类型感知 lint / 与 `tsc` 的分工 | ⬜ |
| 3 | 类型检查进 CI 与团队规范 | `--noEmit` / pre-commit / 类型严格度的团队约定 / 代码评审时看什么 | ⬜ |

## 📦 前置依赖（JS 概念）

| 用到的 JS 概念 | 掌握要求 | 回补 |
|---------------|---------|------|
| npm scripts 与 `package.json` | 会用即可 | — |
| `tsconfig` 配置 | **强依赖** | 课 10 ✅ |
| 模块与 `@types` | **强依赖** | 课 11 ✅ |

## ⚠️ 事实核查要求（编写本课时必做）

- 工具链生态**变化极快**（tsx / ts-node / esbuild / swc / Vite 的版本与 TS 7 兼容状态）→ 必须联网核查当前兼容情况并标注 `（核查于 YYYY-MM）`
- **typescript-eslint 与 TS 7 的并存方案**是官方公告明确给出的（`typescript@npm:@typescript/typescript6` 别名 + `@typescript/native`），编写时以官方公告为准并实测
- 拿不准的兼容性一律标 `⏳ 置信度：低`，不写死结论

---

<!-- 以下正文由 Phase 2 按五幕叙事骨架填充 -->

## 第一幕：起源与场景引入

（待填充）

## 第二幕：认知冲突

（待填充）

## 第三幕：层层揭示

（待填充）

## 第四幕：实操验证

（待填充）

## 第五幕：体系收束

（待填充）
