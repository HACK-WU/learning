# 第 7 课：事件循环

> 所属阶段：阶段 3《异步与现代语法》｜ 水平：入门 ｜ 本课知识点：单线程与调用栈、宏任务与微任务、事件循环全流程
> 故事情节：主角终于要正面回答开头那个问题了——`setTimeout(fn, 0)` 明明写的是 0 毫秒，为什么最后才执行？这一课拆开"JS 怎么处理时间"这台机器
> 📌 **前置约定**：本课讲微任务时会借用 `Promise.then` 的**外壳**举例（"它是微任务"），Promise 的完整机制留到课 8 展开
> ⏳ **状态：骨架（正文待 Phase 2 填充）**

## 🎯 本课目标

- 解释 JS 为什么是单线程，说出栈溢出的触发条件与阻塞的代价
- 对 `setTimeout` / `Promise.then` / `queueMicrotask` 正确归类为宏任务或微任务，并说出微任务的清空时机
- 推演任意 `setTimeout` + Promise 混合代码的输出顺序；解释为什么 `setTimeout(fn, 0)` 不是"立即执行"

## 📌 知识点清单（含关键点）

### 知识点 1：单线程与调用栈

- 关键点：为什么 JS 是单线程（动机与代价）/ 调用栈（`Call Stack`）与栈溢出 / 阻塞的代价 / 浏览器 Runtime 与 Node Runtime 的差异

### 知识点 2：宏任务与微任务

- 关键点：任务队列的**两级结构** / 哪些是宏任务（`setTimeout`·`setInterval`·I/O·UI 渲染）、哪些是微任务（`Promise.then`·`queueMicrotask`·`MutationObserver`）/ 微任务的清空时机 / `queueMicrotask`

### 知识点 3：事件循环全流程

- 关键点：一次 tick 的完整顺序（同步 → 清空微任务 → 取一个宏任务 → 再清空微任务）/ 经典输出顺序题的**通用推演方法** / `setTimeout(fn, 0)` 的真实含义 / 渲染时机与 `requestAnimationFrame`

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课：

```
继续学 JavaScript 语言核心（ES6+）。我的学习档案在 frontend/javascript-core/00-学习档案.md，
刚学完阶段 3《异步与现代语法》的课《事件循环》三个知识点
（单线程与调用栈 / 宏任务与微任务 / 事件循环全流程），
请按大纲继续讲解下一课《Promise 与 async/await》。
```
