"use strict";
// 课 3 · 知识点 2：结构化类型系统 —— 看形状，不看名字
// ① 从没声明过 implements DataRow，形状对就能赋值
const fromApi = { id: "u1", name: "Alice", score: 98, source: "api" };
const row1 = fromApi; // ✅ 多余属性不拦
// ② class 也一样：只要形状对
class Point {
    x;
    y;
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }
}
const xy = new Point(1, 2); // ✅ 没人声明过 Point implements XY
const box = { row: fromApi }; // ✅ 里面的 row 也按形状检查
function report(row) {
    return `${row.id}: ${row.score}`;
}
console.log(report(fromApi));
console.log(row1, xy, box);
