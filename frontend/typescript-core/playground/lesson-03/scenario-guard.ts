// 课 3 · 第四幕回扣：四个防护点（预期报错，用来对照第一幕的静默失败）

interface DataRow {
  id: string;
  name: string;
  score: number;
}

// ① 字段名拼错：JS 里静默产出 undefined，TS 当场抓住并给出建议
const typo: DataRow = { id: "u2", name: "Bob", scroe: 76 };

// ② 缺字段：JS 里静默产出 undefined，TS 当场抓住
const missing: DataRow = { id: "u2", name: "Bob" };

// ③ 新鲜字面量直接赋值：多余属性被拦（大概率是笔误）
const fresh: DataRow = { id: "u1", name: "Alice", score: 98, source: "api" };

// ④ 变量中转后再赋值：多余属性放行（数据来自外部，就该有这个灵活性）
const fromApi = { id: "u1", name: "Alice", score: 98, source: "api" };
const notFresh: DataRow = fromApi; // ✅ 这一行不该报错

console.log(typo, missing, fresh, notFresh);
