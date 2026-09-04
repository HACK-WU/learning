// ⚠️ 这是本课写基准测试时真实踩到的坑，保留为反例。
//
// 场景：Split 一条以 "/" 开头的路径，再用 Join 拼回去（往返应当相等）。
// 结果：Join 把开头的空字符串吞了，" /a/b" 变成了 "a/b"。

type Split<S extends string, Sep extends string> = SplitHelper<S, Sep, []>;
type SplitHelper<S extends string, Sep extends string, Acc extends string[]> =
  S extends `${infer Head}${Sep}${infer Tail}`
    ? SplitHelper<Tail, Sep, [...Acc, Head]>
    : [...Acc, S];

// ❌ 有 bug 的写法：用「累加器是不是空」来判断当前是不是第一个元素
type JoinBuggy<T extends readonly string[], Sep extends string> = JoinBuggyHelper<T, Sep, "">;
type JoinBuggyHelper<T extends readonly string[], Sep extends string, Acc extends string> =
  T extends [infer Head extends string, ...infer Rest extends readonly string[]]
    ? JoinBuggyHelper<Rest, Sep, Acc extends "" ? Head : `${Acc}${Sep}${Head}`>
    : Acc;

// ✅ 正确写法：用一个显式的 First 标志位
type JoinFixed<T extends readonly string[], Sep extends string> = JoinFixedHelper<T, Sep, "", true>;
type JoinFixedHelper<
  T extends readonly string[],
  Sep extends string,
  Acc extends string,
  First extends boolean,
> = T extends [infer Head extends string, ...infer Rest extends readonly string[]]
  ? JoinFixedHelper<Rest, Sep, First extends true ? Head : `${Acc}${Sep}${Head}`, false>
  : Acc;

// Split 的结果：第一个元素是空字符串（因为路径以 / 开头）
type Parts = Split<"/a/b", "/">;
export const parts: ["", "a", "b"] = null as unknown as Parts;

// ❌ buggy 版本：往返不相等 —— 少了个前导斜杠
type RoundTripBuggy = JoinBuggy<Parts, "/">;
// @ts-expect-error 实际得到 "a/b"，不是 "/a/b"
export const bad: "/a/b" = null as unknown as RoundTripBuggy;
export const actuallyIs: "a/b" = null as unknown as RoundTripBuggy;

// ✅ fixed 版本：往返相等
type RoundTripFixed = JoinFixed<Parts, "/">;
export const good: "/a/b" = null as unknown as RoundTripFixed;
