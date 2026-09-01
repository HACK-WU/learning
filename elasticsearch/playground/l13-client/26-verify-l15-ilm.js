// 按修正后的讲义第 5 步端到端验证：模板无 aliases + 建索引时 is_write_index + rollover 真触发
const { Client } = require('@elastic/elasticsearch')
const c = new Client({ node: 'http://localhost:9201' })
const fs = require('fs')
const sleep = ms => new Promise(r => setTimeout(r, ms))
const J = n => JSON.parse(fs.readFileSync('./' + n, 'utf8'))
const ok = s => console.log('  ✅', s)
const bad = s => console.log('  ❌', s)

async function main () {
  await c.cluster.putSettings({ transient: { 'indices.lifecycle.poll_interval': '2s' } })
  await c.cluster.putComponentTemplate({ name: 'l15_shop_settings', body: J('l15-comp-settings.json') })
  await c.cluster.putComponentTemplate({ name: 'l15_shop_mappings', body: J('l15-comp-mappings.json') })
  await c.ilm.putLifecycle({ name: 'l15_shop_policy', body: J('l15-ilm-policy.json') })
  await c.indices.putIndexTemplate({ name: 'l15_shop_tpl', body: J('l15-shop-template2.json') })

  // 讲义写法：显式 is_write_index
  await c.indices.create({ index: 'l15-shop-000003',
    body: { aliases: { 'l15-shop': { is_write_index: true } } } })
  ok('按讲义建索引（显式 is_write_index）')

  const a = await c.ilm.explainLifecycle({ index: 'l15-shop-000003' })
  if (a.indices['l15-shop-000003'].managed) ok('状态A managed=true（此时尚无 phase，符合讲义）')
  else bad('未被 ILM 接管')

  // 写入触发 rollover（策略 max_docs=100，这里写 101 条）
  const body = []
  for (let i = 0; i < 101; i++) body.push({ index: { _index: 'l15-shop' } }, { name: 'd' + i })
  await c.bulk({ refresh: true, operations: body })
  await sleep(7000)

  const b = await c.ilm.explainLifecycle({ index: 'l15-shop-*' })
  for (const [n, i] of Object.entries(b.indices))
    console.log(`     [${n}] phase=${i.phase} action=${i.action} step=${i.step}`)

  const idx = await c.cat.indices({ format: 'json' })
  const got = idx.filter(x => /^l15-shop-/.test(x.index)).map(x => x.index)
  if (got.length >= 2) ok(`rollover 真触发，生成 ${got.join(', ')}`)
  else bad('rollover 未触发，索引仍为 ' + got.join(', '))

  const names = idx.filter(x => /^l15-shop-/.test(x.index)).map(x => x.index)
  if (names.length) await c.indices.delete({ index: names })
  await c.indices.deleteIndexTemplate({ name: 'l15_shop_tpl' })
  await c.ilm.deleteLifecycle({ name: 'l15_shop_policy' })
  for (const n of ['l15_shop_settings', 'l15_shop_mappings'])
    await c.cluster.deleteComponentTemplate({ name: n })
  await c.cluster.putSettings({ transient: { 'indices.lifecycle.poll_interval': null } })
  ok('清理完成，轮询间隔已还原为默认')
}
main().catch(async e => {
  console.error('失败:', e.message)
  await c.cluster.putSettings({ transient: { 'indices.lifecycle.poll_interval': null } }).catch(() => {})
})
