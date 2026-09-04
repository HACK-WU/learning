// 候选 B：深层嵌套对象，最内层类型不对
interface Config {
  a: { b: { c: { d: string } } };
}

declare function load(c: Config): void;

load({ a: { b: { c: { d: 123 } } } });
