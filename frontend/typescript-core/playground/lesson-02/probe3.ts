// 课 2 · 补测 A：空数组 / as const 对变量 / 字符串累加

// A1 空数组：写入后读取，类型能被确定吗？
const nums = [];
nums.push(1);
const n1: number = nums[0];

// A2 as const 作用在「变量」上还生效吗？
const arr = [1, 2, 3];
const frozenByAsConst = arr as const;
const n2: 4 = frozenByAsConst[0];

// A3 字符串初值 + 数字累加：TS 拦得住吗？
let total = "";
for (const s of [98, 76, 89]) {
  total += s;
}
console.log("total =", total);
console.log("n1 =", n1, "n2 =", n2);
