"use strict";
// 课 3 · 知识点 3：边界探测（as 能做什么、不能做什么）
// A：as 能屏蔽「属性缺失」—— 这是它最危险的地方
const a = { method: "GET" }; // 缺 url，不报错
const aUrl = a.url; // 编译通过，运行时却是 undefined
console.log("a.url =", aUrl);
// B：类型注解会检查缺失
const b = { method: "GET" };
// C：satisfies 也会检查缺失
const c = { method: "GET" };
// D：as 挡不住「属性类型冲突」
const d = { method: "GET", url: 123 };
// E：双重断言：绕过一切检查（危险信号）
const e = { method: "GET", url: 123 };
// F：完全无关的类型之间断言
const f = "hello";
// G：注解 vs satisfies —— 字面量类型还留着吗？
const g1 = { method: "GET", url: "/x" };
const g2 = { method: "GET", url: "/x" };
const gm1 = g1.method;
const gm2 = g2.method;
// H：多余属性，三种写法各怎么处理？
const h1 = { method: "GET", url: "/x", extra: 1 };
const h2 = { method: "GET", url: "/x", extra: 1 };
const h3 = { method: "GET", url: "/x", extra: 1 };
console.log(a, b, c, d, e, f, gm1, gm2, h1, h2, h3);
