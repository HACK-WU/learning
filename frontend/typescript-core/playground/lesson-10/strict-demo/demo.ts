// 课 10 · 严格性开关对比：同一份代码，三档配置

interface Config {
  retries?: number;
}

// A：参数没标类型 —— noImplicitAny
function sum(a, b) {
  return a + b;
}

// B：null 赋给 string —— strictNullChecks
const name: string = null;

// C：数组下标访问 —— noUncheckedIndexedAccess
const scores: number[] = [1, 2, 3];
const first: number = scores[0];

// D：可选属性显式赋 undefined —— exactOptionalPropertyTypes
const config: Config = { retries: undefined };

console.log(sum, name, first, config);
