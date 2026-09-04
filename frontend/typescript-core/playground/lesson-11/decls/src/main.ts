// 先跑 bootstrap，把 declare 承诺的东西在运行时兑现
import "./bootstrap.js";

// 1) declare global（build.d.ts）：从模块内部扩展了全局作用域
const flags: FeatureFlags = { dark: true, beta: false };
console.log("BUILD_ID =", __BUILD_ID__, "| dark =", flags.dark, "| beta =", flags.beta);

// 2) 全局环境声明（globals.d.ts）：直接用，不用 import
const info: AppInfo = { name: "decls-demo", version: "1.0.0" };
console.log("info =", info.name, info.version);

// 3) 声明合并（merge-a + merge-b）：AppPlugin 同时要求 name 与 version
const plugin: AppPlugin = { name: "logger", version: "0.3.1" };
console.log("plugin =", plugin.name, plugin.version);
