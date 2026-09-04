// 课 6 · 知识点 2：边界探测 —— unknown 的限制与两个高频场景

const u: unknown = "hello";

// A：unknown 能直接用吗？
console.log(u.toUpperCase());

// B：unknown 能参与运算吗？
const n: unknown = 1;
const sum = n + 1;

// C：unknown 能赋给具体类型吗？
const s: string = u;

// D：JSON.parse 返回的到底是什么类型？
const parsed = JSON.parse('{"a":1}');
const asNumber: number = parsed; // 不报错 → 说明它是 any；报错 → unknown

// E：catch 变量是什么类型？
try {
  throw new Error("x");
} catch (e) {
  const msg: string = e; // 报错 → unknown；不报错 → any
  console.log(msg);
}

// F：unknown 与 any 的相互赋值
const anyValue: any = 1;
const toUnknown: unknown = anyValue; // ✅ any → unknown
const backToAny: any = toUnknown; // ✅ unknown → any

console.log(sum, s, asNumber, backToAny);
