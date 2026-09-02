import { getClient, printConnection } from '../es/client.js';
import { runIfEntry } from '../es/cli.js';
import { writeSearchLog } from '../es/logging.js';
import { runSearch } from './query.js';
import { DEMO_QUERIES, resolveKeyword } from './keywords.js';

/**
 * 搜索 CLI：
 *   npm run search                               用内置示例查询（Windows 上最稳）
 *   npm run search -- --keyword-file=q.txt       从 UTF-8 文件读关键词（脚本/自动化推荐）
 *   npm run search -- 苹果手机                    直接传（PowerShell 5.1 下中文可能失真）
 *   npm run search -- 手机 --min-rating=4.5 --sort=sales
 *   npm run search -- 手机 --boost-sales          （按销量加权）
 *
 * 可用参数：--brand= --category= --min-price= --max-price= --min-rating=
 *          --sort=relevance|sales|price_asc|price_desc  --size=  --boost-sales
 *
 * 全部内置示例查询：DEMO_QUERIES = 苹果手机 / 小米笔记本 / 降噪耳机 / 商务办公
 */
function parseArgs(argv) {
  const opts = { keyword: '', brands: [], categories: [] };
  const list = (v) => (v ? v.split(',').map((s) => s.trim()).filter(Boolean) : []);
  for (const a of argv) {
    if (a.startsWith('--brand=')) opts.brands = list(a.slice(8));
    else if (a.startsWith('--category=')) opts.categories = list(a.slice(11));
    else if (a.startsWith('--min-price=')) opts.priceMin = Number(a.slice(12));
    else if (a.startsWith('--max-price=')) opts.priceMax = Number(a.slice(12));
    else if (a.startsWith('--min-rating=')) opts.minRating = Number(a.slice(13));
    else if (a.startsWith('--sort=')) opts.sort = a.slice(7);
    else if (a.startsWith('--size=')) opts.size = Number(a.slice(7));
    else if (a === '--boost-sales') opts.boostSales = true;
    else if (!a.startsWith('--')) opts.keyword = a;
  }
  return opts;
}

async function main() {
  const argv = process.argv.slice(2);
  const opts = parseArgs(argv);
  const { keyword, source } = resolveKeyword(argv);
  opts.keyword = keyword;
  const client = getClient();
  await printConnection();

  const filters = {
    brand: opts.brands.join('/') || '',
    category: opts.categories.join('/') || ''
  };

  console.log(`\n🔎 搜索：keyword="${opts.keyword || '(空)'}"（来源：${source}）${opts.brands.length ? ` brand=${opts.brands}` : ''}${opts.categories.length ? ` category=${opts.categories}` : ''} sort=${opts.sort ?? 'relevance'}${opts.boostSales ? ' +销量加权' : ''}`);

  const r = await runSearch(client, opts);

  console.log(`\n   命中 ${r.total} 条 ｜ ES 内部耗时 ${r.esTookMs}ms ｜ 端到端 ${r.wallMs}ms`);
  console.log('   ' + '─'.repeat(76));

  for (const [i, hit] of r.hits.entries()) {
    const s = hit._source;
    // 排序后 _score 为 null（课 7 实测），这里如实展示
    const score = hit._score == null ? 'null(已指定排序)' : hit._score.toFixed(4);
    console.log(`   ${String(i + 1).padStart(2)}. [${score}] ${s.title}`);
    console.log(`       ${s.brand} / ${s.category} ｜ ¥${s.price} ｜ 销量 ${s.sales} ｜ 评分 ${s.rating}`);
    const hl = hit.highlight?.title?.[0];
    if (hl) console.log(`       高亮：${hl}`);
  }

  console.log('   ' + '─'.repeat(76));
  if (opts.sort && opts.sort !== 'relevance') {
    console.log('   💡 指定了 sort，_score 变 null —— ES 认为你不需要相关性了，索性不算（课 7 实测）');
  }
  if (opts.boostSales) {
    console.log('   💡 boost_mode=multiply 只放大不颠覆：BM25 分太低的商品，加权后依然排后面（课 7 实测）');
  }

  // 写一条搜索日志进数据流（演示 ILM + 自动滚动）
  await writeSearchLog({
    keyword: opts.keyword,
    brand: opts.brands.join(','),
    category: opts.categories.join(','),
    total: r.total,
    tookMs: r.esTookMs,
    sort: opts.sort ?? 'relevance'
  });
  console.log(`   📝 已写入搜索日志数据流 cap_search_logs`);
}

runIfEntry(import.meta.url, main);
