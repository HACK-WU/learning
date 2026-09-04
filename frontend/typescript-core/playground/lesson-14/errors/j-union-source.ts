// 候选 J：源类型是联合 —— TS 需要解释「每一个成员为什么不行」
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "square"; side: number }
  | { kind: "tri"; a: number; b: number; c: number };

declare let shape: Shape;

export const circle: { kind: "circle"; radius: number } = shape;
