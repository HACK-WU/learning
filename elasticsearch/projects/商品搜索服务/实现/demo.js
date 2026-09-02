import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

/**
 * 一键跑通全流程：初始化 → 同步 → 搜索 → 分面 → 深分页 → 巡检 → 零停机切换。
 *
 * 用子进程逐个调用各入口脚本，而不是在这里重新实现一遍逻辑 ——
 * 这样"每个入口都能独立跑通"本身也是被验证的对象。
 */

const here = path.dirname(fileURLToPath(import.meta.url));

const steps = [
  ['① 初始化索引结构（模板 + 索引 + 别名 + ILM）', 'es/schema.js', []],
  ['② 同步商品数据（bulk 幂等 + 部分失败处理）', 'sync/sync.js', []],
  ['③ 搜索「苹果手机」', 'search/search.js', ['苹果手机']],
  ['④ 分面统计（品牌 / 分类 / 价格段）', 'search/facets.js', ['手机']],
  ['⑤ 深分页导出（search_after）', 'search/paging.js', []],
  ['⑥ 巡检（集群 / 分片 / 段 / ILM / 别名）', 'ops/health.js', []],
  ['⑦ 零停机重建索引（v1 → v2，切换前后对比）', 'ops/reindex-switch.js', []]
];

console.log('🚀 商品搜索服务 · 全流程演示');
console.log('   目标集群由 ES_PROFILE 决定（默认 cluster = 9201 三节点）');

for (const [title, script, args] of steps) {
  console.log(`\n${'='.repeat(78)}`);
  console.log(title);
  console.log('='.repeat(78));
  const r = spawnSync(process.execPath, [path.join(here, script), ...args], { stdio: 'inherit' });
  if (r.status !== 0) {
    console.error(`\n❌ 步骤「${title}」失败（退出码 ${r.status}），后续步骤已中止`);
    process.exit(r.status ?? 1);
  }
}

console.log(`\n${'='.repeat(78)}`);
console.log('🎉 全流程跑通。接下来可以试：');
console.log('   npm run sync:dirty                        看 bulk 部分失败怎么分类处置');
console.log('   node ops/reindex-switch.js --to=v1        回滚到 v1（npm run 传参在 PS 5.1 下会丢）');
console.log('   $env:ES_PROFILE="secure"; npm run security   在 9200 上演示 RBAC');
console.log('   npm run reset                            清理全部 cap_* 资源');
