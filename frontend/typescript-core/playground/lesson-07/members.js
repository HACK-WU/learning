"use strict";
// 课 7 · 知识点 1：类的成员与修饰符
class Order {
    id;
    amount;
    discountRate;
    createdAt;
    // 参数属性：构造参数前加修饰符，自动声明并赋值同名字段
    constructor(id, amount, discountRate = 1, createdAt = "2026-09-03") {
        this.id = id;
        this.amount = amount;
        this.discountRate = discountRate;
        this.createdAt = createdAt;
    }
    total() {
        return this.amount * this.discountRate; // ✅ 类内部能访问 private
    }
    describe() {
        return `Order ${this.id} created at ${this.createdAt}`;
    }
}
class GroupOrder extends Order {
    constructor(id, amount) {
        super(id, amount, 0.8); // 团购八折
    }
    // 子类能访问 protected 成员
    createdOn() {
        return this.createdAt;
    }
}
const normal = new Order("o1", 100, 0.9);
console.log(normal.id, normal.total());
console.log(normal.describe());
const group = new GroupOrder("g1", 100);
console.log(group.total(), group.createdOn());
