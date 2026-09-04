// 课 8 · 知识点 1：泛型函数与类型参数推导

// ① 最简单的泛型函数：T 是「类型的占位符」
function identity<T>(value: T): T {
  return value;
}

// 调用时，T 由实参自动推导出来
const a = identity("hello"); // T 推导为 string
const b = identity(42); // T 推导为 number
const c = identity([1, 2, 3]); // T 推导为 number[]

// ② 也可以显式指定（推导不出来，或你想强制指定时）
const d = identity<string>("hello");

// ③ 泛型把类型信息一路带下去
function first<T>(list: T[]): T {
  return list[0];
}
const firstOrder = first([{ id: "o1", amount: 100 }]); // 推导为 { id: string; amount: number }
const firstId = firstOrder.id; // ✅ 有补全、有检查

// ④ 多个类型参数
function pair<A, B>(a: A, b: B): [A, B] {
  return [a, b];
}
const p = pair("id", 1); // [string, number]

// ⑤ 泛型最常见的样子：Promise<T>、Array<T>
async function fetchOrder(): Promise<{ id: string }> {
  return { id: "o1" };
}

console.log(a, b, c, d, firstId, p, fetchOrder);
