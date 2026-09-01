const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function main() {
  console.log('===== runtime field 真相：为什么 doc[\'amount\'] 报错 =====\n');

  // 查 l9_orders 的 amount 字段到底有没有 doc_values 数据
  const r = await client.search({
    index: 'l9_orders', size: 0,
    aggs: { has_amount: { exists: { field: 'amount' } }, total: { value_count: { field: 'amount' } } },
  });
  console.log('l9_orders 中 amount 字段：');
  console.log(`  exists 聚合命中：${r.aggregations.has_amount.doc_count} 条（总文档 24 条）`);
  console.log(`  value_count 聚合：${r.aggregations.total.value} 个值`);
  console.log('  → 若 exists=0，说明 amount 虽在映射里，但 doc_values 里没数据。');
  console.log('    原因：amount 是【后来动态映射加进去】的，早先写入的文档没被重新索引，');
  console.log('    倒排索引/列存里就没有它 → doc[\'amount\'].value 取不到 → script_exception。\n');

  // 用一个字段从一开始就存在的干净索引验证
  console.log('===== 对照：在干净索引 l9_hi 上重做同一实验 =====\n');
  const m = await client.indices.getMapping({ index: 'l9_hi' });
  const props = m.l9_hi.mappings.properties || {};
  console.log('l9_hi 映射字段：', Object.entries(props).map(([k, v]) => `${k}(${v.type})`).join(', '));

  const numField = Object.entries(props).find(([, v]) => ['integer', 'long', 'double', 'float'].includes(v.type));
  if (!numField) { console.log('（l9_hi 无数值字段，跳过）'); }
  else {
    const [fname] = numField;
    const chk = await client.search({
      index: 'l9_hi', size: 0,
      aggs: { c: { value_count: { field: fname } } },
    });
    console.log(`\n${fname} 的 value_count = ${chk.aggregations.c.value}（有数据才走得通 doc[]）`);

    try {
      const r2 = await client.search({
        index: 'l9_hi', size: 3,
        runtime_mappings: { dbl: { type: 'long', script: { source: `emit(doc['${fname}'].value * 2)` } } },
        fields: [fname, 'dbl'],
      });
      console.log(`✅ doc[] 写法在 l9_hi 上成功（${r2.hits.hits.length} 条）：`);
      r2.hits.hits.forEach(h => console.log(`   _id=${h._id} ${fname}=${h.fields?.[fname]?.[0]}  doubled=${h.fields?.dbl?.[0]}`));
      console.log('\n→ 真相：runtime field 的 doc[] 写法本身没问题，');
      console.log('  是 l9_orders 这批文档的 amount 在列存里没值导致的。');
      console.log('  判据：跑 exists / value_count 聚合，count=0 就说明 doc[] 读不到。');
    } catch (e) {
      console.log('l9_hi 上 doc[] 也失败：', (e.meta?.body?.error?.root_cause?.[0]?.reason || e.message).split('\n')[0]);
    }
  }

  console.log('\n===== 给读者的排查口诀 =====');
  console.log('runtime field 报 script_exception 时，按这个顺序查：');
  console.log('  1. 字段名拼对了吗？（映射里叫 embedding 还是 my_vector）');
  console.log('  2. 该字段在列存里有值吗？（exists / value_count 聚合验证）');
  console.log('  3. 还是不行 → 改用 params._source 写法（慢但一定能读到）');
}

main().catch(e => console.log('出错：', e.message));
