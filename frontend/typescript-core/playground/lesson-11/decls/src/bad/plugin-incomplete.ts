// 只写了 name，少了 merge-b.d.ts 合并进来的 version
const plugin: AppPlugin = { name: "logger" };

console.log(plugin.name);
