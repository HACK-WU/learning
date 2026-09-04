# 综合实战项目：schema-guard（类型安全的运行时校验器）

> 所属课程：[TypeScript](../../02-课程目录.md) ｜ Phase 3 结课实战项目
> 实测环境：**Node.js v22.14.0 + TypeScript 7.0.2**

## 一句话需求

**造一个「从 schema 推导 TypeScript 类型、并在运行时真正校验数据」的迷你校验器** —— 你给它一份 schema，它同时给你两样东西：一个**编译期类型**（不用手写 interface）和一个**运行时校验函数**（真正去检查外部数据）。

```ts
const userSchema = object({
  name: string(1),
  age: number(0),
  tags: array(string()),
});

const result = parse(userSchema, await fetchJson());
if (result.ok) {
  result.value.name; // ← 类型是 string，从 schema 推出来的，不是手写的
} else {
  result.errors; // ← [{ path: "age", message: "expected number, got string" }]
}
```

## 为什么是这个项目

它是 15 课的**交汇点**，而且每一处都是被真实约束逼出来的，没有"为了用而用"：

- **校验结果必须是判别式联合**，否则调用方可以不处理失败（阶段 2）
- **校验函数必须是类型守卫 / 断言函数**，否则 `unknown` 收窄不了（阶段 2）
- **类型从 schema 推导**，否则 schema 和 interface 两份定义会慢慢不同步（阶段 3）
- **`declaration` + `types` 决定了对外的契约面**（阶段 4）
- **类型推导体操到底值不值得写** —— 这是课 13 的题眼，本项目必须正面回答（阶段 5）

更重要的是：**它刚好落在 TypeScript 的能力边界上**。类型系统能替你推导类型，但**它管不住外部数据** —— 这正是课 6「信任边界」和课 15「该不该上 TS」共同指向的那条线。本项目把这条线画成了一个能跑的东西。

## 🎯 目标：做完后你应该能

1. 说清为什么「`as` 断言」挡不住外部数据，以及在边界处该用什么替代
2. 解释判别式联合 + 穷尽性检查是怎么把「漏处理一种情况」变成编译错误的
3. 判断一个类型体操场景该不该写（用课 13 的七步标准，而不是凭感觉）
4. 面对「库要不要依赖环境类型」「失败该抛异常还是返回值」这类问题，先问**使用场景**再选

## 🗺️ 覆盖知识点地图

> 这是「跨阶段整合」的证据，不是装饰。**每一行都能在 `实现/` 里找到对应的代码位置。**

### 阶段 1《类型思维启蒙》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 1 TS 的本质](../../stages/1-类型思维启蒙/lessons/lesson-01-TypeScript到底是什么.md) | 擦除式类型超集 | 全程：schema 是运行时的**值**，类型推导是编译期的**结果**；`tsc` 产物里 schema 留下、类型消失 |
| [课 2 基础类型标注与推导](../../stages/1-类型思维启蒙/lessons/lesson-02-基础类型标注与推导.md) | 类型标注与推导 | ★ `src/index.ts` 只标注**公开 API 边界**，函数体内部大量依赖推导 |
| [课 2 基础类型标注与推导](../../stages/1-类型思维启蒙/lessons/lesson-02-基础类型标注与推导.md) | 数组与只读 | `ParseResult` 的 `errors: readonly ParseError[]`；所有 schema 字段都是 `readonly` |
| [课 3 对象类型与结构化类型](../../stages/1-类型思维启蒙/lessons/lesson-03-对象类型与结构化类型.md) | interface 与 type | ★ `src/schema.ts` 用 interface 定义各种 schema；`src/infer.ts` 用 type 做推导 |
| [课 3 对象类型与结构化类型](../../stages/1-类型思维启蒙/lessons/lesson-03-对象类型与结构化类型.md) | 类型断言 | ★ `src/parse.ts` 里唯一那处 `as Infer<S>` —— 集中在边界、且被测试覆盖 |

