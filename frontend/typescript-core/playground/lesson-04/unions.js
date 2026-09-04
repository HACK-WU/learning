"use strict";
// 课 4 · 知识点 1：联合类型
let orderStatus = "pending";
orderStatus = "paid";
// orderStatus = "shipped"; // ❌ 见 unions-probe.ts
// ② 联合上的属性访问：只能访问所有成员都有的
function format(id) {
    return id.toString(); // ✅ string 和 number 都有 toString
    // return id.toUpperCase(); // ❌ number 上没有
}
function handle(r) {
    if (r.ok) {
        return r.data.join(", "); // ✅ 这个分支里 r 收窄为 { ok: true; data: string[] }
    }
    return `failed: ${r.error}`; // ✅ 收窄为 { ok: false; error: string }
}
const row = { id: "u1", score: 98, createdAt: "2026-09-01" };
console.log(orderStatus, format(42));
console.log(handle({ ok: true, data: ["a", "b"] }));
console.log(handle({ ok: false, error: "timeout" }));
console.log(row);
