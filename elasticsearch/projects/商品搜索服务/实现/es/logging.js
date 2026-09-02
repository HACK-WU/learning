import { getClient } from './client.js';
import { naming } from '../config/index.js';

/**
 * 写一条搜索日志到数据流 cap_search_logs。
 *
 * 两个知识点落地：
 * 1. 数据流（Data Stream）：写入时只需写数据流名，ES 自动路由到当前后备索引（课 13 实测）
 * 2. ILM：后备索引由策略自动滚动 / 合段 / 过期删除，不用人管（课 13 + 课 15）
 *
 * ⚠️ 数据流文档必须带 @timestamp，否则写入会被拒。
 */
export async function writeSearchLog({ keyword, brand, category, total, tookMs, sort }) {
  const client = getClient();
  await client.index({
    index: naming.logsStream,
    document: {
      '@timestamp': new Date().toISOString(),
      keyword: keyword ?? '',
      brand: brand ?? '',
      category: category ?? '',
      total: total ?? 0,
      took_ms: tookMs ?? 0,
      sort: sort ?? '_score'
    }
  });
}

/** 读回最近几条日志，验证数据流确实在接数据 */
export async function recentLogs(size = 5) {
  const client = getClient();
  const res = await client.search({
    index: naming.logsStream,
    size,
    sort: [{ '@timestamp': { order: 'desc' } }]
  });
  return res.hits.hits.map((h) => h._source);
}
