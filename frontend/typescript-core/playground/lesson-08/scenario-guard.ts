// 课 8 · 第四幕回扣：泛型拦住了什么，any 放过了什么

interface Order {
  id: string;
  amount: number;
}

function firstAny(list: any[]): any {
  return list[0];
}
function firstGeneric<T>(list: T[]): T {
  return list[0];
}
function pluck<T, K extends keyof T>(list: T[], key: K): T[K][] {
  return list.map((item) => item[key]);
}

const orders: Order[] = [
  { id: "o1", amount: 100 },
  { id: "g1", amount: 80 },
];

// ① 拼错的 key —— 第一幕那个静默的 [undefined, undefined]
const typo = pluck(orders, "nmae");

// ② any 版本：把数字数组当成订单数组，编译通过
const fromAny: Order = firstAny([1, 2, 3]);
try {
  console.log("fromAny.id.toUpperCase() =", fromAny.id.toUpperCase());
} catch (e) {
  console.log("fromAny ->", (e as Error).message);
}

// ③ 泛型版本：同样的错误当场被拦
const fromGeneric: Order = firstGeneric([1, 2, 3]);

// ④ 无约束时访问属性
function bad<T>(obj: T): string {
  return obj.id;
}

console.log(typo, fromGeneric, bad);
