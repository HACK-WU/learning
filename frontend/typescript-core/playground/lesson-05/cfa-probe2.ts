// 课 5 · 补测：闭包里的收窄什么时候会「重置」

// A：闭包之后又给变量赋值 —— 闭包执行时它可能已经变了
function reassignedAfterCallback(): void {
  let value: string | number = "hi";
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ❓
    value = 42;
  }
}

// B：const —— 不可能再被赋值，收窄保留
function withConst(): void {
  const value: string | number = "hi";
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ✅
  }
}

// C：let，但之后再没赋值过 —— 表现得像 const
function withLetNeverReassigned(): void {
  let value: string | number = "hi";
  if (typeof value === "string") {
    setTimeout(() => console.log(value.toUpperCase()), 0); // ❓
  }
}

console.log(reassignedAfterCallback, withConst, withLetNeverReassigned);
