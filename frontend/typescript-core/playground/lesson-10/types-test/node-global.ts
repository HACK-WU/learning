// 课 10 · types: [] 的影响
// console 来自 lib（标准库），可用
console.log("console is available");

// process 来自 @types/node —— types: [] 时不会自动引入
console.log(process.version);
