# 综合实战项目：异步任务编排器

> 所属课程：[JavaScript 语言核心（ES6+）](../../02-课程目录.md) ｜ Phase 3 结课实战项目
> 实测环境：**Node.js v22.14.0**（零依赖，无需 `npm install`）

## 一句话需求

**造一个「能限制并发、能超时、能重试、会缓存」的异步任务编排器** —— 你给它一批异步任务，它负责在不超过并发上限的前提下把它们跑完，超时了能真正叫停，失败了按规则重试，重复的查询结果直接命中缓存。

## 为什么是这个项目

它是课程 12 课的**交汇点**：

- **并发控制**逼你用上闭包与 `this`（阶段 1、2）
- **超时与重试**逼你搞懂 Promise 组合与错误边界（阶段 3、4 课 8、课 11）
- **缓存**逼你在「方便」和「内存」之间做取舍（阶段 4 课 9、课 12）
- **多文件组织**逼你真正用一次 ESM（阶段 4 课 10）

换句话说：**它没有一个知识点是"为了用而用"的** —— 每一个都被一个真实的工程约束逼出来了。

## 🎯 目标：做完后你应该能

1. 说清 `Promise.race` 为什么**只能判定超时、不能取消任务**，以及 `AbortController` 补上了哪一半
2. 指出 `try...catch` 包在 `forEach` 外面为什么一个错都接不住，并给出正确写法
3. 解释为什么"缓存用 `Map` 却不限大小"就是内存泄漏，以及 `WeakMap` 什么时候才是更好的解
4. 面对"要不要上 TypeScript""选哪个运行时"这类问题，先问**约束**而不是先比工具

## 🗺️ 覆盖知识点地图

> 这是「跨阶段整合」的证据，不是装饰。**每一行都能在 `实现/` 里找到对应的代码位置。**

### 阶段 1《值与作用域》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 1 变量与类型](../../stages/1-值与作用域/lessons/lesson-01-变量与类型.md) | var·let·const 与 TDZ | 全部源码只用 `const`/`let`；`retry.js` 的 `for (let attempt...)` 每轮独立绑定 |
| [课 1 变量与类型](../../stages/1-值与作用域/lessons/lesson-01-变量与类型.md) | 类型检测 | `Number.isInteger(concurrency)`、`Number.isFinite(ms)` 做参数校验（`semaphore.js`/`timeout.js`/`retry.js`/`cache.js`） |
| [课 2 值的复制与比较](../../stages/1-值与作用域/lessons/lesson-02-值的复制与比较.md) | 原始值 vs 引用值 | `Semaphore` 的 `#active` 是原始值（改的是值）；`#waiting` 数组是引用值（操作的是同一个数组） |
| [课 3 作用域与闭包](../../stages/1-值与作用域/lessons/lesson-03-作用域与闭包.md) | **闭包** | ★ `semaphore.js` 的 `#makeRelease()` —— `released` 这个变量活在函数返回之后，用来防重复释放；`index.js` 的 `attempts` 计数同理 |
| [课 3 作用域与闭包](../../stages/1-值与作用域/lessons/lesson-03-作用域与闭包.md) | 词法作用域 | 私有字段 `#xxx` 的作用域边界（`semaphore.js`、`index.js`） |

### 阶段 2《函数与对象》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 4 函数是一等公民](../../stages/2-函数与对象/lessons/lesson-04-函数是一等公民.md) | 高阶函数 | ★ `run(task)` 把函数当参数传来传去；`#makeRelease()` 返回一个函数 |
| [课 4 函数是一等公民](../../stages/2-函数与对象/lessons/lesson-04-函数是一等公民.md) | 参数机制 | 全部 API 用「解构 + 默认值」：`{ concurrency = 4, timeout = null } = {}` |
| [课 5 this 到底指向谁](../../stages/2-函数与对象/lessons/lesson-05-this到底指向谁.md) | **this 的绑定规则** | ★ `semaphore.js` 用**箭头函数**返回释放回调，保证被谁拿着调用 `this` 都不丢；`demo.js` 场景 7 演示「把 `queue.run` 提取出来就炸」 |
| [课 6 原型与类](../../stages/2-函数与对象/lessons/lesson-06-原型与类.md) | class 与私有字段 | `#limit` / `#active` / `#waiting` / `#cache`；`class X extends Error` 继承链（`errors.js`） |

