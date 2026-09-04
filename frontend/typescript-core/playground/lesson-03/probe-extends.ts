// 课 3 · 补充核实：extends 与交叉类型在属性冲突时的行为差异
interface Base {
  x: number;
}

interface Derived extends Base {
  x: string; // 同名属性冲突：extends 会怎样？
}

type Cross = { x: number } & { x: string }; // 交叉：会怎样？
const c: Cross = { x: 1 };

console.log(c);
