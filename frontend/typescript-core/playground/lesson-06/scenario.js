"use strict";
// 课 6 · 第四幕：同一份后端数据，三种处理方式的结局对比
// 后端把 amount 从数字改成了字符串，接口文档没更新
const response = '{"id":"o1","amount":"99"}';
const raw = JSON.parse(response);
// 方式一：as 断言 —— 第一幕的做法
function byAssertion(input) {
    const order = input;
    try {
        return `as        -> ${order.amount.toFixed(2)}`;
    }
    catch (e) {
        return `as        -> 崩溃: ${e.message}`;
    }
}
// 方式二：unknown + 收窄 —— 编译期逼你处理每一种可能
function byNarrowing(input) {
    if (typeof input === "object" && input !== null) {
        const candidate = input;
        if (typeof candidate.amount === "number") {
            return `narrowing -> ${candidate.amount.toFixed(2)}`;
        }
        return `narrowing -> amount 不是数字（实际是 ${typeof candidate.amount}）`;
    }
    return "narrowing -> 不是对象";
}
// 方式三：边界校验 —— 一次校验，边界之内处处安全
function parseOrder(input) {
    if (typeof input !== "object" || input === null)
        return null;
    const candidate = input;
    if (typeof candidate.id !== "string")
        return null;
    if (typeof candidate.amount !== "number")
        return null;
    return { id: candidate.id, amount: candidate.amount };
}
function byValidation(input) {
    const order = parseOrder(input);
    if (order === null)
        return "validation -> 拒绝接收（数据不符合契约）";
    return `validation -> ${order.id} ${order.amount.toFixed(2)}`;
}
console.log(byAssertion(raw));
console.log(byNarrowing(raw));
console.log(byValidation(raw));
console.log(byValidation(JSON.parse('{"id":"o2","amount":199}')));
