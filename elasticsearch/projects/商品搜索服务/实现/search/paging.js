import { getClient, rootCause, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { naming, pageCfg } from '../config/index.js';

/**
 * 深分页：把全部商品按销量倒序导出。
 *
 * 为什么不用 from/size（课 7 / 课 12 实测）：
 *   - from + size 上限 10000，超了直接报 `Result window is too large`
 *   - 即使没超，from=99000 意味着每个分片都要先算 99100 条再丢掉前 99000 条，越翻越慢
 * 为什么不用 scroll：
 *   - scroll 持有的是"发起那一刻的快照"，适合一次性全量导出，不适合用户实时翻页
 * search_after 才是用户翻页的正解：无上限、每次只算当前页。
 *
 * 决胜键为什么选 sku（keyword）而不是 _id / _doc：
 *   - _id：ES 9.5.1 直接禁止排序（Fielddata access on the _id field is disallowed，课 7 实测）
 *   - _doc：最快，但它是 Lucene 内部顺序 —— reindex 之后顺序会变，导出结果不可复现
 *   - sku：业务主键，稳定、可复现、且能跨索引重建保持一致
 */
const SORT = [{ sales: 'desc' }, { sku: 'asc' }];

export async function exportAll(client, { size = pageCfg.exportSize, verbose = true } = {}) {
  const all = [];
  let searchAfter;
  let page = 0;

  while (true) {
    page += 1;
    const body = {
      size,
      sort: SORT,
      query: { match_all: {} },
      _source: ['sku', 'title', 'sales', 'price']
    };
    if (searchAfter) body.search_after = searchAfter;

    const res = await client.search({ index: naming.alias, ...body });
    const hits = res.hits.hits;
    if (hits.length === 0) break;

    all.push(...hits);
    if (verbose) {
      const last = hits[hits.length - 1].sort;
      console.log(`   第 ${page} 页：${hits.length} 条，游标 = [${last[0]}, ${last[1]}]`);
    }
    if (hits.length < size) break;
    searchAfter = hits[hits.length - 1].sort;
  }

  return all;
}

/** 演示 from/size 撞墙：不修改任何索引设置，直接用一个越界的 from 触发报错 */
export async function demoFromSizeLimit(client) {
  try {
    await client.search({
      index: naming.alias,
      from: pageCfg.maxResultWindow - 5,
      size: 10,
      query: { match_all: {} }
    });
    return { errored: false, message: '未报错（说明 max_result_window 被改大过）' };
  } catch (e) {
    return { errored: true, message: rootCause(e) };
  }
}

async function main() {
  const client = getClient();
  await printConnection();

  console.log('\n📄 深分页导出（search_after）');
  const rows = await exportAll(client);
  console.log(`\n   ✅ 共导出 ${rows.length} 条，按 [销量 desc, sku asc] 排序`);
  console.log('   前 5 条：');
  for (const r of rows.slice(0, 5)) {
    console.log(`     ${r._source.sku} ｜ 销量 ${String(r._source.sales).padStart(4)} ｜ ¥${String(r._source.price).padStart(5)} ｜ ${r._source.title}`);
  }
  console.log('   后 3 条：');
  for (const r of rows.slice(-3)) {
    console.log(`     ${r._source.sku} ｜ 销量 ${String(r._source.sales).padStart(4)} ｜ ¥${String(r._source.price).padStart(5)} ｜ ${r._source.title}`);
  }
  // 校验排序是否严格单调（游标没写错的话一定是）
  let ordered = true;
  for (let i = 1; i < rows.length; i++) {
    const a = rows[i - 1]._source;
    const b = rows[i]._source;
    if (a.sales < b.sales || (a.sales === b.sales && a.sku > b.sku)) ordered = false;
  }
  console.log(`   排序单调性校验：${ordered ? '✅ 通过（游标正确，无重无漏）' : '❌ 失败'}`);

  console.log('\n🚧 对照组：from/size 撞墙');
  const r = await demoFromSizeLimit(client);
  console.log(`   from=${pageCfg.maxResultWindow - 5}, size=10 →`);
  console.log(`   ${r.errored ? '❌ 报错：' : ''}${r.message}`);
  console.log('   💡 报错原文里会告诉你上限是多少 —— 别去调大 max_result_window，改用 search_after');
}

runIfEntry(import.meta.url, main);
