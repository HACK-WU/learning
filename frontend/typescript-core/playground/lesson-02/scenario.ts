// 课 2 · 第四幕：给第一幕的「CSV 导入算总账」补上类型

// 原始数据：三行 CSV
const LINES: readonly string[] = ["u1,Alice,98", "u2,Bob,76", "u3,Cindy,89"];

// 一行数据 = 元组：长度固定，每格类型各自独立
type Row = [id: string, name: string, score: number];

// 函数签名就是合同：进来一行字符串，出去一个 Row
function parseRow(line: string): Row {
  const [id, name, rawScore] = line.split(",");
  return [id, name, Number(rawScore)];
}

// 参数写 readonly：向调用方承诺「我不会改你的数组」
function totalOf(rows: readonly Row[]): number {
  let total = 0; // ← 第一幕的 bug 就在这一行（JS 版写成了 let total = ""）
  for (const [, , score] of rows) {
    total += score;
  }
  return total;
}

const DISCOUNT = 0.8;
const STATUS: readonly string[] = ["pending", "paid", "refunded"];

const rows: Row[] = LINES.map(parseRow); // 回调参数由 map 推导，不用写
const total = totalOf(rows);

console.log(`rows = ${rows.length}`);
console.log(`total = ${total}`);
console.log(`after discount = ${(total * DISCOUNT).toFixed(2)}`);
console.log(`status = ${STATUS.join("/")}`);
