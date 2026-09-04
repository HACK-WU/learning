// 课 3 · 知识点 2：结构化类型系统 —— 看形状，不看名字

interface DataRow {
  id: string;
  score: number;
}

// ① 从没声明过 implements DataRow，形状对就能赋值
const fromApi = { id: "u1", name: "Alice", score: 98, source: "api" };
const row1: DataRow = fromApi; // ✅ 多余属性不拦

// ② class 也一样：只要形状对
class Point {
  constructor(
    public x: number,
    public y: number,
  ) {}
}
interface XY {
  x: number;
  y: number;
}
const xy: XY = new Point(1, 2); // ✅ 没人声明过 Point implements XY

// ③ 缺属性才会被拦（见 structural-probe.ts）
// const row2: DataRow = { id: "u2" };

// ④ 嵌套也递归检查
interface Box {
  row: DataRow;
}
const box: Box = { row: fromApi }; // ✅ 里面的 row 也按形状检查

function report(row: DataRow): string {
  return `${row.id}: ${row.score}`;
}

console.log(report(fromApi));
console.log(row1, xy, box);
