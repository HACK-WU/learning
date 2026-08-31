# 第 11 课：错误处理与调试

> 所属阶段：阶段 4《工程化与运行时》｜ 水平：入门 ｜ 本课知识点：Error 体系与 throw、try·catch·finally 与异步错误、调试工具链与 Source Map
> 故事情节：主角给异步代码包了 `try...catch`，线上照样崩——因为 `try` 抓不到异步里的错。这一课建立"同步 / 异步"两套错误捕获的分工意识
> ⏳ **状态：骨架（正文待 Phase 2 填充）**

## 🎯 本课目标

- 区分 `TypeError` / `RangeError` / `SyntaxError` 等内置错误类型，用 `cause` 串起错误链
- 解释 `finally` 的覆盖行为，为 `unhandledrejection` 写全局兜底，说清**什么时候该 catch、什么时候该往上抛**
- 说出 `console.log` 调试的三个坑，用 `debugger` 和断点定位问题，说清生产环境 Source Map 的取舍

## 📌 知识点清单（含关键点）

### 知识点 1：Error 体系与 throw

- 关键点：`Error`·`TypeError`·`RangeError`·`SyntaxError`·`ReferenceError` 各自何时抛出 / `error.stack` 与 `Error.cause`（错误链）/ 自定义错误类（`instanceof` 为何会失效及修复）/ `throw` 什么才有用（抛原始值的坑）

### 知识点 2：try·catch·finally 与异步错误

- 关键点：`finally` 的**覆盖行为**（`return` 被覆盖）/ `try...catch` **只能捕获同步错误**（回扣课 7 事件循环：异步回调在另一个 tick）/ Promise 错误的捕获（`.catch` / `await` + `try`）/ 全局兜底 `onerror` 与 `unhandledrejection` / 错误边界：什么时候该 catch、什么时候该往上抛

### 知识点 3：调试工具链与 Source Map

- 关键点：`console` 的正确用法与三个坑（保留对象引用、生产环境性能、`console.log` 改变时序）/ `debugger` 与条件断点 / Node 内置调试器（`node --inspect`）/ Source Map 原理与生产环境策略（不上传 vs 不上线）

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课：

```
继续学 JavaScript 语言核心（ES6+）。我的学习档案在 frontend/javascript-core/00-学习档案.md，
刚学完阶段 4《工程化与运行时》的课《错误处理与调试》三个知识点
（Error 体系与 throw / try·catch·finally 与异步错误 / 调试工具链与 Source Map），
请按大纲继续讲解下一课《内存·性能与选型收束》。
```
