# 第 10 课：tsconfig 与编译配置

> 所属阶段：阶段 4《工程化与类型声明》｜ 水平：零基础 TS
> 本课知识点：TS7 的新默认与硬错误、目标与模块配置、严格性开关族与渐进收紧、构建性能与项目引用
> 故事情节：主角照着网上的老教程配 `tsconfig.json`，结果一路红灯——**TS 7 把一批默认值改了，旧选项直接变硬错误**
> ✅ 状态：⬜ 待编写 ｜ 实操环境：Node.js v22.14.0 + TypeScript 7.0.2

## 🎯 本课目标

- 说出 TS 7 改了哪些默认值、哪些选项变成硬错误，并给出老项目的迁移路径
- 为自己的运行环境选出 `target` / `module` / `moduleResolution` 组合，说清 `nodenext` 与 `bundler` 的取舍
- 用 `--build` 做增量构建，用 `--checkers` / `--builders` 调并行度，定位常见性能杀手

## 📌 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 1 | TS7 的新默认与硬错误 | `strict: true` 默认 / `rootDir: ./` 与 `types: []` 默认变化 / 被移除的旧选项 / 迁移路径 | ⬜ |
| 2 | 目标与模块配置 | `target` / `module` / `moduleResolution` 的取值与组合 / `nodenext` vs `bundler` 取舍 / `jsx` 配置点到为止 | ⬜ |
| 3 | 严格性开关族与渐进收紧 | `strict` 各子项 / `noUncheckedIndexedAccess` / `exactOptionalPropertyTypes` / 老项目渐进策略 | ⬜ |
| 4 | 构建性能与项目引用 | `--build` 增量 / `--checkers` `--builders` 并行 / `--singleThreaded` / 常见性能杀手与诊断 | ⬜ |

## 📦 前置依赖（JS 概念）

| 用到的 JS 概念 | 掌握要求 | 回补 |
|---------------|---------|------|
| ESM 与 CommonJS 的差异 | **需理解**（`module` / `moduleResolution` 建立在其上） | [JS 课 10 模块化](../javascript-core/02-课程目录.md)（未学 —— 本课给最小对比表） |
| `package.json` 与 npm 脚本 | 会用即可 | — |

## ⚠️ 事实核查要求（编写本课时必做）

本课内容**强时效**，编写前必须：

1. 跑 `npx tsc --version` 确认实际版本，与 [`00-学习档案.md`](../../00-学习档案.md) 的「版本事实基线」对照
2. 所有默认值 / 硬错误清单以 **TypeScript 官方博客 Announcing TypeScript 7.0（2026-07-08）** 为准
3. 每个新建的 `tsconfig.json` 都要**实测跑一遍**，不靠记忆写配置
4. 与基线不符之处就地更新档案并在文中标注 `（核查于 YYYY-MM）`

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
