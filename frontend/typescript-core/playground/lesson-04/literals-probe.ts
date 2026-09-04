// 课 4 · 知识点 2：边界探测（预期报错，用来看清字面量类型的边界）

type EventName = "click" | "change";
type HandlerName = `on${EventName}`;

// A：模板字面量展开后，只有那几个值
const bad: HandlerName = "onhover";
const empty: HandlerName = "on";

// B：字面量类型就该只有一个值
let orderStatus: "pending" = "pending";
orderStatus = "paid";

// C：模板字面量与原始类型组合 = 模式匹配
type UserId = `u-${number}`;
const id1: UserId = "x-1001"; // 前缀不对
const id2: UserId = "u-abc"; // 后缀不是数字

console.log(bad, empty, orderStatus, id1, id2);
