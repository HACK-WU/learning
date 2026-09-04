"use strict";
// 课 4 · 第四幕：给订单状态机加上类型
// ② 需要遍历 / 校验时，从常量数组生成同一份联合（索引访问类型，课 9 展开）
const ORDER_STATUS = ["pending", "paid", "refunded"];
// 状态流转：写漏一个分支，返回值就不完整（穷尽性检查见课 5）
function nextStatus(status) {
    switch (status) {
        case "pending":
            return "paid";
        case "paid":
            return "refunded";
        case "refunded":
            return "refunded";
    }
}
function describe(order) {
    switch (order.status) {
        case "pending":
            return `${order.id}: pending ${order.amount}`;
        case "paid":
            return `${order.id}: paid at ${order.paidAt}`;
        case "refunded":
            return `${order.id}: refunded at ${order.refundedAt}`;
    }
}
// ④ 外部进来的字符串：先运行时校验，再断言成 OrderStatus
function toStatus(raw) {
    return ORDER_STATUS.includes(raw) ? raw : null;
}
const orders = [
    { status: "pending", id: "o1", amount: 99 },
    { status: "paid", id: "o2", amount: 199, paidAt: "2026-09-01" },
    { status: "refunded", id: "o3", amount: 299, refundedAt: "2026-09-02" },
];
for (const order of orders) {
    console.log(describe(order));
}
console.log("next(pending) =", nextStatus("pending"));
console.log("toStatus(PAID) =", toStatus("PAID"));
console.log("toStatus(paid) =", toStatus("paid"));
