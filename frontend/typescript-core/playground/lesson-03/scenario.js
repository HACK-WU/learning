"use strict";
// 课 3 · 第四幕：给「统一记录格式」上类型
// 来源一：CSV 解析
function fromCsv(line) {
    const [id, name, rawScore] = line.split(",");
    return { id, name, score: Number(rawScore) };
}
function report(rows) {
    for (const row of rows) {
        console.log(`${row.id} ${row.name}: ${row.score}`);
    }
}
const csvRows = ["u1,Alice,98", "u2,Bob,76"].map(fromCsv);
const apiRows = [{ id: "u3", name: "Cindy", score: 89, source: "api" }];
// 两个来源混在一起：ApiRow 结构上兼容 DataRow，不需要任何转换
const all = [...csvRows, ...apiRows];
report(all);
const config = { title: "Score Report", sortBy: "score" };
const sortKey = config.sortBy; // ✅ satisfies 保留了字面量
console.log(`${config.title} - sorted by ${sortKey}`);
