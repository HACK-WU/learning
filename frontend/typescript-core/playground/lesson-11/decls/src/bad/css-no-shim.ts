// 没有 *.css 的通配声明时，副作用 import 会被 TS 7 拦下来
import "./../style.css";

console.log("no shim");
