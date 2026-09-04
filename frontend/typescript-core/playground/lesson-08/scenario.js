"use strict";
// 课 8 · 第四幕：把订单工具函数库改成泛型版
// ① 取第一个元素 —— 不用 any，类型信息完整保留
function first(list) {
    if (list.length === 0)
        throw new Error("empty list");
    return list[0];
}
// ② 按 key 批量取值 —— key 拼错会被当场拦住
function pluck(list, key) {
    return list.map((item) => item[key]);
}
function ok(data) {
    return { code: 0, message: "ok", data };
}
const orders = [
    { id: "o1", amount: 100, status: "paid" },
    { id: "g1", amount: 80, status: "pending" },
];
const head = first(orders); // Order（不是 any）
const ids = pluck(orders, "id"); // string[]
const amounts = pluck(orders, "amount"); // number[]
const response = ok(orders); // ApiResponse<Order[]>
console.log("head.id        =", head.id);
console.log("ids            =", ids);
console.log("amounts        =", amounts);
console.log("response       =", response.code, response.data.length);
console.log("total          =", amounts.reduce((a, b) => a + b, 0));