### 阶段 2《收窄与控制流》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 4 联合类型与字面量类型](../../stages/2-收窄与控制流/lessons/lesson-04-联合类型与字面量类型.md) | 判别式联合 | ★ `Schema`（`kind` 做判别式）与 `ParseResult`（`ok` 做判别式） |
| [课 5 类型收窄](../../stages/2-收窄与控制流/lessons/lesson-05-类型收窄.md) | 自定义类型守卫 | ★ `is(schema, value): value is Infer<S>` |
| [课 5 类型收窄](../../stages/2-收窄与控制流/lessons/lesson-05-类型收窄.md) | 断言函数 | ★ `assert(schema, value): asserts value is Infer<S>`；`parseOrThrow` 靠它收窄 |
| [课 5 类型收窄](../../stages/2-收窄与控制流/lessons/lesson-05-类型收窄.md) | 穷尽性检查 | ★ `src/check.ts` 与 `src/schema.ts` 的 `default` 分支都是 `const _exhaustive: never = schema` |
| [课 6 any·unknown·never 与信任边界](../../stages/2-收窄与控制流/lessons/lesson-06-any·unknown·never与信任边界.md) | **信任边界** | ★ 整个项目的立意：`unknown` 进来 → 校验 → 变成可靠的类型 |
| [课 6 any·unknown·never 与信任边界](../../stages/2-收窄与控制流/lessons/lesson-06-any·unknown·never与信任边界.md) | never | 穷尽性检查的落点 |
| [课 7 类与接口的类型世界](../../stages/2-收窄与控制流/lessons/lesson-07-类与接口的类型世界.md) | class 与 implements | `src/errors.ts` 的 `class SchemaGuardError extends Error`（写 `this.name`） |

### 阶段 3《泛型与类型编程》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 8 泛型基础](../../stages/3-泛型与类型编程/lessons/lesson-08-泛型基础.md) | 泛型函数与推导 | ★ `parse<S extends Schema>(schema: S, ...): ParseResult<Infer<S>>` |
| [课 8 泛型基础](../../stages/3-泛型与类型编程/lessons/lesson-08-泛型基础.md) | 泛型约束 | `array<S>` / `object<F>` 的 builder；`noUncheckedIndexedAccess` 下的边界防护 |
| [课 9 类型编程三件套](../../stages/3-泛型与类型编程/lessons/lesson-09-类型编程三件套与内置工具类型.md) | 条件类型与 infer | ★ `src/infer.ts` 的 `Infer<S>`（本项目唯一的类型体操） |
| [课 9 类型编程三件套](../../stages/3-泛型与类型编程/lessons/lesson-09-类型编程三件套与内置工具类型.md) | 映射类型 | ★ `Infer<S>` 的 object 分支用映射类型遍历 `fields` |

### 阶段 4《工程化与类型声明》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 10 tsconfig 与编译配置](../../stages/4-工程化与类型声明/lessons/lesson-10-tsconfig与编译配置.md) | **tsconfig 与严格性开关** | ★ `tsconfig.json`：开了 `noUncheckedIndexedAccess` 与 `exactOptionalPropertyTypes`（课 10 说这两个默认关、是官方额外推荐） |
| [课 10 tsconfig 与编译配置](../../stages/4-工程化与类型声明/lessons/lesson-10-tsconfig与编译配置.md) | 命令行行为变化 | `test/depth.cjs` 里踩到 **TS5112**（有 tsconfig 时不能传文件路径，需 `--ignoreConfig`） |
| [课 11 模块与声明文件](../../stages/4-工程化与类型声明/lessons/lesson-11-模块与声明文件.md) | **types 与 lib** | ★ `tsconfig.src.json` 用 `types: []` + `lib: ["esnext"]` 验证库的环境无关性；默认配置的 `types: ["node"]` 是为了 `console` / `node:assert`（课 11 实测：`console` 在 `lib.dom`，Node 项目靠 `@types/node`） |
| [课 11 模块与声明文件](../../stages/4-工程化与类型声明/lessons/lesson-11-模块与声明文件.md) | `.d.ts` 与导出边界 | ★ `src/index.ts` 刻意只导出必要的东西 —— 因为 `declaration: true` 会把对外签名用到的类型都写进 `.d.ts` |
| [课 12 工具链集成与团队协作](../../stages/4-工程化与类型声明/lessons/lesson-12-工具链集成与团队协作.md) | **类型检查进 CI** | ★ `package.json` 的 `ci` 脚本：`typecheck && typecheck:lib && test`，类型检查是独立且可见的一步 |

