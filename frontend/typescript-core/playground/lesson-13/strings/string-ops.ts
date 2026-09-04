// ============ 知识点 1：模板字面量 + infer 的字符串操作 ============

// ① 拆分：Split<"a-b-c", "-"> → ["a", "b", "c"]
//    用累加器把它写成尾递归，才能处理较长的字符串
type Split<S extends string, Sep extends string> = SplitHelper<S, Sep, []>;
type SplitHelper<S extends string, Sep extends string, Acc extends string[]> =
  S extends `${infer Head}${Sep}${infer Tail}`
    ? SplitHelper<Tail, Sep, [...Acc, Head]>
    : [...Acc, S];

type S1 = Split<"a-b-c", "-">;
export const s1: ["a", "b", "c"] = null as unknown as S1;

// ② 连接：Join<["a","b","c"], "-"> → "a-b-c"（尾递归）
type Join<T extends readonly string[], Sep extends string> = JoinHelper<T, Sep, "">;
type JoinHelper<T extends readonly string[], Sep extends string, Acc extends string> =
  T extends [infer Head extends string, ...infer Rest extends readonly string[]]
    ? JoinHelper<Rest, Sep, Acc extends "" ? Head : `${Acc}${Sep}${Head}`>
    : Acc;

type J1 = Join<["a", "b", "c"], "-">;
export const j1: "a-b-c" = null as unknown as J1;

// ③ TrimLeft：官方 TS 4.5 发布说明里的例子，天生尾递归
type TrimLeft<S extends string> = S extends ` ${infer Rest}` ? TrimLeft<Rest> : S;
type T1 = TrimLeft<"   hello">;
export const t1: "hello" = null as unknown as T1;

// ④ 取首字符（非尾递归 vs 尾递归，同一道题的两种写法）
//    朴素版：递归结果被并进联合类型 → 非尾递归 → 深度约 48 就爆
type GetCharsNaive<S extends string> =
  S extends `${infer Char}${infer Rest}` ? Char | GetCharsNaive<Rest> : never;
//    累加器版：尾递归 → 可以长得多
type GetChars<S extends string> = GetCharsHelper<S, never>;
type GetCharsHelper<S extends string, Acc> =
  S extends `${infer Char}${infer Rest}` ? GetCharsHelper<Rest, Char | Acc> : Acc;

type G1 = GetChars<"abc">;
export const g1: "a" | "b" | "c" = null as unknown as G1;
type G2 = GetCharsNaive<"abc">;
export const g2: "a" | "b" | "c" = null as unknown as G2;

// ⑤ 内置的字符串工具（不需要自己写）
export const u1: "ABC" = null as unknown as Uppercase<"abc">;
export const u2: "Abc" = null as unknown as Capitalize<"abc">;
export const u3: "abc" = null as unknown as Lowercase<"ABC">;
export const u4: "aBC" = null as unknown as Uncapitalize<"ABC">;

// ⑥ 一个真实点的例子：从 URL 模板里提取路由参数名
//    "/users/:id/posts/:postId" → "id" | "postId"
type RouteParams<S extends string> = RouteParamsHelper<S, never>;
type RouteParamsHelper<S extends string, Acc> =
  S extends `${string}:${infer Param}/${infer Rest}`
    ? RouteParamsHelper<Rest, Acc | Param>
    : S extends `${string}:${infer Param}`
      ? Acc | Param
      : Acc;

type P1 = RouteParams<"/users/:id/posts/:postId">;
export const p1: "id" | "postId" = null as unknown as P1;

type P2 = RouteParams<"/health">;
export const p2: never = null as unknown as P2;
