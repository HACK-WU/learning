const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function main() {
  console.log('===== 复核1：kNN 为什么命中 0 条？=====\n');

  const map = await client.indices.getMapping({ index: 'l13_vector_demo' });
  console.log('映射：', JSON.stringify(map.l13_vector_demo.mappings.properties, null, 2));

  const one = await client.search({ index: 'l13_vector_demo', size: 2 });
  console.log('\n前 2 条文档的向量：');
  one.hits.hits.forEach(h => console.log(`  _id=${h._id}  ${JSON.stringify(h._source)}`));

  console.log('\n分别用不同 query_vector 试：');
  for (const qv of [[1.0, 0.0, 0.0], [0.99, 0.14, 0.0], [0.5, 0.5, 0.5]]) {
    try {
      const r = await client.search({
        index: 'l13_vector_demo', size: 3,
        knn: { field: 'my_vector', query_vector: qv, k: 3, num_candidates: 10 },
      });
      const top = r.hits.hits.map(h => `${h._id}(${(h._score ?? 0).toFixed(4)})`).join(', ');
      console.log(`  query_vector=${JSON.stringify(qv).padEnd(20)} → 命中 ${r.hits.hits.length} 条: ${top}`);
    } catch (e) {
      console.log(`  query_vector=${JSON.stringify(qv)} → 报错 ${e.meta?.body?.error?.type}`);
    }
  }

  const cnt = await client.count({ index: 'l13_vector_demo' });
  console.log(`\n索引总文档数：${cnt.count} 条`);
  console.log('→ 说明：k=1 时若 hits.total.value 报 0，是 ES 9.x kNN 的 total 行为，');
  console.log('  实际 hits.hits 数组里是有结果的。看 hits.hits.length 才准。');

  console.log('\n\n===== 复核2：runtime field 为什么返回 undefined？=====\n');

  const r2 = await client.search({
    index: 'l9_orders', size: 2,
    runtime_mappings: { amount_doubled: { type: 'long', script: { source: "emit(doc['amount'].value * 2)" } } },
    fields: ['amount_doubled'],
  });
  console.log('完整返回（前 2 条）：');
  console.log(JSON.stringify(r2.hits.hits, null, 2));

  console.log('\n换一种写法：把 runtime field 放进 query 里做 range 过滤');
  const r3 = await client.search({
    index: 'l9_orders', size: 3,
    runtime_mappings: { amount_doubled: { type: 'long', script: { source: "emit(doc['amount'].value * 2)" } } },
    query: { range: { amount_doubled: { gte: 1000 } } },
    fields: ['amount', 'amount_doubled'],
  });
  console.log(`  过滤 amount_doubled>=1000 → 命中 ${r3.hits.hits.length} 条`);
  r3.hits.hits.forEach(h => {
    console.log(`    _id=${h._id} amount=${h._source?.amount ?? h.fields?.amount?.[0]} doubled=${h.fields?.amount_doubled?.[0]}`);
  });
}

main().catch(e => console.log('出错：', e.message, JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2)));
