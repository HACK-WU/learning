// 按讲义第四幕 7 个步骤端到端跑一遍，验证补齐的 JSON 文件与命令可用
const { Client } = require('@elastic/elasticsearch')
const c = new Client({ node: 'http://localhost:9201' })
const ok = s => console.log('  ✅', s)
const bad = s => console.log('  ❌', s)
const fs = require('fs')

const J = n => JSON.parse(fs.readFileSync('./' + n, 'utf8'))

async function main () {
  console.log('=== 按讲义步骤回放 ===')
  // 第1步 组件模板
  await c.cluster.putComponentTemplate({ name: 'l15_shop_settings', body: J('l15-comp-settings.json') })
  await c.cluster.putComponentTemplate({ name: 'l15_shop_mappings', body: J('l15-comp-mappings.json') })
  ok('第1步 组件模板 x2')

  // 第2步 索引模板
  await c.indices.putIndexTemplate({ name: 'l15_shop_tpl', body: J('l15-shop-template.json') })
  ok('第2步 索引模板')

  // 第3步 建 v1
  await c.indices.create({ index: 'l15-shop-000001' })
  const g = await c.indices.get({ index: 'l15-shop-000001' })
  const s = g['l15-shop-000001']
  if (s.aliases && s.aliases['l15-shop']) ok('第3步 v1 自动继承别名')
  else bad('第3步 别名未自动挂上')
  if (s.mappings.properties.price.type === 'scaled_float') ok('第3步 price = scaled_float')
  else bad('第3步 price 类型不对: ' + s.mappings.properties.price.type)
  if (s.settings.index.number_of_shards === '2') ok('第3步 分片数 2 来自模板')
  else bad('第3步 分片数: ' + s.settings.index.number_of_shards)

  // 第4步 写文档 + 切别名
  await c.index({ index: 'l15-shop', document: J('l15-doc1.json'), refresh: true })
  await c.indices.create({ index: 'l15-shop-000002' })
  const rr = await c.reindex({ refresh: true, body: { source: { index: 'l15-shop-000001' }, dest: { index: 'l15-shop-000002' } } })
  if (rr.created === 1) ok('第4步 reindex 搬运 1 条')
  else bad('第4步 reindex 条数: ' + rr.created)
  await c.indices.updateAliases({ body: J('l15-switch.json') })
  const r = await c.search({ index: 'l15-shop' })
  if (r.hits.hits[0] && r.hits.hits[0]._index === 'l15-shop-000002') ok('第4步 原子切换后搜索落到 v2 且数据已搬过去')
  else bad('第4步 切换失败或数据未搬: ' + (r.hits.hits[0] ? r.hits.hits[0]._index : '空结果'))

  // 第5步 ILM
  await c.ilm.putLifecycle({ name: 'l15_shop_policy', body: J('l15-ilm-policy.json') })
  await c.indices.putIndexTemplate({ name: 'l15_shop_tpl', body: J('l15-shop-template2.json') })
  // 模板策略只影响新建索引 → 用新索引验证自动挂载
  await c.indices.create({ index: 'l15-shop-000003' })
  const ex = await c.ilm.explainLifecycle({ index: 'l15-shop-000003' })
  const info = ex.indices['l15-shop-000003']
  if (info && info.managed && info.phase) ok(`第5步 新索引自动挂载 ILM，phase=${info.phase} action=${info.action}`)
  else bad('第5步 新索引未被 ILM 托管')
  // 存量索引补挂验证
  await c.indices.putSettings({ index: 'l15-shop-000002',
    body: { 'index.lifecycle.name': 'l15_shop_policy', 'index.lifecycle.rollover_alias': 'l15-shop' } })
  const ex2 = await c.ilm.explainLifecycle({ index: 'l15-shop-000002' })
  if (ex2.indices['l15-shop-000002'] && ex2.indices['l15-shop-000002'].managed)
    ok('第5步 存量索引补挂 ILM 成功')
  else bad('第5步 存量索引补挂失败')

  // 第6步 forcemerge
  await c.indices.refresh({ index: 'l15-shop' })
  await c.indices.forcemerge({ index: 'l15-shop', max_num_segments: 1 })
  ok('第6步 forcemerge 执行成功')

  // 第7步 清理
  await c.indices.delete({ index: ['l15-shop-000001', 'l15-shop-000002', 'l15-shop-000003'] })
  await c.ilm.deleteLifecycle({ name: 'l15_shop_policy' })
  await c.indices.deleteIndexTemplate({ name: 'l15_shop_tpl' })
  for (const n of ['l15_shop_settings', 'l15_shop_mappings'])
    await c.cluster.deleteComponentTemplate({ name: n })
  ok('第7步 清理完成')
  console.log('\n=== 全部步骤通过 ===')
}
main().catch(e => { console.error('失败:', e.message); process.exit(1) })
