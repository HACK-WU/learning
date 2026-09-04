// 课 4 · 知识点 1：边界探测（预期报错，用来看清联合的规则）

type Status = "pending" | "paid" | "refunded";

// A：不在联合里的值
const bad: Status = "shipped";

// B：联合上的属性访问 —— 只能访问共有属性
function f(id: string | number): number {
  return id.length; // number 上没有 length
}

// C：对象联合但缺少判别字段 —— 独有属性访问不了
type Circle = { radius: number };
type Square = { size: number };
type Shape = Circle | Square;
function area(s: Shape): number {
  return s.radius;
}

// D：加了判别字段之后，分支里就能访问独有属性（对比 C）
type Tagged = { kind: "circle"; radius: number } | { kind: "square"; size: number };
function taggedArea(s: Tagged): number {
  if (s.kind === "circle") return s.radius; // ✅
  return s.size; // ✅
}

// E：交叉类型的冲突
type Conflicted = { x: number } & { x: string };
const conflict: Conflicted = { x: 1 };

// F：从常量数组生成联合类型（索引访问类型，课 9 展开）
const STATUS_LIST = ["pending", "paid", "refunded"] as const;
type StatusFromList = (typeof STATUS_LIST)[number];
const s1: StatusFromList = "paid";
const s2: StatusFromList = "shipped";

console.log(bad, f, area, taggedArea, conflict, s1, s2);
