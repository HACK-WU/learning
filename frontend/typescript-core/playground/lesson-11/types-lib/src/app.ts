import { count } from "broken-types";

console.log("count =", count);
// 这个全局名字来自 @types/legacy-logger，只有 types 里列了它才存在
console.log("LOG_LEVEL =", LOG_LEVEL);
logOnce("hello from types-lib");
