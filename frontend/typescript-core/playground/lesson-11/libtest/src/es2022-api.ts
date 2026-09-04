// Array.prototype.at 是 ES2022 才进标准的
const first: number = [1, 2, 3].at(0) ?? 0;

console.log("first =", first);
