import { getClient, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { naming, priceRanges } from '../config/index.js';
import { DEMO_BRAND, resolveKeyword } from './keywords.js';

/**
 * 分面统计（Faceted Search）：左边一排"品牌 / 分类 / 价格段"的计数是怎么来的。
 *
 * 两个关键设计：
 *
 * 1. **分面字段必须是 keyword**。text 会被分词，"苹果"变成"苹""果"两个桶（课 8 实测 6 个碎桶）。
 *
 * 2. **用 post_filter 而不是 filter**。
 *    区别很实在：如果把"品牌=苹果"放进 query 的 filter，那品牌分面里就只剩苹果一个桶，
 *    用户没法看到"华为还有 8 件"，也就没法一键改选华为。
 *    post_filter 只作用于返回的 hits，不影响聚合 —— 所以分面计数始终基于"除品牌外的其他条件"。
 */
export function buildFacetsBody({ keyword, brands, categories, priceMin, priceMax, minRating }) {
  const must = [];
  const queryFilter = [];
  const postFilter = [];

  if (keyword) {
    must.push({
      multi_match: {
        query: keyword,
        fields: ['title^3', 'description'],
        type: 'best_fields',
        minimum_should_match: '75%'
      }
    });
  }
  if (must.length === 0) must.push({ match_all: {} });

  // 价格 / 评分：既筛结果，也筛分面（这两个维度通常不需要"反选"）
  if (priceMin != null || priceMax != null) {
    const range = {};
    if (priceMin != null) range.gte = priceMin;
    if (priceMax != null) range.lte = priceMax;
    queryFilter.push({ range: { price: range } });
  }
  if (minRating != null) queryFilter.push({ range: { rating: { gte: minRating } } });

  // 品牌 / 分类：用 post_filter，让分面仍能显示其他选项的数量
  if (brands?.length) postFilter.push({ terms: { brand: brands } });
  if (categories?.length) postFilter.push({ terms: { category: categories } });

  return {
    size: 3, // 只要几条样例
    query: { bool: { must, filter: queryFilter } },
    ...(postFilter.length ? { post_filter: { bool: { filter: postFilter } } } : {}),
    aggs: {
      品牌: {
        terms: { field: 'brand', size: 20 },
        aggs: {
          均价: { avg: { field: 'price' } },
          最高销量: { max: { field: 'sales' } }
        }
      },
      分类: { terms: { field: 'category', size: 20 } },
      价格段: { range: { field: 'price', ranges: priceRanges } },
      价格总览: { stats: { field: 'price' } },
      热门标签: { terms: { field: 'tags', size: 10 } }
    }
  };
}

export async function runFacets(client, opts) {
  const body = buildFacetsBody(opts);
  const res = await client.search({ index: naming.alias, ...body });
  return { res, body };
}

async function main() {
  const argv = process.argv.slice(2);
  const opts = { keyword: '', brands: [], categories: [] };
  for (const a of argv) {
    if (a.startsWith('--brand=')) opts.brands = a.slice(8).split(',').filter(Boolean);
    else if (a.startsWith('--category=')) opts.categories = a.slice(11).split(',').filter(Boolean);
  }
  const { keyword, source } = resolveKeyword(argv, { fallback: '手机' });
  opts.keyword = keyword;
  // 品牌同样有中文编码问题，所以除了 --brand= 之外再给一个内置开关
  if (argv.includes('--demo-brand')) opts.brands = [DEMO_BRAND];

  const client = getClient();
  await printConnection();

  console.log(`\n📊 分面统计：keyword="${opts.keyword || '(空)'}"（来源：${source}）${opts.brands.length ? ` brand=${opts.brands}` : ''}${opts.categories.length ? ` category=${opts.categories}` : ''}`);

  const { res } = await runFacets(client, opts);
  const aggs = res.aggregations;

  console.log(`\n   命中（post_filter 之后）${typeof res.hits.total === 'number' ? res.hits.total : res.hits.total.value} 条，样例：`);
  for (const h of res.hits.hits) {
    console.log(`     - ${h._source.title}（¥${h._source.price}）`);
  }

  const showTerms = (name, unit = '件') => {
    console.log(`\n   【${name}】`);
    for (const b of aggs[name].buckets) {
      const extra = b['均价'] ? ` ｜ 均价 ¥${Math.round(b['均价'].value)} ｜ 最高销量 ${b['最高销量'].value}` : '';
      console.log(`     ${b.key.padEnd(8)} ${String(b.doc_count).padStart(3)} ${unit}${extra}`);
    }
    // sum_other_doc_count > 0 就是"漏桶"信号（课 8 实测：默认只返回 Top 10）
    if (aggs[name].sum_other_doc_count > 0) {
      console.log(`     ⚠️  还有 ${aggs[name].sum_other_doc_count} 件被截断（调大 size 或提高 shard_size）`);
    }
    if (aggs[name].doc_count_error_upper_bound > 0) {
      console.log(`     ⚠️  跨分片误差上界 ${aggs[name].doc_count_error_upper_bound}（分片越多误差越大，课 9 / 课 14 实测）`);
    }
  };

  showTerms('品牌');
  showTerms('分类');
  showTerms('热门标签');

  console.log('\n   【价格段】');
  for (const b of aggs['价格段'].buckets) {
    const from = b.from == null ? '' : `${b.from}`;
    const to = b.to == null ? '' : `${b.to}`;
    console.log(`     ${b.key.padEnd(12)} ${String(b.doc_count).padStart(3)} 件   [${from}, ${to})`);
  }

  const st = aggs['价格总览'];
  console.log(`\n   价格总览：${st.count} 件 ｜ 最低 ¥${st.min} ｜ 最高 ¥${st.max} ｜ 均价 ¥${st.avg.toFixed(2)}`);

  console.log('\n   💡 分面全部用 keyword 字段：换成 text 会被 IK 切碎，"苹果"变成"苹""果"两个桶（课 8 实测）');
}

runIfEntry(import.meta.url, main);
