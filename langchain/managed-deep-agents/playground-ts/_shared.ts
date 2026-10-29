/**
 * 公共工具：把定义对象打印成人能读的形状。
 *
 * 所有 lNN-*.ts 脚本都从这里取打印函数，保证输出格式一致、便于对照课文。
 * 这里刻意不依赖模型与网络——MDA 的核心实测都是"定义期"的，不需要真调模型。
 */

/** 分段标题，和课文里的实验编号对齐。 */
export function section(id: string, title: string): void {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`${id}  ${title}`);
  console.log("=".repeat(60));
}

/** 小标题（一节里的子步骤）。 */
export function step(title: string): void {
  console.log(`\n--- ${title} ---`);
}

/** 打印键值对，值统一 JSON 化，避免 [Object object]。 */
export function show(label: string, value: unknown): void {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  console.log(`  ${label.padEnd(26)} ${text}`);
}

/**
 * 打印 config 的键集合。
 *
 * 这是本课程最高频的断言：MDA 的很多"静默失败"表现为
 * 某个键压根不在 config 里（区别于键存在但值为空）。
 */
export function showConfigKeys(config: object, label = "config keys"): void {
  show(label, Object.keys(config).sort());
}

/**
 * 判断某个键在 config 里是否存在。
 *
 * 注意 Python 侧的差别：Python 里硬取不存在的键抛 KeyError，
 * JS 里返回 undefined——所以 JS 侧"键不存在"只能靠 `in` 判断，
 * 拿 `=== undefined` 判断会把"显式传了 undefined"也混进来。
 */
export function hasKey(config: object, key: string): boolean {
  return key in config;
}

/** 捕获一段调用的异常，返回可打印的结果（用于实测"错法会怎么炸"）。 */
export function attempt(label: string, fn: () => unknown): void {
  try {
    const value = fn();
    show(`${label} →`, value === undefined ? "undefined（没有抛错）" : value);
  } catch (e) {
    const err = e as Error;
    console.log(`  ${label} → 抛错 ${err.constructor.name}`);
    console.log(`  ${" ".repeat(4)}${err.message.split("\n")[0].slice(0, 150)}`);
  }
}
