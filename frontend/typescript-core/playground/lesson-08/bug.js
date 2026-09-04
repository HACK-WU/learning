// 课 8 · 第一幕：JS 里的"通用函数"，类型信息全靠人记

const orders = [
  { id: "o1", amount: 100, status: "paid" },
  { id: "g1", amount: 80, status: "pending" },
];

// 通用工具：取第一个元素
function first(list) {
  return list[0];
}
console.log("first(ids)   =", first(["o1", "o2"]));
console.log("first(orders) =", first(orders).id);

// 通用工具：按 key 批量取值
function pluck(list, key) {
  return list.map((item) => item[key]);
}
console.log("pluck(id)    =", pluck(orders, "id"));
console.log("pluck(nmae)  =", pluck(orders, "nmae")); // 拼错了，静默

// 通用工具：包装 API 响应
function wrap(data) {
  return { code: 0, data };
}
const res = wrap(orders);
console.log("wrap ->", res.code, res.data.length);

// 拼错的 key 一路传下去，最后才炸
const names = pluck(orders, "nmae");
console.log("names[0].toUpperCase() ->", names[0].toUpperCase());
