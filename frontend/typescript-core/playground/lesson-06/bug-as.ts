// 课 6 · 第一幕：一个 as，让报错消失了，三小时后线上炸了

interface Order {
  id: string;
  amount: number;
}

// 后端某天把 amount 从数字改成了字符串 —— 接口文档没更新
const response = '{"id":"o1","amount":"99"}';

// 赶工时写的：一个 as，编译器的所有疑问都闭嘴了
const order = JSON.parse(response) as Order;

console.log("打折后 =", order.amount * 0.8); // 79.2 —— 字符串被隐式转成数字，碰巧对了
console.log("加运费 =", order.amount + 10); // "9910" —— 变成字符串拼接，悄悄错了
console.log("格式化 =", order.amount.toFixed(2)); // 运行时炸在这里
