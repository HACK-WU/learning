// 课 5 · 知识点 1：边界探测（看清每种收窄手段的能力范围）

// A：typeof 的盲区 —— null
function f1(value: string | null) {
  if (typeof value === "object") {
    return value; // 这里 value 是什么类型？
  }
  return value;
}

// B：typeof 分不出数组（数组也是 "object"）
function f2(value: string | string[]) {
  if (typeof value === "object") {
    return value.length; // string[] 有 length，但收窄成功了吗？
  }
  return value.length;
}

// C：in 用在非联合类型上 —— 收窄不了
function f3(value: { a: number }) {
  if ("b" in value) {
    return value.b; // ❓ 能访问吗
  }
  return value.a;
}

// D：instanceof 的右边必须是「值」，接口不是值
interface Point {
  x: number;
}
function f4(value: Point | string) {
  if (value instanceof Point) return value.x; // ❓ 接口编译后不存在
  return value;
}

// E：普通 boolean 函数不能收窄
function isString(value: unknown): boolean {
  return typeof value === "string";
}
function f5(value: string | number): string {
  if (isString(value)) {
    return value.toUpperCase(); // ❓ 收窄了吗
  }
  return value.toFixed(2);
}

// F：真值检查会把合法的 0 / "" 也排除（运行时行为）
function f6(count: number | undefined): number {
  if (count) return count;
  return 0;
}

console.log(f1(null), f2(["a", "b"]), f3({ a: 1 }), f4({ x: 1 }), f5(1), f6(0));
