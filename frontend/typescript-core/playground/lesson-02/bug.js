// 课 2 · 第一幕：JS 老项目里的「导入 CSV 算总账」
// 注意 total 的初值：本想放数字，顺手写了空串
let total = "";
const scores = [98, 76, 89];
for (const s of scores) {
  total += s;
}
console.log("total =", total);
console.log("total + 100 =", total + 100);

// 状态列表：本该是常量，被同事顺手加了一项
const STATUS = ["pending", "paid", "refunded"];
STATUS.push("paid"); // 手滑：重复状态进来了
console.log("STATUS =", STATUS);
