// 课 2 · 知识点 2：数组、元组与只读

const scores: number[] = [98, 76, 89];
const names: Array<string> = ["Alice", "Bob"]; // 与 string[] 完全等价

// 元组：CSV 的一行，长度固定、每列类型各自独立
const row: [string, number] = ["Alice", 98];
const cell0: string = row[0]; // 第一格一定是 string
const cell1: number = row[1]; // 第二格一定是 number

// 具名元素 + 可选元素
type CsvRow = [id: string, score: number, remark?: string];
const r1: CsvRow = ["u1", 98];
const r2: CsvRow = ["u2", 76, "late"];

// 剩余元素：至少一个 string，后面跟任意个 number
type Header = [title: string, ...rest: number[]];
const header: Header = ["scores", 1, 2, 3];

// 只读数组
const STATUS: readonly string[] = ["pending", "paid", "refunded"];
const mutable: number[] = [1, 2, 3];
const readonlyView: readonly number[] = mutable; // ✅ 可变 → 只读，允许

// as const：把每个值都锁成字面量类型
const frozen = ["pending", "paid", "refunded"] as const;
const config = { mode: "dev", retries: 3 } as const;

console.log(scores, names, row, cell0, cell1, r1, r2, header);
console.log(STATUS, mutable, readonlyView, frozen, config);
