// 课 15《索引管理与生命周期策略》实测 · 第 3 组：ILM 五阶段 + 索引运维操作
// 目标：让 ILM 真的动起来（用秒级 min_age 观察阶段流转），并实测 open/close/shrink/forcemerge
const { Client } = require('@elastic/elasticsearch')

const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')
const sleep = (ms) => new Promise(r => setTimeout(r, ms))

async function cleanup() {
  for (const p of ['l15_ops', 'l15_ops_shrunk', 'l15_merge',
    'l15-lifecycle-000001', 'l15-lifecycle-000002', 'l15-lifecycle-000003']) {
    try { await client.indices.delete({ index: p }) } catch (e) {}
  }
  // 别名要先摘掉，否则删索引会连带失败
  try {
    const al = await client.indices.getAlias({ name: 'l15-lifecycle' })
    await client.indices.updateAliases({
      actions: Object.keys(al).map(i => ({ remove: { index: i, alias: 'l15-lifecycle' } })),
    })
  } catch (e) {}
  for (const n of ['l15_lc_template']) {
    try { await client.indices.deleteIndexTemplate({ name: n }) } catch (e) {}
  }
  try { await client.ilm.deleteLifecycle({ name: 'l15_fast_policy' }) } catch (e) {}
}

async function waitPhase(indexName, target, maxSec = 180) {
  const t0 = Date.now()
  let last = null
  while ((Date.now() - t0) / 1000 < maxSec) {
    try {
      const r = await client.ilm.explainLifecycle({ index: indexName })
      const info = r.indices[indexName]
      if (info) {
        last = { phase: info.phase, action: info.action, step: info.step, age: info.age }
        if (info.phase === target) return last
      }
    } catch (e) {}
    await sleep(5000)
  }
  return last
}

