const { Client } = require('@elastic/elasticsearch');
const client = new Client({ node: 'http://localhost:9201' });

async function countValues(index, field) {
  try {
    const r = await client.search({
      index, size: 0,
      aggs: { c: { value_count: { field } } },
    });
    return r.aggregations.c.value;
  } catch (e) {
    return `报错(${e.meta?.body?.error?.root_cause?.[0]?.type || 'unknown'})`;
  }
}

async function tryRuntimeDoc(index, field) {
  try {
    const r = await client.search({
      index, size: 3,
      runtime_mappings: { dbl: { type: 'long', script: { source: `emit(doc['${field}'].value * 2)` } } },
      fields: [field, 'dbl'],
    });
    const first = r.hits.hits[0];
    return `✅ 成功，${field}=${first?.fields?.[field]?.[0]} → doubled=${first?.fields?.dbl?.[0]}`;
  } catch (e) {
    const rc = e.meta?.body?.error?.root_cause?.[0];
    return `❌ ${rc?.type || 'error'}`;
  }
}

async function main() {
  console.log('===== runtime field 真相：doc[] 能不能读，取决于列存里有没有值 =====\n');

  console.log('索引'.padEnd(16) + '字段'.padEnd(14) + 'value_count'.padEnd(14) + 'doc[] 写法');
  console.log('-'.repeat(72));

  const cases = [
    ['l9_orders', 'amount'],
    ['l9_orders', 'price'],
    ['l9_hi', 'amount'],
    ['l10_shard_1', 'amount'],
  ];

  for (const [idx, f] of cases) {
    const m = await client.indices.getMapping({ index: idx });
    const props = m[idx].mappings.properties || {};
    if (!props[f]) { console.log(idx.padEnd(16) + f.padEnd(14) + '(字段不存在)'); continue; }
    const c = await countValues(idx, f);
    const r = await tryRuntimeDoc(idx, f);
    console.log(idx.padEnd(16) + f.padEnd(14) + String(c).padEnd(14) + r);
  }

  console.log('\n===== 结论 =====');
  console.log('value_count = 0 的字段 → doc[] 读不到 → runtime field 报 script_exception');
  console.log('value_count > 0 的字段 → doc[] 正常 → runtime field 正常');
  console.log('\n判据口诀：先用 value_count 聚合探一下，count=0 就别用 doc[]，改 params._source。');
}

main().catch(e => console.log('出错：', e.message));
