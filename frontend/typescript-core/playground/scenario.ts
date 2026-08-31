// 第四幕：给同样的函数加上类型，编译器当场拦住
function calcDiscount(price: number, rate: number): number {
  return price * rate;
}

console.log(calcDiscount(100, 0.8)); // ✅ 正常
console.log(calcDiscount("100", 0.8)); // ❌ 编译时报错
console.log(calcDiscount(100, "八折")); // ❌ 编译时报错
