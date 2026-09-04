// 课 6 · 知识点 1：any 关闭检查，并沿数据流扩散

// ① any 什么都能做 —— 编译器完全不拦
let value: any = 1;
value = "hello";
value = { a: 1 };
try {
  console.log(value.foo.bar.baz); // ✅ 编译通过
} catch (e) {
  console.log("value.foo.bar.baz ->", (e as Error).message); // 💥 运行时才炸
}

// ② 传染：any 参与运算，结果还是 any
const raw: any = "99";
const doubled = raw * 2; // any（不是 number）
const label = `x${doubled}`; // any
console.log(doubled, label);

// ③ 传染：喂给函数，返回值也跟着变成 any
function doubleIt(x: any) {
  return x * 2;
}
const result = doubleIt("99"); // any
console.log(result);

// ④ 传染：混进正常类型里，整个数组被污染
const clean: number[] = [1, 2, 3];
const mixed = [...clean, raw]; // (number | any)[] → 实际退化成 any[]
console.log(mixed);
