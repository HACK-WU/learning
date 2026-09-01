const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

// 真实感的查询：关键词过滤 + 数值范围 + 排序 + 聚合
// 字段是课10建索引时定好的：brand(keyword) / amount(integer)
const body = {
  size: 10,
  query: { bool: {
    filter: [
      { term: { brand: 'BRAND-7' } },
      { range: { amount: { gte: 0 } } },
    ],
  }},
  sort: [{ amount: 'asc' }],
  aggs: { avg_amount: { avg: { field: 'amount' } } },
};

async function bench(index, rounds = 30) {
  for (let i = 0; i < 5; i++) await client.search({ index, ...body }); // 预热
  const times = [];
  for (let i = 0; i < rounds; i++) {
    const t0 = process.hrtime.bigint();
    await client.search({ index, ...body });
    times.push(Number(process.hrtime.bigint() - t0) / 1e6);
  }
  times.sort((a, b) => a - b);
  return {
    p50: times[Math.floor(rounds * 0.5)].toFixed(2),
    p95: times[Math.floor(rounds * 0.95)].toFixed(2),
    min: times[0].toFixed(2),
  };
}

async function main() {
  console.log('===== 课14 实测：分片数对查询延迟的影响 =====');
  console.log('三个索引各 3000 条相同数据，唯一变量是主分片数\n');
  console.log('索引'.padEnd(16) + '主分片'.padEnd(8) + 'p50(ms)'.padEnd(11) + 'p95(ms)'.padEnd(11) + 'min(ms)');
  console.log('-'.repeat(56));
  for (const [idx, s] of [['l10_shard_1','1'], ['l10_shard_3','3'], ['l10_shard_50','50']]) {
    const r = await bench(idx);
    console.log(idx.padEnd(16) + s.padEnd(8) + r.p50.padEnd(11) + r.p95.padEnd(11) + r.min);
  }

  console.log('\n===== 分片开销的静态证据（同样 3000 条）=====');
  const raw = await client.cat.indices({ index: 'l10_shard_*', format: 'json', h: 'index,pri,docs.count,pri.store.size' });
  let rows = raw?.body;
  if (typeof rows === 'string') rows = rows.trim().split('\n').map(l => l.trim().split(/\s+/)).map(([index, pri, docs, size]) => ({ index, pri, 'docs.count': docs, 'pri.store.size': size }));
  if (!Array.isArray(rows)) { console.log('（无法解析 cat.indices 返回，类型=' + typeof raw?.body + '）'); }
  else {
    console.log('索引'.padEnd(16) + '主分片'.padEnd(8) + '文档数'.padEnd(10) + '主分片存储');
    console.log('-'.repeat(48));
    rows.slice().sort((a, b) => Number(a.pri) - Number(b.pri)).forEach(r => {
      console.log(String(r.index).padEnd(16) + String(r.pri).padEnd(8) + String(r['docs.count']).padEnd(10) + r['pri.store.size']);
    });
  }

  console.log('\n===== 结论 =====');
  console.log('同样 3000 条数据：');
  console.log('  · 50 分片的存储开销显著大于 1 分片（每个分片都有固定开销）');
  console.log('  · 但查询延迟未必更快，甚至更慢');
  console.log('这就是"分片不是越多越好" —— 官方文档建议单分片 20-50GB，');
  console.log('小数据量时多分片纯属浪费。');
}

main().catch(e => { console.log('出错:', e.message); console.log(JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2)); });
