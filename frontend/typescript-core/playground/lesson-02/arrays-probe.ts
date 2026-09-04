// 课 2 · 知识点 2：边界探测（预期全部报错，用来看清规则边界）

const row: [string, number] = ["Alice", 98];
row.push(3); // 元组能被 push 吗？（运行时它就是个数组）
const cell2 = row[2]; // 越界访问

const STATUS: readonly string[] = ["pending", "paid", "refunded"];
const back: string[] = STATUS; // 只读 → 可变，允许吗？
STATUS.push("x"); // 只读数组能改吗？

const frozen = { mode: "dev", port: 3000 } as const;
frozen.port = 4000; // as const 的对象属性可改吗？

const shallow = { list: [1, 2, 3] } as const;
shallow.list.push(4); // as const 是深冻结还是浅冻结？

const mixed = [1, "a"]; // 混合数组推导成什么？
const m0: number = mixed[0];

const pair: [string, number] = ["Alice", 98];
const asArr: string[] = pair; // 元组能当数组用吗？

console.log(row, cell2, back, frozen, shallow, mixed, m0, asArr);
