"use strict";
// 课 6 · 知识点 2：unknown —— 安全的顶层类型
// ① 任何值都能放进 unknown（它是顶层类型）
let value = 1;
value = "hello";
value = { a: 1 };
value = null;
// ② 但要用它，必须先收窄
function describe(input) {
    if (typeof input === "string")
        return `string: ${input.toUpperCase()}`;
    if (typeof input === "number")
        return `number: ${input.toFixed(2)}`;
    if (input === null)
        return "null";
    return "something else";
}
// ③ 收窄之后，unknown 比 any 更安全也更精确
function lengthOf(input) {
    if (typeof input === "string")
        return input.length;
    if (Array.isArray(input))
        return input.length;
    return 0;
}
console.log(describe("hi"), describe(3.14159), describe(null), describe({}));
console.log(lengthOf("abcd"), lengthOf([1, 2, 3]), lengthOf(42));
