"use strict";
// 课 3 · 知识点 1：对象类型 —— interface 与 type
const scores = { u1: 98, u2: 76 };
scores.u3 = 89; // 键名任意，值必须是 number
const cfg = { mode: "dev", port: 3000 }; // 两个声明合并后，两个属性都必需
const row = { id: "u1", name: "Alice", score: 98, createdAt: "2026-09-01" };
const apiRow = {
    id: "u2",
    name: "Bob",
    score: 76,
    createdAt: "2026-09-02",
    endpoint: "/users",
};
console.log(row, apiRow, scores, cfg);
