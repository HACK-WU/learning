import fs from 'node:fs';

/**
 * 关键词输入：让"中文关键词"在 Windows 上也能可靠地传进来。
 *
 * 为什么需要这个文件（本机实测的环境坑）：
 *   Windows PowerShell 5.1 会把 UTF-8 的中文按 GBK 解析，
 *   所以 `node search/search.js 苹果手机` 到了程序里会变成 "鑻规灉鎵嬫満"，查出来必然 0 条。
 *   这个坑已经在 elasticsearch/00-评审清单.md 里记过一次（JSON 内联传参被吃掉是同一个根因）。
 *
 * 三条输入路径，按优先级：
 *   1. --keyword-file=xxx.txt   从 UTF-8 文件读（最可靠，脚本/自动化推荐）
 *   2. 位置参数                 交互时方便，但 PowerShell 5.1 下中文可能失真
 *   3. 内置示例查询             不传参数时用它，保证 `npm run search` 一定能跑出结果
 */
export const DEMO_QUERIES = ['苹果手机', '小米笔记本', '降噪耳机', '商务办公'];

/** 内置示例品牌：给分面脚本的 --demo-brand 用，同样是为了绕开终端编码问题 */
export const DEMO_BRAND = '苹果';

export function readKeywordFile(p) {
  return fs.readFileSync(p, 'utf8').trim();
}

/** 从 argv 里解析关键词：返回 { keyword, source } */
export function resolveKeyword(argv, { fallback = DEMO_QUERIES[0] } = {}) {
  const fileArg = argv.find((a) => a.startsWith('--keyword-file='));
  if (fileArg) {
    return { keyword: readKeywordFile(fileArg.slice(15)), source: '文件' };
  }
  const positional = argv.find((a) => !a.startsWith('--'));
  if (positional) {
    return { keyword: positional, source: '命令行参数' };
  }
  return { keyword: fallback, source: `内置示例（${fallback}）` };
}
