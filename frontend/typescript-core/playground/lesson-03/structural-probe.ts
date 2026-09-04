// 课 3 · 知识点 2：边界探测（核心 = 多余属性检查的两种命运）

interface DataRow {
  id: string;
  score: number;
}

// A：新鲜对象字面量直接赋值 → 多余属性检查触发
const a: DataRow = { id: "u1", score: 98, source: "api" };

// B：先赋给变量，再赋值 → 不触发
const raw = { id: "u1", score: 98, source: "api" };
const b: DataRow = raw;

function report(row: DataRow): string {
  return `${row.id}:${row.score}`;
}

// C：直接传字面量（新鲜）vs 传变量
report({ id: "u1", score: 98, source: "api" });
report(raw);

// D：字段名拼错 —— 新鲜检查能抓住
const d: DataRow = { id: "u1", scroe: 98 };

// E：属性类型不兼容
const e: DataRow = { id: 1, score: 98 };

// F：缺属性
const f: DataRow = { id: "u1" };

// G：多余属性检查对嵌套层级也生效吗？
interface Box {
  row: DataRow;
}
const g: Box = { row: { id: "u1", score: 98, extra: 1 } };

// H：断言之后再赋值，还会检查多余属性吗？
const h: DataRow = { id: "u1", score: 98, extra: 1 } as DataRow;

console.log(a, b, d, e, f, g, h, report);