### 阶段 5《深入与架构》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 13 类型体操进阶](../../stages/5-深入与架构/lessons/lesson-13-类型体操进阶.md) | **类型体操值不值** | ★ `设计决策.md` 决策点 2：用课 13 的七步放弃标准逐条过 `Infer<S>`；`test/cost.cjs` 实测推导 vs 手写 interface 的编译期代价（0.87x，测不出差异） |
| [课 13 类型体操进阶](../../stages/5-深入与架构/lessons/lesson-13-类型体操进阶.md) | 递归深度限制 | ★ `test/depth.cjs` 实测：**实例化 >1000 层，结构比较约 100 层后报 TS2321**（不是 TS2589） |
| [课 13 类型体操进阶](../../stages/5-深入与架构/lessons/lesson-13-类型体操进阶.md) | 类型测试 | `test/types.test.ts` 用 `Equals` + 负向对照，把推导结果钉死 |
| [课 14 编译器原理](../../stages/5-深入与架构/lessons/lesson-14-编译器原理与类型检查机制.md) | Checker 惰性求值 | 深度测量必须**强制求值**才测得准（否则测不出差别）—— 这正是课 14 引的官方原文 |
| [课 14 编译器原理](../../stages/5-深入与架构/lessons/lesson-14-编译器原理与类型检查机制.md) | 读报错结构 | TS2321 / TS2589 / TS5112 / TS2591 / TS2584 五个码在本项目里全部真实出现过，逐条定位过 |
| [课 15 大型项目类型架构](../../stages/5-深入与架构/lessons/lesson-15-大型项目类型架构与选型收束.md) | **类型的分层与放置** | ★ `src/` 内部按职责分层（`result` / `errors` / `schema` / `infer` / `parse` / `index`），`check()` 不对外暴露 |
| [课 15 大型项目类型架构](../../stages/5-深入与架构/lessons/lesson-15-大型项目类型架构与选型收束.md) | 公开 API 与版本兼容 | ★ `src/index.ts` 的导出边界；`objectSchema` 的字段是"必填"设计 → 新增字段即破坏性变更（课 15 实测 TS2741） |
| [课 15 大型项目类型架构](../../stages/5-深入与架构/lessons/lesson-15-大型项目类型架构与选型收束.md) | **类型管不住外部数据** | ★ 本项目存在的全部理由；`test/run.ts` 最后一条断言就是它 |

**覆盖统计**：**5 个阶段 / 15 课全部涉及**。其中 ★ 标记的 12 处是核心落点。
**关联最弱的是课 1 与课 7** —— 课 1 的结论（类型被擦除）是前提而非落点；课 7 只用到一处 `class extends Error`，类的修饰符 / 抽象类 / `this` 类型在本项目里没有自然落点，**不硬凑**。

## ✅ 复杂度四门槛自检

| # | 门槛 | 达标情况 |
|---|------|---------|
| 1 | **跨阶段整合 ≥3 个阶段** | ✅ 覆盖 **5 个阶段**（上表逐条回指到课，全部带文件链接） |
| 2 | **非功能约束 ≥2 项** | ✅ 4 项：**错误处理**（不短路、带路径、`SchemaGuardError` + `name`）、**可观测性**（错误路径精确到 `profile.level` 这种层级）、**规模边界**（嵌套深度实测，见 `test/depth.cjs`）、**环境无关性**（`tsconfig.src.json` 的 `types: []` 闸门） |
| 3 | **真权衡决策 ≥2 个** | ✅ **3 个**，每个写成五段式，见 [`设计决策.md`](设计决策.md) |
| 4 | **规模：多文件工程** | ✅ 7 个源码模块 + 2 个示例 + 2 个测试（运行时 + 类型）+ 2 个测量脚本（depth / cost） |

## 🚀 运行方式

