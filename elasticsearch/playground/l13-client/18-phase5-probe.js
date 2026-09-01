// Phase 5 素材取证：把"高频故障"里能在本机复现的几条真跑一遍
// 目的：经验/手册里的"症状—验证—修复"必须有本机证据，不能照抄文档
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')

async function main() {
  // ---- 故障1：text 字段聚合（fielddata）----
  sep('故障 A：对 text 字段做聚合/排序')
  await client.indices.create({
    index: 'p5_fd', settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { title: { type: 'text' } } },
  }).catch(() => {})
  await client.index({ index: 'p5_fd', id: '1', document: { title: 'hello world' }, refresh: true })
  try {
    const r = await client.search({
      index: 'p5_fd', size: 0,
      aggs: { by_title: { terms: { field: 'title' } } },
    })
    log('竟然成功了（不该成功）：', JSON.stringify(r.aggregations).slice(0, 200))
  } catch (e) {
    const b = e.meta?.body?.error
    log('报错 type =', b?.type)
    log('报错 reason =', b?.reason)
    log('root_cause =', JSON.stringify(b?.root_cause?.[0]?.reason))
    if (b?.caused_by) log('caused_by =', b.caused_by.type, '→', b.caused_by.reason)
  }
  // 用 keyword 子字段就好
  try {
    const r2 = await client.search({
      index: 'p5_fd', size: 0,
      aggs: { by_kw: { terms: { field: 'title.keyword' } } },
    })
    log('改用 title.keyword →', r2.aggregations ? '成功（但 title.keyword 其实不存在，看结果）' : '无聚合')
  } catch (e) {
    log('title.keyword 也不行：', e.meta?.body?.error?.caused_by?.reason || e.meta?.body?.error?.reason)
  }

  // ---- 故障2：mapping 冲突 ----
  sep('故障 B：写入与映射不符的数据（mapper_parsing_exception）')
  await client.indices.create({
    index: 'p5_mp', settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { price: { type: 'long' } } },
  }).catch(() => {})
  try {
    await client.index({ index: 'p5_mp', id: '1', document: { price: '很便宜' } })
    log('竟然写入成功（不该成功）')
  } catch (e) {
    const b = e.meta?.body?.error
    log('报错 type =', b?.type)
    log('报错 reason =', b?.reason)
    log('caused_by =', b?.caused_by?.type, '→', b?.caused_by?.reason)
  }
  // ignore_malformed 解法
  await client.indices.putMapping({ index: 'p5_mp', properties: { price2: { type: 'long', ignore_malformed: true } } })
  try {
    await client.index({ index: 'p5_mp', id: '2', document: { price2: '很便宜' }, refresh: true })
    log('加 ignore_malformed 后写入 → 成功（脏值被忽略，字段不入库）')
    const g = await client.get({ index: 'p5_mp', id: '2' })
    log('文档内容 =', JSON.stringify(g._source))
  } catch (e) {
    log('ignore_malformed 后仍失败：', e.meta?.body?.error?.reason)
  }

  // ---- 故障3：深分页 ----
  sep('故障 C：深分页超过 max_result_window')
  await client.indices.create({
    index: 'p5_page', settings: { number_of_shards: 1, number_of_replicas: 0 },
  }).catch(() => {})
  const ops = []
  for (let i = 0; i < 30; i++) {
    ops.push({ index: { _index: 'p5_page', _id: String(i) } }, { n: i })
  }
  await client.bulk({ refresh: true, operations: ops }).catch(() => {})
  const mrwRaw = await client.indices.getSettings({ index: 'p5_page', name: 'index.max_result_window', include_defaults: true })
  const mrwIdx = mrwRaw['p5_page']
  log('index.max_result_window =', mrwIdx.settings?.index?.max_result_window
    || mrwIdx.defaults?.index?.max_result_window
    || JSON.stringify(mrwIdx).slice(0, 200))
  try {
    await client.search({ index: 'p5_page', from: 25, size: 10, query: { match_all: {} } })
    log('from=25 成功（不该成功）')
  } catch (e) {
    const b = e.meta?.body?.error
    log('报错 type =', b?.type)
    log('报错 reason =', b?.reason)
    log('root_cause =', b?.root_cause?.[0]?.reason)
  }
  // search_after 解法
  try {
    const sa = await client.search({
      index: 'p5_page', size: 10,
      query: { match_all: {} },
      sort: [{ n: 'asc' }],
      search_after: [20],
    })
    log('改用 search_after → 成功，命中', sa.hits.hits.length, '条，第一条 n =', sa.hits.hits[0]?._source?.n)
  } catch (e) {
    log('search_after 失败：', e.meta?.body?.error?.reason)
  }

  // ---- 故障4：字段类型冲突（改映射）----
  sep('故障 D：想把 long 改成 text（映射不可变）')
  try {
    await client.indices.putMapping({ index: 'p5_mp', properties: { price: { type: 'text' } } })
    log('改类型成功（不该成功）')
  } catch (e) {
    const b = e.meta?.body?.error
    log('报错 type =', b?.type)
    log('报错 reason =', b?.reason)
  }

  // ---- 故障5：磁盘水位与只读块的参数确认 ----
  sep('故障 E：磁盘水位参数（本次不触发，仅确认阈值）')
  const st = await client.cluster.getSettings({ include_defaults: true })
  const rw = st.defaults?.cluster?.routing?.allocation?.disk?.watermark
  log('watermark =', JSON.stringify(rw))
  const blk = st.defaults?.cluster?.blocks
  log('cluster.blocks.read_only_allow_delete =', st.defaults?.cluster?.blocks?.read_only_allow_delete)

  // ---- 故障6：字段数量爆炸防护 ----
  sep('故障 F：字段爆炸防护参数')
  log('index.mapping.total_fields.limit 默认值 =',
    (await client.indices.getSettings({ index: 'p5_fd', name: 'index.mapping.total_fields.limit', include_defaults: true }))
      ['p5_fd'].settings?.index?.mapping?.total_fields?.limit
    || JSON.stringify((await client.indices.getSettings({ index: 'p5_fd', include_defaults: true }))['p5_fd'].defaults?.index?.mapping?.total_fields || {}))

  // ---- 故障7：bulk 部分失败 ----
  sep('故障 G：bulk 部分失败的表现（errors=true 但成功项已落库）')
  await client.indices.create({
    index: 'p5_bulk', settings: { number_of_shards: 1, number_of_replicas: 0 },
    mappings: { properties: { n: { type: 'integer' } } },
  }).catch(() => {})
  const br = await client.bulk({ refresh: true, operations: [
    { index: { _index: 'p5_bulk', _id: '1' } }, { n: 1 },
    { index: { _index: 'p5_bulk', _id: '2' } }, { n: '不是数字' },
    { index: { _index: 'p5_bulk', _id: '3' } }, { n: 3 },
  ]})
  log('bulk errors =', br.errors)
  for (const it of br.items) {
    const op = it.index || it.create
    log(`  id=${op._id} status=${op.status} ${op.error ? 'ERROR: ' + op.error.type + ' / ' + op.error.reason : 'OK'}`)
  }
  const c = await client.count({ index: 'p5_bulk' })
  log('落库条数 =', c.count, '（3 条里成功 2 条）')

  // ---- 清理 ----
  sep('清理')
  for (const i of ['p5_fd', 'p5_mp', 'p5_page', 'p5_bulk']) {
    try { await client.indices.delete({ index: i }); log('已删', i) } catch (e) { log('删除失败', i, e.message) }
  }
}
main().catch(e => console.error('FAILED:', e.meta?.body?.error?.reason || e.message))
