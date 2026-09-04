"use strict";
// 课 9 · 知识点 3：内置工具类型全景与手写实现
// ── 逐个用一遍 ────────────────────────────────────────
const draft = { id: "o1" };
const complete = { id: "o1", amount: 100, status: "pending", note: "" };
const frozen = { id: "o1", amount: 100, status: "paid" };
const summary = { id: "o1", amount: 100 };
const withoutNote = { id: "o1", amount: 100, status: "pending" };
const labels = { pending: "PENDING", paid: "PAID" };
const statuses = "pending";
const paidOnly = "paid";
const clean = "text";
function createOrder(id, amount) {
    return { id, amount, status: "pending" };
}
async function loadOrder() {
    return createOrder("o1", 100);
}
const created = { id: "o1", amount: 100, status: "pending" };
const args = ["o1", 100];
const loaded = { id: "o1", amount: 100, status: "paid" };
console.log(draft, complete, frozen, summary, withoutNote, labels);
console.log(statuses, paidOnly, clean, created, args, loaded);
