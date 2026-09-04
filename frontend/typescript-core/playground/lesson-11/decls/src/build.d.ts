// 想在一个「模块文件」里扩展全局作用域，必须用 declare global。
// 末尾的 export {} 是必需的：它让本文件成为模块，declare global 才合法。
declare global {
  var __BUILD_ID__: string;
  interface FeatureFlags {
    dark: boolean;
    beta: boolean;
  }
}

export {};
