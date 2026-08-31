// 第一幕：老项目里的这个函数，没人知道参数到底要什么
function calcDiscount(price, rate) {
  return price * rate;
}

console.log(calcDiscount(100, 0.8)); // 80  ✅ 正常
console.log(calcDiscount("100", 0.8)); // 80  ⚠️ 字符串居然也算对了（隐式转换）
console.log(calcDiscount(100, "八折")); // NaN 💥 灾难的开始

// 这个 NaN 会一路传到页面上
const total = calcDiscount(100, "八折");
console.log(`应付：${total} 元`);
