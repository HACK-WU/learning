// 课 4 · 第一幕：JS 老项目的订单状态流转

function nextStatus(status) {
  if (status === "pending") return "paid";
  if (status === "paid") return "refunded";
  return status;
}

// 手滑拼错
console.log("pendng  ->", nextStatus("pendng"));
// 大小写不一致
console.log("PAID    ->", nextStatus("PAID"));
// 中文状态混进来
console.log("已付款  ->", nextStatus("已付款"));
// 正常路径
console.log("pending ->", nextStatus("pending"));

// 状态被当成分支条件用，错的也照样"走得通"
const order = { id: "o1", status: "pendng" };
if (order.status === "pending") {
  console.log("可以付款");
} else {
  console.log("订单状态异常，无法付款：", order.status);
}
