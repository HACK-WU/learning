"use strict";
// 课 8 · 知识点 2：泛型约束与 keyof
const k1 = "id";
const k2 = "amount";
const idValue = "o1";
// ③ 用 extends 约束类型参数：K 必须是 T 的键
function getField(obj, key) {
    return obj[key];
}
const order = { id: "o1", amount: 100, status: "paid" };
const id = getField(order, "id"); // string
const amount = getField(order, "amount"); // number
// getField(order, "nmae");   // ❌ 拼错会被拦住，见 constraints-probe.ts
// ④ 批量取值：第一幕那个 pluck 的泛型版
function pluck(list, key) {
    return list.map((item) => item[key]);
}
const ids = pluck([order], "id"); // string[]
const amounts = pluck([order], "amount"); // number[]
function logId(item) {
    return item.id; // ✅ 因为 T 一定有 id
}
console.log(k1, k2, idValue, id, amount, ids, amounts, logId(order));
