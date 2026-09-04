"use strict";
// 课 4 · 知识点 2：字面量类型与模板字面量类型
// ① 字面量类型的三种来源
const fromConst = "pending"; // const 推导为 "pending"
const fromAsConst = ["a", "b"]; // as const 把每个值都锁成字面量
let fromAnnotation = "paid"; // 显式标注
const handler = "onclick";
const corner = "top-left";
const upper = "PENDING";
const capped = "Pending";
const id1 = "u-1001";
// const id2: UserId = "x-1001"; // ❌ 见 literals-probe.ts
console.log(fromConst, fromAsConst, fromAnnotation, handler, corner, upper, capped, id1);
