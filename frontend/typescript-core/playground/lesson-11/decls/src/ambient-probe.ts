// declare = 「我向编译器承诺这里有这么个东西」，它不产出任何代码
declare const __DEV__: boolean;
declare function ping(): void;

if (__DEV__) {
  ping();
}
