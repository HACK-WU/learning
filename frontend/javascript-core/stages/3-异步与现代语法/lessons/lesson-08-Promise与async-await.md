# 第 8 课：Promise 与 async/await

> 所属阶段：阶段 3《异步与现代语法》｜ 水平：入门 ｜ 本课知识点：Promise 状态机、错误处理与组合方法、async/await
> 故事情节：主角用 `await` 写循环发 10 个请求，接口慢得离谱——因为 `await` 在循环里会退化成串行。搞懂"它是语法糖"，才知道怎么改成并发
> ⏳ **状态：骨架（正文待 Phase 2 填充）**

## 🎯 本课目标

- 说清 Promise 三态不可逆、`then` 返回新 Promise、值穿透与错误冒泡
- 区分 `all` / `allSettled` / `race` / `any` 的语义，并选出适合"允许部分失败"场景的那个
- 把串行的 `await` 循环改成并发；说清 `try...catch` 与 `.catch` 的取舍

## 📌 知识点清单（含关键点）

### 知识点 1：Promise 状态机

- 关键点：`pending`·`fulfilled`·`rejected` 三态**不可逆** / `then` 返回**新** Promise（链式调用的基础）/ 值穿透与错误冒泡 / `then` 的回调是**微任务**（回扣课 7）

### 知识点 2：错误处理与组合方法

- 关键点：`catch` 的**位置**决定捕获范围 / `Promise.all`·`allSettled`·`race`·`any` 的语义差异与选型 / `then` 的第二参数 vs `catch` / `unhandledrejection`

### 知识点 3：async/await

- 关键点：本质是 Promise 的**语法糖**（证据：返回值恒为 Promise）/ `await` 的暂停与恢复机制 / 串行 vs 并发的写法与性能差（`Promise.all` 改造）/ `try...catch` 与 `.catch` 的取舍 / 顶层 `await`（ESM 专属）

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课：

```
继续学 JavaScript 语言核心（ES6+）。我的学习档案在 frontend/javascript-core/00-学习档案.md，
刚学完阶段 3《异步与现代语法》的课《Promise 与 async/await》三个知识点
（Promise 状态机 / 错误处理与组合方法 / async·await），
请按大纲继续讲解下一课《现代语法与内置数据结构》。
```