### 阶段 3《异步与现代语法》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 7 事件循环](../../stages/3-异步与现代语法/lessons/lesson-07-事件循环.md) | **事件循环** | ★ `timeout.js` 用 `Promise.resolve().then()` 包一层让任务在**微任务**里启动；并发调度的整个节奏都建立在事件循环上 |
| [课 8 Promise 与 async/await](../../stages/3-异步与现代语法/lessons/lesson-08-Promise与async-await.md) | Promise 组合方法 | ★ `Promise.race`（超时判定 / `stream` 的完成序）、`Promise.allSettled`（`runAll`） |
| [课 8 Promise 与 async/await](../../stages/3-异步与现代语法/lessons/lesson-08-Promise与async-await.md) | async/await | 全部异步代码；`async *stream()` 异步生成器 |
| [课 9 现代语法与内置数据结构](../../stages/3-异步与现代语法/lessons/lesson-09-现代语法与内置数据结构.md) | **Map 与保序** | ★ `cache.js` 用 Map 的**插入顺序**实现 LRU（先删再插 = 挪到队尾） |
| [课 9 现代语法与内置数据结构](../../stages/3-异步与现代语法/lessons/lesson-09-现代语法与内置数据结构.md) | Symbol.iterator | `cache.js` 的 `*[Symbol.iterator]()`，让缓存可被 `for...of` |
| [课 9 现代语法与内置数据结构](../../stages/3-异步与现代语法/lessons/lesson-09-现代语法与内置数据结构.md) | 生成器 | `index.js` 的 `async *stream(entries)` |
| [课 9 现代语法与内置数据结构](../../stages/3-异步与现代语法/lessons/lesson-09-现代语法与内置数据结构.md) | 可选链 / 空值合并 | `signal?.aborted`、`this.#cache?.has(key)`、`options.taskId ?? null` |
| [课 9 现代语法与内置数据结构](../../stages/3-异步与现代语法/lessons/lesson-09-现代语法与内置数据结构.md) | 解构 | 所有 API 的 options 解构 |

### 阶段 4《工程化与运行时》

| 课 | 知识点 | 用在哪 |
|---|---|---|
| [课 10 模块化](../../stages/4-工程化与运行时/lessons/lesson-10-模块化.md) | **ESM 模块化** | ★ 6 个模块各自 `export`，`index.js` 统一再导出；`package.json` 的 `"type": "module"` |
| [课 11 错误处理与调试](../../stages/4-工程化与运行时/lessons/lesson-11-错误处理与调试.md) | Error 体系与 throw | ★ `errors.js`：`TaskError` 基类 + 3 个子类，全部写 `this.name`（不写栈首行就显示成 `Error:`） |
| [课 11 错误处理与调试](../../stages/4-工程化与运行时/lessons/lesson-11-错误处理与调试.md) | **Error.cause 错误链** | ★ `retry.js`：重试耗尽时把最后一次的真实错误挂在 `cause` 上 |
| [课 11 错误处理与调试](../../stages/4-工程化与运行时/lessons/lesson-11-错误处理与调试.md) | try·catch·finally | ★ `semaphore.js` 的 `run()` 用 `finally` 保证名额一定归还（且 `finally` 里只做清理，不写 return/throw） |
| [课 11 错误处理与调试](../../stages/4-工程化与运行时/lessons/lesson-11-错误处理与调试.md) | **错误边界** | ★ `retry.js`：不可重试的错误**原样上抛**不包装；重试耗尽才加上下文再抛 |
| [课 12 内存·性能与选型收束](../../stages/4-工程化与运行时/lessons/lesson-12-内存性能与选型收束.md) | **内存泄漏 ②**（定时器/监听器） | ★ `timeout.js` 的 `finally { clearTimeout }`；`abortableSleep` 里 `removeEventListener` 解绑监听器 |
| [课 12 内存·性能与选型收束](../../stages/4-工程化与运行时/lessons/lesson-12-内存性能与选型收束.md) | **内存泄漏 ④**（无界容器） | ★ `cache.js` 强制有上限；`index.js` 里 `cacheMax=0` 表示"明确不缓存"而不是"无限缓存" |

**覆盖统计**：**4 个阶段 / 12 课全部涉及**。其中 ★ 标记的 8 处是**核心落点**（闭包、`this`、事件循环、Promise 组合、Map 保序、ESM、错误体系与边界、内存泄漏），其余为辅助印证。
**关联最弱的是课 2** —— 只用到了「原始值 vs 引用值」的区分，深浅拷贝在本项目里没有自然落点，不硬凑。

## ✅ 复杂度四门槛自检

