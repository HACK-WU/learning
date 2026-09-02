import { naming } from '../config/index.js';

/**
 * 查询构造：把"用户想搜什么"翻译成 Query DSL。
 *
 * 三条来自课 6 / 课 7 的硬规矩：
 * 1. **打分的条件放 must，筛选的条件放 filter** —— filter 不打分也不影响分数（实测 1.6706 → 0.7262）
 * 2. **指定了 sort，_score 就变 null** —— 所以"按相关性"时必须不写 sort
 * 3. **text 字段用 match / multi_match，keyword 字段用 term / terms** —— 反过来必然 0 条
 */
export function buildBody({
  keyword,
  brands,
  categories,
  priceMin,
  priceMax,
  minRating,
  sort = 'relevance',
  boostSales = false,
  size = 10,
  from = 0
}) {
  const must = [];
  const filter = [];

  // —— 打分部分：全文检索 ——
  if (keyword) {
    must.push({
      multi_match: {
        query: keyword,
        fields: ['title^3', 'description'], // 标题权重是正文的 3 倍（课 7 实测 boost 乘在 2.2 上）
        type: 'best_fields',
        minimum_should_match: '75%' // 避免长尾词把噪声拉进来
      }
    });
  }
  if (must.length === 0) must.push({ match_all: {} });

  // —— 筛选部分：不参与打分 ——
  if (brands?.length) filter.push({ terms: { brand: brands } });
  if (categories?.length) filter.push({ terms: { category: categories } });
  if (priceMin != null || priceMax != null) {
    const range = {};
    if (priceMin != null) range.gte = priceMin;
    if (priceMax != null) range.lte = priceMax;
    filter.push({ range: { price: range } });
  }
  if (minRating != null) filter.push({ range: { rating: { gte: minRating } } });

  let query = { bool: { must, filter } };

  // —— 可选：按销量加权 ——
  // boost_mode: multiply 是"只放大不颠覆"（课 7 实测：BM25 分太低的商品加权后仍排后面）
  // 想让销量主导排序要改成 replace
  if (boostSales) {
    query = {
      function_score: {
        query,
        field_value_factor: { field: 'sales', modifier: 'log1p', factor: 0.5 },
        boost_mode: 'multiply'
      }
    };
  }

  const body = {
    size,
    from,
    query,
    _source: ['sku', 'title', 'brand', 'category', 'price', 'sales', 'rating', 'tags']
  };

  // 高亮：默认 encoder 会做 HTML 转义，别改成 html（课 7：否则有 XSS 风险）
  if (keyword) {
    body.highlight = {
      pre_tags: ['【'],
      post_tags: ['】'],
      fields: {
        title: {},
        description: { fragment_size: 60, number_of_fragments: 1 }
      }
    };
  }

  // 排序：指定了 sort 之后 _score 会变 null，这是设计而非 bug（课 7 实测）
  if (sort === 'sales') body.sort = [{ sales: 'desc' }, { sku: 'asc' }];
  else if (sort === 'price_asc') body.sort = [{ price: 'asc' }, { sku: 'asc' }];
  else if (sort === 'price_desc') body.sort = [{ price: 'desc' }, { sku: 'asc' }];
  // relevance：不写 sort，让 ES 按 _score 排

  return body;
}

/** 执行搜索，顺带记录耗时与命中总数 */
export async function runSearch(client, opts) {
  const body = buildBody(opts);
  const started = Date.now();
  const res = await client.search({ index: naming.alias, ...body });
  const wallMs = Date.now() - started;
  return {
    total: typeof res.hits.total === 'number' ? res.hits.total : res.hits.total.value,
    hits: res.hits.hits,
    esTookMs: res.took,
    wallMs,
    body
  };
}
