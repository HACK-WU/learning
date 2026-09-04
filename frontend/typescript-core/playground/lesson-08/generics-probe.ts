// 课 8 · 知识点 1：边界探测 —— 泛型与 any 的本质差别

function firstAny(list: any[]): any {
  return list[0];
}
function firstGeneric<T>(list: T[]): T {
  return list[0];
}

const fromAny = firstAny([1, 2, 3]);
const fromGeneric = firstGeneric([1, 2, 3]);

// A：any 版本 —— 赋给什么类型都不报错（信息丢了）
const wrong1: string = fromAny;

// B：泛型版本 —— 类型信息保存下来了，会拦
const wrong2: string = fromGeneric;

// C：泛型函数体内部，T 上能访问什么？—— 实测：连 toString 都不行
function inspect<T>(value: T): string {
  return value.toString(); // ❌ TS2339：T 上没有任何已知成员
}
function inspectBad<T>(value: T): number {
  return value.length; // ❌ TS2339：同上
}

// D：推导不出来时会怎样
function makeEmpty<T>(): T[] {
  return [];
}
const empty1 = makeEmpty(); // T 推导不出来 → 变成 unknown？
const empty2 = makeEmpty<number>(); // 显式指定

// E：显式指定与实参冲突
const conflict = identity<string>(42);

function identity<T>(value: T): T {
  return value;
}

console.log(wrong1, wrong2, inspect(1), inspectBad("x"), empty1, empty2, conflict);
