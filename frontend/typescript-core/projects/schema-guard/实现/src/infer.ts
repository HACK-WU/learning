/**
 * 类型推导：从 schema 的结构算出对应的 TypeScript 类型（阶段 3 课 9 + 阶段 5 课 13）。
 *
 * 这就是本项目里唯一一处「类型体操」。它值不值得写，是 `设计决策.md` 的
 * 决策点 2 —— 这里只管实现，取舍另说。
 */
import type {
  ArraySchema,
  BooleanSchema,
  NumberSchema,
  ObjectSchema,
  StringSchema,
} from "./schema.js";

export type Infer<S> =
  S extends StringSchema ? string
  : S extends NumberSchema ? number
  : S extends BooleanSchema ? boolean
  : S extends ArraySchema<infer Inner> ? Infer<Inner>[]
  : S extends ObjectSchema<infer F>
    ? { -readonly [K in keyof F]: F[K] extends { readonly kind: string } ? Infer<F[K]> : never }
  : never;

/**
 * ⚠️ 递归深度上限 —— 实测（2026-09-04，Node v22.14.0 + TS 7.0.2）
 *
 * `Infer` 在 array / object 上是递归的。**实测发现：限制不在「能不能算出来」，
 * 而在「算出来之后要不要比较」。**
 *
 * | 嵌套形状 | 只强制实例化 | 再做结构比较（更接近真实用法） |
 * |---------|------------|---------------------------|
 * | array   | > 1002 层仍通过 | **101 层**，102 层起报 **TS2321** |
 * | object  | > 303 层仍通过  | **100 层**，101 层起报 **TS2321** |
 *
 * 两个要点：
 *
 * 1. **报错码是 TS2321**（Excessive stack depth comparing types），不是课 13
 *    里那个 TS2589。也就是说失败发生在**比较两个深层类型**的时候，而不是
 *    实例化的时候 —— 光"推导得出来"不够，还得"比得了"。
 * 2. 约 **100 层**对真实业务的 schema 已经绰绰有余（一般不超过 10 层）。
 *    这是一个**必须写下来的已知边界**，而不是"应该能一直嵌套下去"。
 *
 * ⚠️ 写这段注释时我一开始凭课 13 的印象写了「非尾递归、约 48 层」——
 *    实测证明是错的：这里的实例化能到一千层以上，卡住的是比较。
 *    **凡涉及具体数值，一律实测，不凭记忆。** 复现：`node test/depth.cjs`。
 */
export type INFER_DEPTH_LIMIT_NOTE =
  "实例化 >1000 层；结构比较约 100 层后报 TS2321。详见 test/depth.cjs 的实测";
