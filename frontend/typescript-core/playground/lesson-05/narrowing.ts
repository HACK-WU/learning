// 课 5 · 知识点 1：内置收窄手段

// ① typeof：识别原始类型
function format(value: string | number | boolean): string {
  if (typeof value === "string") return value.toUpperCase();
  if (typeof value === "number") return value.toFixed(2);
  return value ? "yes" : "no";
}

// ② 真值检查：排除 null / undefined
function greet(name: string | null): string {
  if (name) return `hello, ${name}`;
  return "hello, stranger";
}

// ③ 相等性检查：排除具体值
function lengthOf(value: string | null): number {
  if (value === null) return 0;
  return value.length;
}

// ④ in：按属性是否存在区分
type Fish = { swim: () => void };
type Bird = { fly: () => void };
function move(animal: Fish | Bird): string {
  if ("swim" in animal) return "swimming";
  return "flying";
}

// ⑤ instanceof：识别 class 实例
function formatDate(value: Date | string): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return value;
}

// ⑥ Array.isArray：识别数组
function join(value: string | string[]): string {
  if (Array.isArray(value)) return value.join(",");
  return value;
}

console.log(format("hi"), format(3.14159), format(true));
console.log(greet(null), "|", greet("Alice"));
console.log(lengthOf(null), lengthOf("abcd"));
console.log(move({ swim: () => {} }), move({ fly: () => {} }));
console.log(formatDate(new Date("2026-09-03T00:00:00Z")), formatDate("2026-09-03"));
console.log(join(["a", "b"]), join("a"));
