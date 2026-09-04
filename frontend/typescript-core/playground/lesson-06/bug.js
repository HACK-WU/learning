// 课 6 · 第一幕：JS 里「不知道是什么」的数据，一路静默流到底

// 后端某天把 amount 从数字改成了字符串
const response = '{"id":"o1","amount":"99"}';

const raw = JSON.parse(response); // 拿到什么全凭后端心情
console.log("raw.amount =", raw.amount);

// 乘法：字符串被隐式转成数字，碰巧对了
const total = raw.amount * 0.8;
console.log("total =", total);

// 加法：字符串拼接，悄悄错了
const bonus = raw.amount + 10;
console.log("bonus =", bonus); // "9910"

// 一路传到账单，谁也没发现
function save(record) {
  return "saved: " + record.bonus;
}
console.log(save({ bonus }));

// catch 里的错误对象也是「不知道是什么」
try {
  JSON.parse("{bad json}");
} catch (e) {
  console.log("caught:", e.constructor.name, "|", e.message);
}
try {
  throw "just a string"; // 有人直接抛了个字符串
} catch (e) {
  console.log("caught2: message =", e.message); // undefined
}
