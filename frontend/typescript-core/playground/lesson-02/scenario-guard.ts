// 课 2 · 第四幕回扣：三个防护点（预期全部报错）

// ① 数字总和被赋成字符串：JS 里静默污染，TS 当场拦下
let total = 0;
total = "263 pts";

// ② 状态表是只读的：JS 里同事 push 成功，TS 当场拦下
const STATUS: readonly string[] = ["pending", "paid", "refunded"];
STATUS.push("paid");

// ③ 函数参数不标注：推导不出来，TS 直接拒绝
function parseRow(line) {
  return line.split(",");
}

console.log(total, STATUS, parseRow);
