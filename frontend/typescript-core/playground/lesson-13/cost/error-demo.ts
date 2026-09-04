// ============ 知识点 3：报错可读性对照 ============
// 同一个「少传一个参数」的错误，在「简单类型」与「类型体操」下的报错长什么样。

// ---------- 版本 A：手写类型（简单）----------
declare function fetchSimple(route: string, params: { id: string; postId: string }): void;

fetchSimple("api/v2/users/:id/posts/:postId", { id: "1" });
//                                             ^^^^ 少了 postId

// ---------- 版本 B：由路径算出来的类型（体操）----------
export type RouteParams<S extends string> = RouteParamsHelper<S, never>;
type RouteParamsHelper<S extends string, Acc> =
  S extends `${string}:${infer Param}/${infer Rest}`
    ? RouteParamsHelper<Rest, Acc | Param>
    : S extends `${string}:${infer Param}`
      ? Acc | Param
      : Acc;

// 再套一层：DeepReadonly + Record，模拟真实项目里常见的「好几层类型叠在一起」
type DeepReadonly<T> = T extends object ? { readonly [K in keyof T]: DeepReadonly<T[K]> } : T;
type RouteArgs<S extends string> = DeepReadonly<Record<RouteParams<S> & string, string>>;

declare function fetchGym<S extends string>(route: S, params: RouteArgs<S>): void;

fetchGym("api/v2/users/:id/posts/:postId", { id: "1" });
//                                          ^^^^ 同样少了 postId
