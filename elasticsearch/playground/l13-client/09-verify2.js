const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function main() {
  console.log('===== 复核（修正版）=====\n');

  console.log('【修正1】向量字段真名是 embedding，不是 my_vector\n');
  for (const qv of [[1.0, 0.0, 0.0], [0.99, 0.14, 0.0], [0.5, 0.5, 0.5]]) {
    const r = await client.search({
      index: 'l13_vector_demo', size: 3,
      knn: { field: 'embedding', query_vector: qv, k: 3, num_candidates: 10 },
    });
    const top = r.hits.hits.map(h => `${h._source?.title}(${(h._score ?? 0).toFixed(4)})`).join('  ');
    console.log(`  ${JSON.stringify(qv).padEnd(20)} → ${r.hits.hits.length} 条: ${top}`);
  }
  console.log('  → 结论：字段名写错会静默返回 0 条，不报错。这是 kNN 最阴的坑。\n');

  console.log('【修正2】runtime field：先看 l9_orders 到底有哪些字段\n');
  const m = await client.indices.getMapping({ index: 'l9_orders' });
  console.log('  映射字段：', Object.keys(m.l9_orders.mappings.properties || {}).join(', '));
  const s = await client.search({ index: 'l9_orders', size: 1 });
  console.log('  样本 _source：', JSON.stringify(s.hits.hits[0]?._source));
  console.log('  → 注意：映射里没有 amount，但 _source 里有。');
  console.log('    doc[...] 只能读【映射中声明】的字段，所以 doc[\'amount\'] 报 script_exception。\n');

  console.log('【修正2b】改用映射中真实存在的字段（order_id 是 keyword 吗？先看）\n');
  const props = m.l9_orders.mappings.properties || {};
  const numericField = Object.entries(props).find(([, v]) => ['integer', 'long', 'double', 'float'].includes(v.type));
  console.log('  找到数值字段：', numericField ? `${numericField[0]} (${numericField[1].type})` : '无');

  if (numericField) {
    const [fname] = numericField;
    try {
      const r = await client.search({
        index: 'l9_orders', size: 3,
        runtime_mappings: { doubled: { type: 'long', script: { source: `emit(doc['${fname}'].value * 2)` } } },
        query: { range: { doubled: { gte: 1000 } } },
        fields: [fname, 'doubled'],
      });
      console.log(`  ✅ runtime field 成功：过滤 doubled>=1000 命中 ${r.hits.hits.length} 条`);
      r.hits.hits.forEach(h => console.log(`     _id=${h._id} ${fname}=${h.fields?.[fname]?.[0]} doubled=${h.fields?.doubled?.[0]}`));
    } catch (e) {
      console.log('  仍失败：', (e.meta?.body?.error?.root_cause?.[0]?.reason || e.message).split('\n')[0]);
    }
  }

  console.log('\n【补充】runtime field 读 _source 的正确写法（绕过 doc[] 限制）\n');
  try {
    const r = await client.search({
      index: 'l9_orders', size: 3,
      runtime_mappings: {
        amount_x2: {
          type: 'long',
          script: { source: "if (params._source.containsKey('amount')) { emit(params._source['amount'] * 2); }" },
        },
      },
      fields: ['amount_x2'],
    });
    console.log(`  ✅ 用 params._source 写法成功，返回 ${r.hits.hits.length} 条：`);
    r.hits.hits.forEach(h => console.log(`     _id=${h._id} amount_x2=${h.fields?.amount_x2?.[0]}`));
    console.log('  → 关键区别：doc[] 读倒排索引（快，但只读映射字段）；');
    console.log('    params._source 读原始 JSON（慢，但不受映射限制）。');
  } catch (e) {
    console.log('  失败：', (e.meta?.body?.error?.root_cause?.[0]?.reason || e.message).split('\n')[0]);
  }
}

main().catch(e => console.log('出错：', e.message));
