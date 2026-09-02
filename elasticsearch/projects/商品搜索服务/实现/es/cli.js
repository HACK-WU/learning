import { pathToFileURL } from 'node:url';
import { rootCause } from './client.js';

/**
 * 只有当"这个模块被当作脚本直接运行"时，才执行 main()。
 *
 * 为什么必须有这一层：
 *   ops/reindex-switch.js 需要 import es/schema.js 里的 putProductsTemplate / createIndex / pointAlias。
 *   如果 schema.js 在模块顶层无条件调用 main()，那么"切换索引"会顺带把整个初始化流程重跑一遍 ——
 *   实测就这么踩过：切索引的输出里凭空多出"📐 初始化 v1 结构"和"🎉 初始化完成"。
 *   模块的副作用被 import 触发，是 ESM 里非常隐蔽的一类 bug。
 *
 * 为什么不能用 `file://${process.argv[1]}` 硬拼：
 *   Windows 下 process.argv[1] 是反斜杠路径（D:\...），拼出来是 file://D:\... ，
 *   而 import.meta.url 是 file:///D:/... ，两者永远不相等 → main() 永远不执行，
 *   表现是"脚本跑了、退出码 0、但一个字都不输出"。
 */
export function runIfEntry(metaUrl, mainFn) {
  let isEntry = true;
  try {
    isEntry = metaUrl === pathToFileURL(process.argv[1]).href;
  } catch {
    isEntry = true;
  }
  if (!isEntry) return;

  mainFn().catch((err) => {
    console.error('\n❌ 失败：', rootCause(err));
    process.exit(1);
  });
}
