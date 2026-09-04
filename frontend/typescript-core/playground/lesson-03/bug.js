// 课 3 · 第一幕：JS 版的「统一记录格式」
function report(record) {
  return `${record.id}: ${record.score}`;
}

// 小王从 API 拿的对象，多带了一个字段
const fromApi = { id: "u1", name: "Alice", score: 98, source: "api" };
console.log("from api ->", report(fromApi));

// 他自己写死的一条测试数据，字段名拼错了
const typo = { id: "u2", name: "Bob", scroe: 76 };
console.log("typo     ->", report(typo));

// 字段名完全对不上的一份数据
const wrong = { key: "u3", value: 88 };
console.log("wrong    ->", report(wrong));
