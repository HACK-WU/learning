"use strict";
// 课 7 · 知识点 2：抽象类与 implements
// 抽象类：半成品 —— 既有实现，也规定子类必须做的事
class Order {
    id;
    amount;
    constructor(id, amount) {
        this.id = id;
        this.amount = amount;
    }
    // 已实现的方法：所有子类共享
    describe() {
        return `${this.id} -> ${this.total()}`;
    }
}
class NormalOrder extends Order {
    total() {
        return this.amount;
    }
}
// 既继承抽象类，又声明自己符合 Payable 接口
class GroupOrder extends Order {
    total() {
        return this.amount * 0.8;
    }
}
const orders = [new NormalOrder("o1", 100), new GroupOrder("g1", 100)];
for (const order of orders) {
    console.log(order.describe());
}
