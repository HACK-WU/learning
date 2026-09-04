"use strict";
// 课 9 · 知识点 1：映射类型 —— 类型的 map
const draft = { id: "o1" }; // ✅ 只填一部分
const full = { id: "o1", amount: 100, status: "pending" };
const editable = { id: "o1", amount: 100, status: "paid" };
const summary = { id: "o1", amount: 100 };
const labels = { pending: "PENDING", paid: "PAID", refunded: "REFUNDED" };
console.log(draft, full, editable, summary, labels);
