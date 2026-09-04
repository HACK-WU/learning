// 课 2 · 知识点 3：函数类型标注

// ① 参数与返回值都标注
function formatRow(id: string, score: number, suffix = "pts"): string {
  return `${id}: ${score}${suffix}`;
}

// ② 简写：箭头函数 + 返回值标注
const sum = (list: number[]): number => list.reduce((acc, n) => acc + n, 0);

// ③ 返回元组：把 CSV 的一行解析成结构化数据
function parseRow(line: string): [id: string, score: number] {
  const [id, rawScore] = line.split(",");
  return [id, Number(rawScore)];
}

// ④ void：只做副作用，不关心返回值
function log(message: string): void {
  console.log(message);
}

// ⑤ never：函数永远不会正常返回
function fail(message: string): never {
  throw new Error(message);
}

// ⑥ 可选参数与剩余参数
function join(parts: string[], sep?: string): string {
  return parts.join(sep ?? "-");
}
function first(...items: number[]): number {
  return items[0];
}

// ⑦ 函数类型：把签名抽出来复用
type Formatter = (id: string, score: number) => string;
const formatter: Formatter = formatRow; // 第三个参数有默认值，赋给 2 参类型也成立

// ⑧ 上下文类型：回调参数不写，TS 从调用方推出来
const lines = ["u1,98", "u2,76", "u3,89"];
const rows = lines.map(parseRow);
const allScores = rows.map(([, score]) => score); // score 被推导为 number
const total = sum(allScores);

console.log(formatRow("u1", 98));
console.log(formatRow("u2", 76, "分"));
console.log(formatter("u3", 89)); // 按 Formatter 签名调用：只能传 2 个
log(`total = ${total}`);
console.log(join(["a", "b"]), join(["a", "b"], "+"), first(1, 2, 3));
console.log(rows, allScores);
if (total < 0) fail("total should not be negative");
