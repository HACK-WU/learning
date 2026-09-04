// 语法错误：括号没配对。Parser 造不出 AST，后面的阶段根本没东西可处理。
function total(a: number, b: number {
  return a + b;
}

console.log(total(1, 2));
