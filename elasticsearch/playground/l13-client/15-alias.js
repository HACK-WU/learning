// 课 15《索引管理与生命周期策略》实测 · 第 2 组：别名的四种玩法
// 目标：零停机切换 / 过滤别名 / 写索引路由 / 别名不是索引
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')
const sleep = (ms) => new Promise(r => setTimeout(r, ms))

async function cleanup() {
  for (const p of ['l15_shop_v1', 'l15_shop_v2', 'l15_multi_a', 'l15_multi_b', 'l15_alias_test']) {
    try { await client.indices.delete({ index: p }) } catch (e) {}
  }
}

async function main() {
  await cleanup()

  sep('1. 建两个版本的索引（模拟改了映射要重建索引）')
  await client.indices.create({
    index: 'l15_shop_v1',
    settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { name: { type: 'text' }, price: { type: 'integer' } } },
  })
  await client.indices.create({
    index: 'l15_shop_v2',
    settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { name: { type: 'text' }, price: { type: 'scaled_float', scaling_factor: 100 } } },
  })
  await client.bulk({
    refresh: true,
    operations: [
      { index: { _index: 'l15_shop_v1', _id: '1' } }, { name: '苹果', price: 5 },
      { index: { _index: 'l15_shop_v1', _id: '2' } }, { name: '香蕉', price: 3 },
      { index: { _index: 'l15_shop_v1', _id: '3' } }, { name: '车厘子', price: 88 },
      { index: { _index: 'l15_shop_v2', _id: '1' } }, { name: '苹果', price: 5.5 },
      { index: { _index: 'l15_shop_v2', _id: '2' } }, { name: '香蕉', price: 3.25 },
      { index: { _index: 'l15_shop_v2', _id: '3' } }, { name: '车厘子', price: 88.8 },
    ],
  })
  log('v1（price=integer，小数被截断）与 v2（price=scaled_float，保留两位）各 3 条已写入')

  sep('2. 应用只认别名，不认真实索引名')
  await client.indices.putAlias({ index: 'l15_shop_v1', name: 'l15_shop' })
  let r = await client.search({ index: 'l15_shop', query: { match_all: {} } })
  log('搜别名 l15_shop 命中 =', r.hits.total.value, '条；_index =', r.hits.hits[0]._index)
  log('第一条 price =', r.hits.hits[0]._source.price)

  sep('3. 原子切换：一次请求里 remove + add')
  await client.indices.updateAliases({
    actions: [
      { remove: { index: 'l15_shop_v1', alias: 'l15_shop' } },
      { add: { index: 'l15_shop_v2', alias: 'l15_shop' } },
    ],
  })
  r = await client.search({ index: 'l15_shop', query: { match_all: {} } })
  log('切换后命中 =', r.hits.total.value, '条；_index =', r.hits.hits[0]._index)
  log('切换后第一条 price =', r.hits.hits[0]._source.price, ' ← 小数回来了')

  sep('4. 过滤别名：同一个索引，给不同人看不同的数据')
  await client.indices.updateAliases({
    actions: [{ add: { index: 'l15_shop_v2', alias: 'l15_shop_cheap', filter: { range: { price: { lt: 10 } } } } }],
  })
  const all = await client.search({ index: 'l15_shop_v2', query: { match_all: {} } })
  const cheap = await client.search({ index: 'l15_shop_cheap', query: { match_all: {} } })
  log('不带过滤（索引本体）命中 =', all.hits.total.value, '条')
  log('过滤别名（price < 10）命中 =', cheap.hits.total.value, '条：',
    cheap.hits.hits.map(h => h._source.name + '(' + h._source.price + ')').join(' '))
  const filtered = await client.search({
    index: 'l15_shop_cheap',
    query: { bool: { filter: [{ range: { price: { gte: 10 } } }] } },
  })
  log('再叠加 price >= 10 的查询 → 命中', filtered.hits.total.value, '条（别名的过滤先生效）')

  sep('5. 写索引：一个别名指向多个索引时，写入往哪去？')
  await client.indices.create({ index: 'l15_multi_a', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.create({ index: 'l15_multi_b', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  await client.indices.updateAliases({
    actions: [
      { add: { index: 'l15_multi_a', alias: 'l15_multi' } },
      { add: { index: 'l15_multi_b', alias: 'l15_multi' } },
    ],
  })
  try {
    await client.index({ index: 'l15_multi', id: 'x', document: { a: 1 } })
    log('未指定 is_write_index 时写入成功（不该成功）')
  } catch (e) {
    log('未指定 is_write_index 时写入报错：')
    log('  →', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  await client.indices.updateAliases({
    actions: [{ add: { index: 'l15_multi_b', alias: 'l15_multi', is_write_index: true } }],
  })
  await client.index({ index: 'l15_multi', id: 'x', document: { a: 1 }, refresh: true })
  const al = await client.indices.getAlias({ name: 'l15_multi' })
  for (const [idx, info] of Object.entries(al)) {
    log(`${idx} → is_write_index =`, info.aliases['l15_multi'].is_write_index)
  }
  const ma = await client.count({ index: 'l15_multi_a' })
  const mb = await client.count({ index: 'l15_multi_b' })
  log('写入后 l15_multi_a 条数 =', ma.count, ' l15_multi_b 条数 =', mb.count, ' ← 只写到指定的那个')
  const searchAll = await client.search({ index: 'l15_multi', query: { match_all: {} } })
  log('但搜别名仍能跨两个索引，命中 =', searchAll.hits.total.value, '条')

  sep('6. 别名不是索引：对别名做索引级操作会怎样？')
  try {
    await client.indices.putSettings({ index: 'l15_shop', settings: { number_of_replicas: 1 } })
    log('对别名改设置成功（不该成功）')
  } catch (e) {
    log('对别名改设置报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('7. 别名指向不存在的索引时写入会怎样？')
  try {
    await client.index({ index: 'l15_not_exist_alias', document: { a: 1 } })
    log('写入成功（说明索引被自动创建）')
    const chk = await client.indices.exists({ index: 'l15_not_exist_alias' })
    log('索引是否被自动创建 =', chk)
    await client.indices.delete({ index: 'l15_not_exist_alias' })
  } catch (e) {
    log('写入报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('实测结论')
  log('别名是"可替换的门牌号"：切换原子完成，应用代码零改动')
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
