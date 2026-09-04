"use strict";
// 课 8 · 知识点 3：泛型类型 —— 接口、别名与默认值
const order = { id: "o1", amount: 100 };
const single = { code: 0, message: "ok", data: order };
const list = { code: 0, message: "ok", data: [order] };
const success = { ok: true, data: 42 };
const failure = { ok: false, error: "timeout" };
const defaultPaged = { items: [order], total: 1 }; // T = Order
const stringPaged = { items: ["a"], total: 1 };
const kv = { key: 1, value: "one" };
const kv2 = { key: "one", value: 1 };
// ⑤ 泛型类：课 7 的 Stack 加上类型参数
class Stack {
    items = [];
    push(item) {
        this.items.push(item);
        return this;
    }
    pop() {
        return this.items.pop();
    }
    get size() {
        return this.items.length;
    }
}
const stack = new Stack();
stack.push(1).push(2);
console.log(single.code, list.data.length, success.data, failure.error);
console.log(defaultPaged.total, stringPaged.items, kv.value, kv2.value);
console.log(stack.pop(), stack.size);
