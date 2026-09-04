// 全局声明是在「全局作用域」里起名字 —— 会跟 lib.dom 已有的同名类型合并。
// lib.dom.d.ts 里已经有 interface Plugin（浏览器插件，name 是只读的），
// 于是这里的 name 与它的修饰符不一致，直接冲突。
interface Plugin {
  name: string;
  version: string;
}
