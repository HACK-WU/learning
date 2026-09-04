// 课 8 · 补测：「缺 id」的约束报错到底长什么样（避开多余属性检查）

interface HasId {
  id: string;
}
function logId<T extends HasId>(item: T): string {
  return item.id;
}

// A：用变量中转，绕开课 3 讲的多余属性检查
const noId = { name: "no id field" };
const a = logId(noId);

// B：字段类型不对
const wrongType = { id: 123 };
const b = logId(wrongType);

// C：满足约束（对照组）
const good = { id: "o1", amount: 100 };
const c = logId(good);

console.log(a, b, c);