| # | 门槛 | 达标情况 |
|---|------|---------|
| 1 | **跨阶段整合 ≥3 个阶段** | ✅ 覆盖 **4 个阶段**（上表逐条回指到课） |
| 2 | **非功能约束 ≥2 项** | ✅ 4 项：**性能**（并发上限 + 缓存）、**错误处理**（自定义错误 + cause + 边界）、**内存**（缓存有界 + 定时器/监听器清理）、**可维护性**（ESM 分模块 + 单一职责） |
| 3 | **真权衡决策 ≥2 个** | ✅ **3 个**，每个都写成五段式，见 [`设计决策.md`](设计决策.md) |
| 4 | **规模：多文件工程** | ✅ 6 个源码模块 + 2 个示例 + 1 个测试文件，见下方目录说明 |

## 🚀 运行方式

**零依赖** —— 不需要 `npm install`，也不会产生 `node_modules/`。

```bash
cd 实现

node test/run.js              # 验收测试：24 条断言，应全部通过
node examples/demo.js         # 演示：7 个场景，逐个对应知识点
node examples/bad-queue.js    # 反例：能跑但很糟的版本
```

（也可通过 `npm run test` / `npm run demo` / `npm run bad` 运行，见 `package.json`）

**预期结果**：`test/run.js` 输出 `24 通过 / 0 失败`；`demo.js` 跑完约 1.1 秒后正常退出。

## 📁 目录说明

```
异步任务编排器/
├── README.md           本文件：需求 / 目标 / 知识点地图 / 运行方式
├── 设计决策.md          3 个真权衡点（五段式：候选 → 选择 → 理由 → 代价 → 何时改选）
├── 反例对照.md          「能跑但很糟」的版本 + 逐条对比（7 条）
├── 验收清单.md          自测项：怎么确认自己真的做成了
└── 实现/
    ├── package.json    仅声明 ESM 与脚本，零依赖
    ├── src/
    │   ├── errors.js       自定义错误体系 + isRetryable 判定（课 11）
    │   ├── semaphore.js    并发闸门：闭包 + 私有字段 + 箭头函数（课 3/5/6）
    │   ├── timeout.js      超时：Promise.race + AbortController + 清理（课 8/11/12）
    │   ├── retry.js        重试：async + cause 链 + 错误边界（课 8/11）
    │   ├── cache.js        有界 LRU 缓存：Map 保序 + Symbol.iterator（课 9/12）
    │   └── index.js        TaskQueue：整合以上五个模块（课 4/5/9/10）
    ├── examples/
    │   ├── demo.js         7 个场景的可运行演示
    │   └── bad-queue.js    反例（含 BAD 1~7 标记）
    └── test/
        └── run.js          24 条断言（Node 内置 assert，零依赖）
```

## 🧭 建议的使用顺序

1. **先自己写**：只看这一页的「一句话需求」，自己动手写一遍（哪怕写得很糟）
2. **跑反例**：`node examples/bad-queue.js`，读 [`反例对照.md`](反例对照.md)，看你能不能自己指出问题
3. **对设计决策**：读 [`设计决策.md`](设计决策.md)，**先不看结论**，自己想「我会怎么选」，再对照
4. **读实现**：带着问题去看 `src/` 下的六个文件（关键处都标了对应哪一课）
5. **验收**：跑 `test/run.js`，再按 [`验收清单.md`](验收清单.md) 逐项自测

> 💡 顺序很重要：**先看参考实现 = 把"设计"这道题变成了"抄写"**。第 3 步那三个决策点，是本项目中价值最高的部分。

---

## 🧭 这个项目在整门课里的位置

```
阶段 1 值与作用域 ─┐
阶段 2 函数与对象 ─┤
阶段 3 异步与现代语法 ─┼──→ 【本项目】把散装知识点焊成「能做出一个完整东西」的能力
阶段 4 工程化与运行时 ─┘              │
                                      ↓
                        Phase 4 课程手册汇总（final-课程手册.md）
                                      ↓
                        Phase 5 实战经验 + 排障速查手册 + 场景解法库
```

**做完这个项目之后，按流程的下一步是**：

```
继续学 JavaScript 语言核心（ES6+）。我的学习档案在 frontend/javascript-core/00-学习档案.md，
已完成 Phase 3 综合实战项目《异步任务编排器》（projects/异步任务编排器/）。
请按流程进入 Phase 4，汇总生成课程手册（final-课程手册.md），并收录本实战项目。
```

**如果你想先自己加练**，[`验收清单.md`](验收清单.md) 的 **L3 · 改得动** 里有 6 个改造挑战（加 TTL、加优先级、改 API 契约等），每一个都对应一个真实的工程决策。
