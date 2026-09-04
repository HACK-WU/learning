// 课 2 · 知识点 3：边界探测（预期报错，用来看清规则边界）

function add(a, b) {
  return a + b;
} // 参数不标注

type VoidFn = () => void;
const returnsNumber: VoidFn = () => 42; // 返回 number 能赋给返回 void 的函数类型吗？

function optional(x?: number) {
  return x;
}
function explicit(x: number | undefined) {
  return x;
}
optional();
optional(undefined);
explicit(); // ❓ 不传参行吗？
explicit(undefined);

function inferred() {
  return "on";
} // 返回值推导成什么？
const probe: "off" = inferred();

const nothing: void = undefined;
const fromNever: void = fail(); // never 能赋给 void 吗？
function fail(): never {
  throw new Error("boom");
}

const tooMany = formatRow("u1", 98, "pts", "extra");
function formatRow(id: string, score: number, suffix?: string): string {
  return `${id}${score}${suffix ?? ""}`;
}

// 函数类型只声明了 2 个参数，调用时就只能传 2 个
type TwoArgs = (a: string, b: number) => string;
const three: TwoArgs = (a, b, c = "!") => `${a}${b}${c}`;
three("x", 1);
three("x", 1, "?");

console.log(add, returnsNumber, optional, explicit, inferred, probe, nothing, fromNever, tooMany);
