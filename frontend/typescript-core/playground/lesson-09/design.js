"use strict";
// 课 9 · 知识点 4：泛型的实际设计场景
class EventBus {
    handlers = {};
    on(event, handler) {
        const list = (this.handlers[event] ??= []);
        list.push(handler);
        return this;
    }
    emit(event, payload) {
        for (const handler of (this.handlers[event] ?? [])) {
            handler(payload);
        }
    }
}
const bus = new EventBus();
bus.on("orderPaid", (p) => console.log(`paid ${p.orderId}: ${p.amount}`));
bus.emit("orderPaid", { orderId: "o1", amount: 100 }); // ✅
const field1 = { name: "id", value: "o1", label: "订单号" };
const field2 = { name: "amount", value: 100, label: "金额" };
// const field3: OrderField = { name: "amount", value: "100", label: "金额" }; // ❌ value 类型不对
// const field4: OrderField = { name: "missing", value: 1, label: "X" };       // ❌ 键不存在
console.log(field1, field2);
