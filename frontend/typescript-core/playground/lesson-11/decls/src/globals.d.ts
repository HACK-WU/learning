// 全局环境声明：本文件没有顶层 import / export，所以它是一个「全局脚本」，
// 这里 declare 出来的名字，项目里任何文件都能直接用，不需要 import。
declare const APP_ENV: "dev" | "prod";

declare interface AppInfo {
  name: string;
  version: string;
}
