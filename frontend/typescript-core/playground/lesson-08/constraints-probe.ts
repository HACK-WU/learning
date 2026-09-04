// 课 8 · 知识点 2：边界探测 —— 约束拦住了什么

interface Order {
  id: string;
  amount: number;
}

function getField<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const order: Order = { id: "o1", amount: 100 };

// A：拼错的 key —— 第一幕那个 bug 的解药
const typo = getField(order, "nmae");

// B：keyof 的结果里没有的键
const k: keyof Order = "missing";

// C：约束不满足 —— 既缺 id 又多了 name，TS 用约束类型 HasId 去检查
interface HasId {
  id: string;
}
function logId<T extends HasId>(item: T): string {
  return item.id;
}
const noId = logId({ name: "no id field" }); // 报 TS2353（见正文说明）

// D：没有约束时，T 上不能访问任何具体属性
function bad<T>(obj: T): string {
  return obj.id;
}

// E：索引访问类型的结果是否精确
type IdType = Order["id"];
const wrongType: IdType = 123;

// F：约束只要求「最低限度」，多出来的属性不影响
const extra = logId({ id: "o1", extra: 42 });

console.log(typo, k, noId, bad, wrongType, extra);
