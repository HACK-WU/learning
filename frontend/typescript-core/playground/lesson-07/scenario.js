"use strict";
// 课 7 · 第四幕：给订单建模 —— 让「意图」变成可检查的东西
class Order {
    id;
    amount;
    // 事故三的解药：一个不参与业务的私有字段，让 Order 与形状相同的类互不兼容
    brand = "order";
    constructor(id, amount) {
        this.id = id;
        this.amount = amount;
    }
    describe() {
        return `${this.id} -> ${this.total().toFixed(2)}`;
    }
    kind() {
        return this.brand;
    }
}
class NormalOrder extends Order {
    total() {
        return this.amount;
    }
}
class GroupOrder extends Order {
    total() {
        return this.amount * 0.8;
    }
}
class PreOrder extends Order {
    total() {
        return this.amount * 0.1; // 只付定金
    }
}
// 优惠券：形状几乎一样，但它不是订单
class Coupon {
    id;
    amount;
    brand = "coupon";
    constructor(id, amount) {
        this.id = id;
        this.amount = amount;
    }
    total() {
        return this.amount;
    }
    kind() {
        return this.brand;
    }
}
function applyTo(order) {
    return `applied: ${order.total().toFixed(2)}`;
}
const orders = [
    new NormalOrder("o1", 100),
    new GroupOrder("g1", 100),
    new PreOrder("p1", 100),
];
for (const order of orders) {
    console.log(order.describe());
}
console.log(applyTo(orders[0]));
console.log(new Coupon("c1", 20).total()); // 优惠券自己用没问题
