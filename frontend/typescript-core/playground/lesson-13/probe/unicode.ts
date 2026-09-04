// TS 7 破坏性变更：模板字面量类型的推断现在按 Unicode 码点，而不是 UTF-16 码元。
// 下面两组断言一正一反，把这件事钉死。

type HeadTail<S> = S extends `${infer Head}${infer Tail}` ? [Head, Tail] : never;

declare const r1: HeadTail<"😀abc">;
declare const r2: HeadTail<"a😀b">;

// ① 正向：TS 7 的行为 —— 😀 被当成「一个」单位
export const h1: "😀" = r1[0];   // ✅ 通过
export const t1: "abc" = r1[1];  // ✅ 通过
export const h2: "a" = r2[0];    // ✅ 通过
export const t2: "😀b" = r2[1];  // ✅ 通过

// ② 反向：TS 6 及更早的行为 —— 会把代理对拆成两半
//    如果这四行「不报错」，说明编译器还在按 UTF-16 处理。
//    实测在 TS 7.0.2 上，这四行全部报错 —— 变更确实生效了。
// @ts-expect-error 旧行为：😀 的前半代理项
export const old_h1: "\ud83d" = r1[0];
// @ts-expect-error 旧行为：😀 的后半代理项 + 剩余字符
export const old_t1: "\ude00abc" = r1[1];
// @ts-expect-error 旧行为
export const old_h2: "a\ud83d" = r2[0];
// @ts-expect-error 旧行为
export const old_t2: "\ude00b" = r2[1];
