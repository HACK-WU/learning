"use strict";
// 课 2 · 知识点 2：数组、元组与只读
const scores = [98, 76, 89];
const names = ["Alice", "Bob"]; // 与 string[] 完全等价
// 元组：CSV 的一行，长度固定、每列类型各自独立
const row = ["Alice", 98];
const cell0 = row[0]; // 第一格一定是 string
const cell1 = row[1]; // 第二格一定是 number
const r1 = ["u1", 98];
const r2 = ["u2", 76, "late"];
const header = ["scores", 1, 2, 3];
// 只读数组
const STATUS = ["pending", "paid", "refunded"];
const mutable = [1, 2, 3];
const readonlyView = mutable; // ✅ 可变 → 只读，允许
// as const：把每个值都锁成字面量类型
const frozen = ["pending", "paid", "refunded"];
const config = { mode: "dev", retries: 3 };
console.log(scores, names, row, cell0, cell1, r1, r2, header);
console.log(STATUS, mutable, readonlyView, frozen, config);