async function main() {
  await cleanup()

  sep('0. 确认 ILM 轮询间隔（决定实验要等多久）')
  const st0 = await client.cluster.getSettings({ include_defaults: true })
  log('默认 indices.lifecycle.poll_interval =', st0.defaults?.indices?.lifecycle?.poll_interval)
  // 默认 10 分钟，实验等不起。临时改成 5 秒（集群级 transient，第 9 步会还原）
  await client.cluster.putSettings({
    transient: { 'indices.lifecycle.poll_interval': '5s' },
  })
  const st1 = await client.cluster.getSettings({})
  log('临时改为 =', st1.transient?.indices?.lifecycle?.poll_interval, '（实验结束后还原）')

  sep('1. 建一个"秒级"ILM 策略：10s 进 warm，60s 进 cold，120s 删除')
  await client.ilm.putLifecycle({
    name: 'l15_fast_policy',
    policy: {
      phases: {
        hot: { min_age: '0ms', actions: { set_priority: { priority: 100 } } },
        warm: { min_age: '10s', actions: { set_priority: { priority: 50 }, forcemerge: { max_num_segments: 1 } } },
        cold: { min_age: '60s', actions: { set_priority: { priority: 0 } } },
        delete: { min_age: '120s', actions: { delete: {} } },
      },
    },
  })
  log('策略 l15_fast_policy 已建')

  sep('2. 建模板绑定策略，并让 ILM 立即接管')
  await client.indices.putIndexTemplate({
    name: 'l15_lc_template',
    index_patterns: ['l15-lifecycle-*'],
    priority: 300,
    template: {
      settings: {
        number_of_shards: 1,
        number_of_replicas: 0,
        'index.lifecycle.name': 'l15_fast_policy',
      },
    },
  })
  // 用"别名 + is_write_index"的经典滚动模式（区别于课 13 的 data stream 模式）
  await client.indices.create({ index: 'l15-lifecycle-000001' })
  await client.indices.updateAliases({
    actions: [{ add: { index: 'l15-lifecycle-000001', alias: 'l15-lifecycle', is_write_index: true } }],
  })
  await client.index({ index: 'l15-lifecycle', document: { msg: 'warmup', '@timestamp': new Date().toISOString() }, refresh: true })
  const ro = await client.indices.rollover({ alias: 'l15-lifecycle' })
  log('rollover 结果：old =', ro.old_index, '→ new =', ro.new_index, ' rolled_over =', ro.rolled_over)
  log('说明：rollover 只能作用于别名或 data stream，不能直接作用于具体索引（实测报错已验证）')

  const t0 = Date.now()
  sep('3. 观察阶段流转（每 5 秒采样一次，最多 240 秒）')
  let seen = []
  while ((Date.now() - t0) / 1000 < 240) {
    let r
    try { r = await client.ilm.explainLifecycle({ index: 'l15-lifecycle-000001' }) } catch (e) { break }
    const entries = Object.entries(r.indices || {})
    if (!entries.length) { log(`[${Math.round((Date.now()-t0)/1000)}s] 索引已被删除（delete 阶段生效）`); break }
    for (const [name, info] of entries) {
      const key = `${name}|${info.phase}|${info.action}|${info.step}`
      if (!seen.includes(key)) {
        seen.push(key)
        log(`[${Math.round((Date.now()-t0)/1000)}s] ${info.phase} / ${info.action} / ${info.step}  (age=${info.age})`)
      }
    }
    await sleep(5000)
  }

  sep('4. ILM 执行历史（看它到底做了什么）')
  try {
    const hist = await client.search({
      index: 'ilm-history-*',
      size: 20,
      sort: [{ '@timestamp': { order: 'desc' } }],
      query: { bool: { filter: [{ term: { 'policy_name': 'l15_fast_policy' } }] } },
    })
    log('命中历史条数 =', hist.hits.total.value)
    for (const h of hist.hits.hits.slice(0, 12)) {
      const s = h._source
      log(`  ${s['@timestamp']} | ${s.phase} | ${s.action} | ${s.step} | success=${s.success}`)
    }
  } catch (e) {
    log('查 ILM 历史失败：', e.meta?.body?.error?.reason || e.message)
  }

  sep('5. 索引运维 · close / open')
  await client.indices.create({ index: 'l15_ops', settings: { number_of_shards: 2, number_of_replicas: 0 } })
  await client.index({ index: 'l15_ops', id: '1', document: { t: 'hello' }, refresh: true })
  try {
    const s1 = await client.search({ index: 'l15_ops', query: { match_all: {} } })
    log('open 状态搜索命中 =', s1.hits.total.value)
  } catch (e) { log('open 状态搜索失败：', e.message) }
  await client.indices.close({ index: 'l15_ops' })
  try {
    await client.search({ index: 'l15_ops', query: { match_all: {} } })
    log('close 后搜索成功（不该成功）')
  } catch (e) {
    log('close 后搜索报错：', e.meta?.body?.error?.type)
    log('  →', String(e.meta?.body?.error?.reason).slice(0, 160))
  }
  try {
    await client.index({ index: 'l15_ops', id: '2', document: { t: 'x' } })
    log('close 后写入成功（不该成功）')
  } catch (e) {
    log('close 后写入报错：', e.meta?.body?.error?.type)
  }
  const catBefore = await client.cat.indices({ index: 'l15_ops', h: ['index', 'status'] })
  log('close 后 _cat 状态 =', JSON.stringify(catBefore))
  await client.indices.open({ index: 'l15_ops' })
  const s2 = await client.search({ index: 'l15_ops', query: { match_all: {} } })
  log('重新 open 后搜索命中 =', s2.hits.total.value, ' ← 数据还在')

  sep('6. 索引运维 · shrink（缩分片，必须是 2 的因数倍关系）')
  try {
    await client.indices.putSettings({ index: 'l15_ops', settings: { 'index.blocks.write': true } })
    const r = await client.indices.shrink({
      index: 'l15_ops',
      target: 'l15_ops_shrunk',
      settings: { 'index.number_of_shards': 1, 'index.number_of_replicas': 0, 'index.blocks.write': null },
    })
    log('shrink 返回 acknowledged =', r.acknowledged)
    const g = await client.indices.get({ index: 'l15_ops_shrunk' })
    log('缩容后主分片 =', g['l15_ops_shrunk'].settings.index.number_of_shards, '（原为 2）')
    const c = await client.count({ index: 'l15_ops_shrunk' })
    log('缩容后条数 =', c.count, ' ← 数据完整')
  } catch (e) {
    log('shrink 报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('7. 索引运维 · forcemerge（合并段）')
  await client.indices.create({ index: 'l15_merge', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  for (let i = 0; i < 5; i++) {
    await client.index({ index: 'l15_merge', id: String(i), document: { t: 'doc' + i } })
    await client.indices.refresh({ index: 'l15_merge' })
  }
  const segBefore = await client.indices.segments({ index: 'l15_merge' })
  let nBefore = 0
  for (const [, sh] of Object.entries(segBefore.indices['l15_merge'].shards)) {
    nBefore += sh.segments ? Object.keys(sh.segments).length : 0
  }
  log('forcemerge 前段数 =', nBefore)
  await client.indices.forcemerge({ index: 'l15_merge', max_num_segments: 1 })
  const segAfter = await client.indices.segments({ index: 'l15_merge' })
  let nAfter = 0
  for (const [, sh] of Object.entries(segAfter.indices['l15_merge'].shards)) {
    nAfter += sh.segments ? Object.keys(sh.segments).length : 0
  }
  log('forcemerge 后段数 =', nAfter)
  await client.indices.delete({ index: 'l15_merge' })

  sep('8. 为什么生产上索引要"只读"（ILM 滚动的前提）')
  try {
    await client.index({ index: 'l15_ops_shrunk', id: '3', document: { t: 'y' } })
    log('写入成功 → 说明 blocks.write 已被解除')
  } catch (e) {
    log('写入报错：', e.meta?.body?.error?.type, '→', e.meta?.body?.error?.reason)
  }

  sep('9. 还原集群设置（把 poll_interval 改回默认）')
  await client.cluster.putSettings({ transient: { 'indices.lifecycle.poll_interval': null } })
  const st2 = await client.cluster.getSettings({ include_defaults: true })
  log('还原后 transient =', JSON.stringify(st2.transient?.indices?.lifecycle || {}), '；默认 =', st2.defaults?.indices?.lifecycle?.poll_interval)

  sep('实测结论')
  log('ILM 按 min_age 推进阶段，poll_interval 决定检查频率；delete 阶段真的会把索引删掉')
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
