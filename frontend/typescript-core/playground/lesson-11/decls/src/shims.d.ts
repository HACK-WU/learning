// 通配模块声明：所有以 .css 结尾的 import 都当作 any
// （空实现 = 类型为 any；这也常用来给图片、字体、SVG 等资源兜底）
declare module "*.css";
