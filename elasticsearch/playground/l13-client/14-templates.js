// 课 15《索引管理与生命周期策略》实测 · 第 1 组：组件模板 + 索引模板组合与优先级
// 目标：证明组件模板可复用、索引模板按 priority 合并、模板只影响新建索引
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')

// 保险：删掉上轮残留
async function cleanup() {
  const pats = ['l15-comp-*', 'l15-tpl-a-*', 'l15-tpl-b-*', 'l15-existing']
  for (const p of pats) {
    try { await client.indices.delete({ index: p }) } catch (e) {}
  }
  for (const n of ['l15_ct_settings', 'l15_ct_mappings', 'l15_tpl_base', 'l15_tpl_override']) {
    try { await client.cluster.deleteComponentTemplate({ name: n }) } catch (e) {}
    try { await client.indices.deleteIndexTemplate({ name: n }) } catch (e) {}
  }
}

async function main() {
  await cleanup()

  sep('1. 建两个组件模板（一个管 settings，一个管 mappings）')
  await client.cluster.putComponentTemplate({
    name: 'l15_ct_settings',
    template: {
      settings: {
        number_of_shards: 2,
        number_of_replicas: 0,
        'index.refresh_interval': '5s',
      },
    },
  })
  await client.cluster.putComponentTemplate({
    name: 'l15_ct_mappings',
    template: {
      mappings: {
        properties: {
          '@timestamp': { type: 'date' },
          message: { type: 'text' },
          level: { type: 'keyword' },
        },
      },
    },
  })
  log('两个组件模板已建：l15_ct_settings / l15_ct_mappings')

  sep('2. 建索引模板，composed_of 引用两个组件模板')
  await client.indices.putIndexTemplate({
    name: 'l15_tpl_base',
    index_patterns: ['l15-tpl-*'],
    priority: 100,
    composed_of: ['l15_ct_settings', 'l15_ct_mappings'],
  })
  log('索引模板 l15_tpl_base 已建（priority=100）')

  sep('3. 直接建索引，看它是否继承了组件模板的配置')
  await client.indices.create({ index: 'l15-tpl-a-0001' })
  const a = await client.indices.get({ index: 'l15-tpl-a-0001' })
  const aBody = a['l15-tpl-a-0001']
  log('number_of_shards      =', aBody.settings.index.number_of_shards)
  log('number_of_replicas    =', aBody.settings.index.number_of_replicas)
  log('refresh_interval      =', aBody.settings.index.refresh_interval)
  log('mappings 字段         =', Object.keys(aBody.mappings.properties || {}).join(', '))
  log('level 类型            =', aBody.mappings.properties?.level?.type)

  sep('4. 建高优先级模板，只覆盖 refresh_interval，看合并结果')
  await client.indices.putIndexTemplate({
    name: 'l15_tpl_override',
    index_patterns: ['l15-tpl-b-*'],
    priority: 200,
    composed_of: ['l15_ct_settings', 'l15_ct_mappings'],
    template: {
      settings: { 'index.refresh_interval': '30s' },
    },
  })
  await client.indices.create({ index: 'l15-tpl-b-0001' })
  const b = await client.indices.get({ index: 'l15-tpl-b-0001' })
  const bBody = b['l15-tpl-b-0001']
  log('refresh_interval      =', bBody.settings.index.refresh_interval, '  ← 被 priority=200 覆盖')
  log('number_of_shards      =', bBody.settings.index.number_of_shards, '  ← 组件模板的值保留')
  log('mappings 字段         =', Object.keys(bBody.mappings.properties || {}).join(', '))

  sep('5. 组件模板更新后，已有索引会跟着变吗？')
  await client.cluster.putComponentTemplate({
    name: 'l15_ct_settings',
    template: {
      settings: {
        number_of_shards: 2,
        number_of_replicas: 0,
        'index.refresh_interval': '77s',
      },
    },
  })
  const a2 = await client.indices.get({ index: 'l15-tpl-a-0001' })
  log('l15-tpl-a-0001 refresh_interval 现在 =', a2['l15-tpl-a-0001'].settings.index.refresh_interval)
  await client.indices.create({ index: 'l15-tpl-a-0002' })
  const a3 = await client.indices.get({ index: 'l15-tpl-a-0002' })
  log('l15-tpl-a-0002 refresh_interval 新建 =', a3['l15-tpl-a-0002'].settings.index.refresh_interval)

  sep('6. 模拟一次真实匹配：GET _index_template/_simulate_index/l15-tpl-x-0001')
  const sim = await client.indices.simulateIndexTemplate({ name: 'l15-tpl-x-0001' })
  log('生效模板顺序 =', (sim.template?.overlapping || []).map(o => `${o.name}(${o.index_patterns})`).join(' → '))
  log('合并后 settings.number_of_shards =', sim.template?.template?.settings?.index?.number_of_shards)
  log('合并后 refresh_interval         =', sim.template?.template?.settings?.index?.refresh_interval)

  sep('7. 模板只对新建索引生效（已存在的索引不被追溯）')
  await client.indices.create({ index: 'l15-existing' }) // 不匹配任何 l15 模板
  const e1 = await client.indices.get({ index: 'l15-existing' })
  log('l15-existing 主分片 =', e1['l15-existing'].settings.index.number_of_shards, '（默认值，未被模板影响）')

  sep('实测结论')
  log('组件模板 = 可复用的配置积木；索引模板 composed_of 组装；priority 大的覆盖小的')
  log('组件模板改了，已有索引不变，只影响之后新建的索引')
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
