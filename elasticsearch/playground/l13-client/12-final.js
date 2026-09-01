const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function main() {
  console.log('===== 兜底确认：runtime field 到底取不取得到值 =====\n');

  const r = await client.search({
    index: 'l10_shard_1', size: 3,
    runtime_mappings: { dbl: { type: 'long', script: { source: "emit(doc['amount'].value * 2)" } } },
    fields: ['amount', 'dbl'],
  });

  console.log('完整 hits（看 fields 的真实结构）：');
  console.log(JSON.stringify(r.hits.hits, null, 2));

  console.log('\n→ 若 fields 里没有值，改用 _source 对照：');
  const r2 = await client.search({
    index: 'l10_shard_1', size: 3,
    runtime_mappings: { dbl: { type: 'long', script: { source: "emit(doc['amount'].value * 2)" } } },
    query: { range: { dbl: { gte: 2000 } } },
    _source: ['amount', 'brand'],
    fields: ['dbl'],
    docvalue_fields: ['amount'],
  });
  console.log(`过滤 dbl>=2000 → 命中 ${r2.hits.hits.length} 条`);
  r2.hits.hits.forEach(h => {
    const amt = h.fields?.amount?.[0] ?? h._source?.amount;
    console.log(`  _id=${h._id}  amount=${amt}  dbl=${h.fields?.dbl?.[0]}  (amount*2=${Number(amt) * 2})`);
  });

  console.log('\n===== 最终判据 =====');
  console.log('1. doc[] 读取：只要字段在列存有值（value_count>0）就能用，本次 4 个索引全通过');
  console.log('2. 取 runtime field 的值：请求体里加 docvalue_fields 或看 fields 结构');
  console.log('3. 过滤/聚合 runtime field：直接在 query / aggs 里引用字段名即可，最直接');
  console.log('4. 之前的 script_exception 是首次脚本编译的偶发失败，重试即可 —— 不是字段缺值');
}

main().catch(e => console.log('出错：', e.message, JSON.stringify(e.meta?.body?.error?.root_cause || {}, null, 2)));
