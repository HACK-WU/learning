// 课 6 · 知识点 1：边界探测 —— any 的传染范围与阻断方式

// A：隐式 any（参数不标注）—— noImplicitAny 会拦
function implicit(x) {
  return x;
}

// B：any 能不能被「阻断」？—— 标注了返回类型的函数就是防火墙
function toNumber(x: any): number {
  return Number(x);
}
const blocked = toNumber("99"); // 出去的是 number，不是 any
const checkBlocked: string = blocked; // ❓ 应该报错（说明 any 被挡住了）

// C：any 传给泛型，推断出什么？
function identity<T>(x: T): T {
  return x;
}
const viaGeneric = identity<any>("99"); // any

// D：any 赋给具体类型 / 具体类型赋给 any
const a: any = 1;
const b: number = a; // ✅ any 能赋给任何类型
const c: string = a; // ✅ 同一个 any，赋给 string 也行

console.log(implicit, blocked, viaGeneric, b, c);
