// 课 4 · 知识点 2：字面量类型与模板字面量类型

// ① 字面量类型的三种来源
const fromConst = "pending"; // const 推导为 "pending"
const fromAsConst = ["a", "b"] as const; // as const 把每个值都锁成字面量
let fromAnnotation: "paid" | "refunded" = "paid"; // 显式标注

// ② 模板字面量类型：像模板字符串一样拼类型
type EventName = "click" | "change";
type HandlerName = `on${EventName}`; // "onclick" | "onchange"
const handler: HandlerName = "onclick";
// const badHandler: HandlerName = "onhover"; // ❌ 见 literals-probe.ts

// ③ 联合之间会做笛卡尔积展开
type Vertical = "top" | "bottom";
type Horizontal = "left" | "right";
type Corner = `${Vertical}-${Horizontal}`; // 4 种组合
const corner: Corner = "top-left";

// ④ 内置的字符串变换类型
type Upper = Uppercase<"pending">; // "PENDING"
type Capped = Capitalize<"pending">; // "Pending"
const upper: Upper = "PENDING";
const capped: Capped = "Pending";

// ⑤ 模板字面量 + 原始类型 = 模式匹配
type UserId = `u-${number}`;
const id1: UserId = "u-1001";
// const id2: UserId = "x-1001"; // ❌ 见 literals-probe.ts

console.log(fromConst, fromAsConst, fromAnnotation, handler, corner, upper, capped, id1);
