import { getClient, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { naming } from '../config/index.js';
import { putProductsTemplate, simulate, createIndex, pointAlias } from '../es/schema.js';

/**
 * 零停机重建索引：把"改分析器"这种映射变更安全地上线。
 *
 * 为什么必须这么做（课 5 + 课 15 实测）：
 *   - 字段类型、分析器属于映射，**已存在的索引改不了**，改就得新建索引 + reindex
 *   - 直接让应用切到新索引名 = 需要改代码 + 发版 + 停服
 *   - 别名让应用永远只认一个名字，切换在 ES 侧一个原子请求里完成
 *
 * 本脚本演示的就是那条完整链路：
 *   建 v2 索引 → reindex 数据 → 对比效果 → 别名原子切换 → 验证 → 可回滚
 */

// 用来对比"切换前后效果"的探针查询。
// 选「小米笔记本」是因为它能把 v1 / v2 的搜索分析器差别暴露得很明显：
//   v1 搜索用 ik_max_word → 切成「小米 | 笔记 | 本 | 笔记本」，那个孤零零的「本」字
//      会把"本商品不含…"这类配件文档也召回进来
//   v2 搜索用 ik_smart   → 切成「小米 | 笔记本」，干净
const PROBE_KEYWORD = '小米笔记本';

async function probe(client, indexName) {
  const res = await client.search({
    index: indexName,
    size: 200, // 本例只有 38 条，一次取全，方便做两个索引的集合差
    query: {
      multi_match: {
        query: PROBE_KEYWORD,
        fields: ['title^3', 'description'],
        type: 'best_fields'
        // 这里刻意**不设** minimum_should_match。
        // 默认的 OR 语义才能把"搜索分析器切出了几个词"的差异放大到看得见：
        // 一旦加 75%，两边都只剩最相关的那几条，差异被一起抹平（实测过，别再加回去）。
      }
    },
    _source: ['sku', 'title', 'brand', 'category']
  });
  return {
    total: res.hits.total.value,
    hits: res.hits.hits.map((h) => ({
      sku: h._source.sku,
      title: h._source.title,
      category: h._source.category,
      score: h._score
    }))
  };
}

/** 当前别名指向哪个索引（优先取 is_write_index） */
async function currentWriteIndex(client) {
  const alias = await client.indices.getAlias({ name: naming.alias });
  for (const [idx, meta] of Object.entries(alias)) {
    if (meta.aliases?.[naming.alias]?.is_write_index) return idx;
  }
  return Object.keys(alias)[0];
}

export async function runSwitch(client, { toVersion = 'v2' } = {}) {
  const target = toVersion === 'v2' ? naming.v2 : naming.v1;
  const source = await currentWriteIndex(client);

  if (source === target) {
    const other = toVersion === 'v2' ? 'v1' : 'v2';
    console.log(`\n⏭  别名已经指向 ${target}，无需切换（要切到另一边请指定 --to=${other}）`);
    return { skipped: true };
  }

  // ---------- 1. 切换前：记录当前效果 ----------
  console.log(`\n📸 切换前（别名 → ${source}）`);
  const before = await probe(client, naming.alias);
  console.log(`   查询「${PROBE_KEYWORD}」命中 ${before.total} 条`);
  for (const h of before.hits.slice(0, 5)) {
    console.log(`     ${h.score.toFixed(4)}  ${h.title}`);
  }

  // ---------- 2. 建新索引（模板切到目标版本） ----------
  console.log(`\n🏗  准备 ${target}`);
  await putProductsTemplate(client, toVersion);
  await simulate(client, target);
  await createIndex(client, target);

  // ---------- 3. reindex ----------
  // ⚠️ reindex 只搬文档，不搬 mapping —— 目标索引的 mapping 由模板给（课 11 实测）
  // 数据量小所以用 wait_for_completion=true；生产大索引要异步 + 查 _tasks 进度
  console.log(`\n🚚 reindex：${source} → ${target}`);
  const reindexRes = await client.reindex({
    wait_for_completion: true,
    refresh: true,
    source: { index: source },
    dest: { index: target }
  });
  const sourceCount = await client.count({ index: source });
  const targetCount = await client.count({ index: target });
  const ok = sourceCount.count === targetCount.count;
  console.log(`   reindex 写入 ${reindexRes.total} 条`);
  console.log(`   文档数核对：${source}=${sourceCount.count} ｜ ${target}=${targetCount.count} ${ok ? '✅ 一致' : '❌ 不一致，不要切！'}`);
  if (!ok) throw new Error('reindex 后文档数不一致，已中止切换（宁可不切，也不能切到缺数据的索引）');

  // ---------- 4. 切换前先对比效果 ----------
  console.log(`\n🔬 切换前对比（直接查 ${target}，此时应用还看 ${source}）`);
  const after = await probe(client, target);
  console.log(`   查询「${PROBE_KEYWORD}」命中 ${after.total} 条`);
  for (const h of after.hits.slice(0, 5)) {
    console.log(`     ${h.score.toFixed(4)}  ${h.title}`);
  }

  const targetSkus = new Set(after.hits.map((h) => h.sku));
  const onlyBefore = before.hits.filter((h) => !targetSkus.has(h.sku));
  const shared = before.hits.filter((h) => targetSkus.has(h.sku));

  console.log(`\n   差异：${source} 命中 ${before.total} 条 → ${target} 命中 ${after.total} 条`);
  console.log(`   两边都命中 ${shared.length} 条，${source} 独有 ${onlyBefore.length} 条`);
  if (onlyBefore.length > 0) {
    console.log(`\n   ${source} 独有的是什么？按分类数一数就清楚了：`);
    const byCategory = {};
    for (const h of onlyBefore) byCategory[h.category] = (byCategory[h.category] ?? 0) + 1;
    for (const [cat, n] of Object.entries(byCategory)) {
      console.log(`     ${cat} ${n} 条`);
    }
    console.log('\n   举几条看看（注意它们跟"小米笔记本"有没有关系）：');
    for (const h of onlyBefore.slice(0, 6)) {
      console.log(`     [${h.category}] ${h.title}`);
    }
    console.log('\n   💡 根因：搜索分析器切出的碎片词（如「本」「笔记」）单独命中了文档，');
    console.log('      这些碎片不是用户想搜的东西。索引用 ik_max_word 是为了提高召回，');
    console.log('      搜索必须换回 ik_smart 才能把精度找回来 —— 这就是"索引/搜索分析器分离"。');
  }

  // ---------- 5. 原子切换 ----------
  console.log(`\n🔀 别名原子切换：${naming.alias} 从 ${source} → ${target}`);
  await pointAlias(client, target);

  // ---------- 6. 切换后验证 ----------
  const verify = await probe(client, naming.alias);
  console.log(`\n✅ 切换后（应用视角，别名 ${naming.alias}）`);
  console.log(`   查询「${PROBE_KEYWORD}」命中 ${verify.total} 条 ${verify.total === after.total ? `（与 ${target} 一致 ✅）` : `（⚠️ 与 ${target} 不一致，回滚！）`}`);
  for (const h of verify.hits.slice(0, 5)) {
    console.log(`     ${h.score.toFixed(4)}  ${h.title}`);
  }

  const other = toVersion === 'v2' ? 'v1' : 'v2';
  console.log(`\n💡 整个过程应用代码一行没改 —— 它只认别名 ${naming.alias}`);
  console.log(`💡 想回滚：node ops/reindex-switch.js --to=${other}`);
  console.log(`   （Windows PowerShell 5.1 下 \`npm run switch -- --to=${other}\` 的参数会被丢掉，实测三种写法只有直接 node 调用有效）`);

  return { source, target, before, after, verify };
}

// ---------- CLI ----------
async function main() {
  const toVersion = process.argv.includes('--to=v1') ? 'v1' : 'v2';
  const client = getClient();
  await printConnection();
  await runSwitch(client, { toVersion });
}

runIfEntry(import.meta.url, main);
