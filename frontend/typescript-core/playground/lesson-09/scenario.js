"use strict";
// 课 9 · 第四幕：把第一幕的三个需求，用类型表达出来
const order = { id: "o1", amount: 100, status: "pending" };
// 需求一：部分更新 —— 键必须是 Order 的键，值类型还得对
function updateOrder(base, patch) {
    return { ...base, ...patch };
}
const updated = updateOrder(order, { amount: 200 }); // ✅
class EventBus {
    handlers = {};
    on(event, handler) {
        const list = (this.handlers[event] ??= []);
        list.push(handler);
        return this;
    }
    emit(event, payload) {
        for (const h of (this.handlers[event] ?? []))
            h(payload);
    }
}
const bus = new EventBus();
bus.on("orderPaid", (p) => console.log(`event: ${p.orderId} paid ${p.amount}`));
bus.emit("orderPaid", { orderId: "o1", amount: 200 });
function toSummary(o) {
    return { id: o.id, amount: o.amount };
}
console.log("updated =", updated);
console.log("summary =", toSummary(order));
