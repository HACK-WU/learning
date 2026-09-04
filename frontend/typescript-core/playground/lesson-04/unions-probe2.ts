// 课 4 · 补测：判别式联合「加了判别字段」但「不判断」时能否访问独有属性

type Tagged =
  | { kind: "circle"; radius: number }
  | { kind: "square"; size: number };

// A：不判断 kind，直接访问独有属性
function withoutCheck(s: Tagged): number {
  return s.radius;
}

// B：判断了 kind 之后
function withCheck(s: Tagged): number {
  if (s.kind === "circle") return s.radius;
  return s.size;
}

console.log(withoutCheck, withCheck);
