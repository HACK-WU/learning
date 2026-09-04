// 课 2 · 知识点 1：故意赋错值，报错里的类型 = 编译器推导出的类型

const nameConst = "Alice";
const p1: "Bob" = nameConst; // const 推导：字面量？

let nameLet = "Alice";
const p2: "Bob" = nameLet; // let 推导：宽化成 string？

const nums = [];
const p3: string = nums; // 空数组推导成什么？

const user = null;
const p4: { name: string } = user; // null 初值推导成什么？

const obj = { mode: "dev" };
const p5: { mode: "prod" } = obj; // 对象属性推导成什么？

const boxed: String = "Alice";
const p6: string = new String("Alice"); // 包装类型能赋回原始类型吗？

console.log(p1, p2, p3, p4, p5, boxed, p6);
