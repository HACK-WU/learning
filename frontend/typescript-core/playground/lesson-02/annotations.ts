// 课 2 · 知识点 1：原始类型标注与类型推导
// 环境：TypeScript 7.0.2，无 tsconfig（strict 默认开）

// ① 七个原始类型的显式标注
const userName: string = "Alice";
const age: number = 18;
const isVip: boolean = true;
const empty: null = null;
const notFound: undefined = undefined;
const huge: bigint = 9007199254740993n;
const key: symbol = Symbol("id");

// ② 不写标注，看它推导出什么
const nameConst = "Alice"; // 推导："Alice"（字面量类型）
let nameLet = "Alice"; // 推导：string（宽化）
const ageConst = 18; // 推导：18
let ageLet = 18; // 推导：number
const flag = true; // 推导：true

// ③ 该写不写的场合：推导太窄
// const nums = [];          // 推导 never[]，push(1) 会报错（见 infer-probe.ts）
const nums: number[] = []; // 正确写法
nums.push(1);

// const user = null;        // 推导 null，之后赋对象会报错
let user: { name: string } | null = null; // 正确写法
user = { name: "Alice" };

console.log(userName, age, isVip, empty, notFound, huge, key);
console.log(nameConst, nameLet, ageConst, ageLet, flag, nums, user);
