// TS 7 默认 noUncheckedSideEffectImports: true
// —— 只为了副作用的 import 也会被检查，没有声明就报错（见 src/bad/css-no-shim.ts）
// 有了 shims.d.ts 的 declare module "*.css"，这一行才通过。
import "./style.css";

console.log("style.css imported for side effect only");
