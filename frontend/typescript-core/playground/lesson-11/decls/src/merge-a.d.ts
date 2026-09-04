// 同名 interface 会自动合并 —— 这是「声明合并」最常用的一支
// 注意命名：全局作用域里已经有 lib.dom 的 Plugin（浏览器插件），
// 这里故意加前缀避免撞车（撞车的样子见 src/bad/global-clash.d.ts）
interface AppPlugin {
  name: string;
}
