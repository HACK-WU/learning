"use strict";
// 课 4 · 补测：enum 与数字的边界（变量 vs 字面量）
var Num;
(function (Num) {
    Num[Num["A"] = 0] = "A";
    Num[Num["B"] = 1] = "B";
})(Num || (Num = {}));
const fromVariable = someNumber;
const c = "p" /* ConstEnum.P */;
console.log(fromVariable, c);