```bash
cd 实现

npm install          # 只需要 typescript + @types/node

npm run ci           # 一道到底：typecheck → typecheck:lib → test
npm test             # 17 条断言
npm run demo         # 7 个场景的演示
npm run bad          # 反例（会以 exit 0 正常结束 —— 这才可怕）
```

**预期结果**：

- `npm run ci` → 两个 typecheck 均 exit 0，测试输出 `17 通过 / 0 失败`
- `npm run demo` → 7 个场景的输出
- `npm run bad` → 7 条 BAD 标记，最后一行提示「只看能不能跑，一条问题都发现不了」

## 📁 目录说明

```
schema-guard/
├── README.md            本文件：需求 / 目标 / 知识点地图 / 运行方式
├── 设计决策.md           3 个真权衡点（五段式）
├── 反例对照.md           「能跑但很糟」的写法，逐条对比（7 条）
├── 验收清单.md           自测项：怎么确认自己真的做成了
└── 实现/
    ├── package.json     只依赖 typescript + @types/node
    ├── tsconfig.json        开发/测试/CI 用：types: ["node"]
    ├── tsconfig.src.json    ★ 库的纯净度闸门：types: [] + noEmit
    ├── src/
    │   ├── result.ts        ParseResult 判别式联合（阶段 2）
    │   ├── errors.ts        SchemaGuardError（阶段 2/4）
    │   ├── schema.ts        Schema 判别式联合 + builders + describe 穷尽性（阶段 2）
    │   ├── check.ts         运行时校验核心：递归 + 不短路 + 穷尽性（阶段 2/5）
    │   ├── infer.ts         Infer<S> 类型推导 + 深度边界实测记录（阶段 3/5）
    │   ├── parse.ts         校验入口：类型守卫 / 断言函数（阶段 2/3）
    │   └── index.ts         公开 API 边界（阶段 5）
    ├── examples/
    │   ├── demo.ts              7 个场景
    │   └── bad-schema-guard.ts  反例（BAD 1~7）
    └── test/
        ├── run.ts          17 条运行时断言（node:assert，零测试框架）
        ├── types.test.ts    类型测试：Equals + 负向对照
        ├── depth.cjs        Infer 的嵌套深度实测（阶段 5 课 13 边界）
        └── cost.cjs         类型推导 vs 手写 interface 的编译期代价实测（决策点 2）
```

## 🧭 建议的使用顺序

1. **先自己写**：只看上面的「一句话需求」，自己动手写一遍（哪怕写得很糟）
2. **跑反例**：`npm run bad`，读 [`反例对照.md`](反例对照.md)，先看自己能指出几条
3. **对设计决策**：读 [`设计决策.md`](设计决策.md)，**先不看结论**，自己想「我会怎么选」，再对照 —— 这一步是本项目价值最高的部分
4. **读实现**：带着问题看 `src/` 下的六个文件（关键处都标了对应哪一课）
5. **验收**：`npm test`，再按 [`验收清单.md`](验收清单.md) 逐项自测

> 💡 顺序很重要：**先看参考实现 = 把"设计"这道题变成了"抄写"**。

---

## 🧭 这个项目在整门课里的位置

```
阶段 1 类型思维启蒙 ─┐
阶段 2 收窄与控制流 ─┤
阶段 3 泛型与类型编程 ─┼──→ 【本项目】把散装知识点焊成「能做出一个完整东西」的能力
阶段 4 工程化与类型声明 ─┤
阶段 5 深入与架构 ──────┘              │
                                        ↓
                          Phase 4 课程手册汇总
                                        ↓
                    Phase 5 实战经验 + 排障速查手册 + 场景解法库
```

**做完这个项目之后，按流程的下一步是**：

```
继续学 TypeScript。我的学习档案在 frontend/typescript-core/00-学习档案.md，
已完成 Phase 3 综合实战项目《schema-guard》（projects/schema-guard/）。
请按流程进入 Phase 4，汇总生成课程手册。
```

**如果你想先自己加练**，[`验收清单.md`](验收清单.md) 的 **L3 · 改得动** 里有 6 个改造挑战（加 union、加 optional 字段、加自定义校验、加路径别名的取舍等），每一个都对应一个真实的工程决策。
