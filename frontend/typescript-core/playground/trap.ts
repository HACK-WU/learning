// 课 1 示例：类型检查通过，但运行时依然崩溃
interface User {
  name: string;
  age: number;
}

// JSON.parse 返回 any —— 它可以被赋给任何类型，编译器完全不拦
const user: User = JSON.parse('{"name":"Alice"}'); // age 字段其实不存在！

console.log("用户名：", user.name);
console.log("年龄（保留两位）：", user.age.toFixed(2)); // 💥 运行时炸在这里
