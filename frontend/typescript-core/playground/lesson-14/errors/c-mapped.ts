// 候选 C：映射类型 + 模板字面量，值没按规则写
type Wrapped<T> = { [K in keyof T]: T[K] extends string ? `str:${T[K]}` : T[K] };

declare function save(w: Wrapped<{ a: string; b: number; c: boolean }>): void;

save({ a: "raw", b: 1, c: true });
