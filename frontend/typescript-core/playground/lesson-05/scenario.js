"use strict";
// 课 5 · 第四幕：订单处理流程的三类输入，全部管住
// 穷尽性检查的兜底函数
function assertNever(value) {
    throw new Error(`unhandled status: ${String(value)}`);
}
// ① 漏一个分支就编译不过（第一幕里静默返回 undefined）
function nextStatus(status) {
    switch (status) {
        case "pending":
            return "paid";
        case "paid":
            return "refunded";
        case "refunded":
            return "refunded";
        default:
            return assertNever(status);
    }
}
// ② 类型守卫：外部数据先过守卫，再进业务逻辑
function isOrder(value) {
    if (typeof value !== "object" || value === null)
        return false;
    const candidate = value;
    return (typeof candidate.id === "string" &&
        typeof candidate.amount === "number" &&
        (candidate.status === "pending" ||
            candidate.status === "paid" ||
            candidate.status === "refunded"));
}
// 第一幕里这里会因为 result 是 null 而炸
function describeResult(result) {
    if (typeof result === "string")
        return `error: ${result}`;
    if (isOrder(result))
        return `ok: ${result.amount}`;
    return "unknown result"; // null / 其他形状被这里接住
}
// ③ 用显式判断替代真值检查，0 不再被误伤
function discountLabel(count) {
    if (count === undefined)
        return "no count";
    return `count = ${count}`;
}
console.log("nextStatus(pending) =", nextStatus("pending"));
console.log("describeResult(order) =", describeResult({ id: "o1", amount: 99, status: "pending" }));
console.log("describeResult(timeout) =", describeResult("timeout"));
console.log("describeResult(null) =", describeResult(null));
console.log("discountLabel(0) =", discountLabel(0));
console.log("discountLabel(3) =", discountLabel(3));
