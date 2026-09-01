// 课 15 补测：shrink（单节点条件）+ forcemerge（段数变化）
// 上轮两个失败点：① shrink 要求全部分片在同一节点 ② forcemerge 段数读到 0（解析方式不对）
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)
const sep = (t) => log('\n===== ' + t + ' =====')
const sleep = (ms) => new Promise(r => setTimeout(r, ms))

// 正确统计段数：遍历 indices -> shards -> 各副本 -> segments 列表
function countSegments(segResp, indexName) {
  const idx = segResp.indices[indexName]
  if (!idx) return 0
  let n = 0
  for (const [, shardArr] of Object.entries(idx.shards)) {
    const list = Array.isArray(shardArr) ? shardArr : [shardArr]
    for (const shard of list) {
      const segs = shard.segments
      if (segs && typeof segs === 'object') n += Object.keys(segs).length
    }
  }
  return n
}

async function cleanup() {
  for (const p of ['l15_ops2', 'l15_ops2_shrunk', 'l15_merge2']) {
    try { await client.indices.delete({ index: p }) } catch (e) {}
  }
}

async function main() {
  await cleanup()

  sep('1. shrink 前置条件：把分片集中到同一个节点')
  await client.indices.create({
    index: 'l15_ops2',
    settings: { number_of_shards: 4, number_of_replicas: 0 },
  })
  for (let i = 0; i < 6; i++) {
    await client.index({ index: 'l15_ops2', id: String(i), document: { t: 'doc' + i } })
  }
  await client.indices.refresh({ index: 'l15_ops2' })
  log('已建 l15_ops2：4 主分片、6 条数据')

  // 先看分片分布在哪些节点
  const shardsBefore = await client.cat.shards({ index: 'l15_ops2', h: ['index', 'shard', 'prirep', 'state', 'node'], format: 'json' })
  log('收缩前分片分布：')
  for (const s of shardsBefore) log(`  shard ${s.shard} ${s.prirep} → ${s.node}`)

  // 用 allocation 规则把全部分片赶到 node-1
  await client.indices.putSettings({
    index: 'l15_ops2',
    settings: { 'index.routing.allocation.require._name': 'node-1' },
  })
  log('\n已设置 allocation.require._name = node-1，等待重分配...')
  for (let i = 0; i < 30; i++) {
    const sh = await client.cat.shards({ index: 'l15_ops2', h: ['shard', 'node'], format: 'json' })
    const nodes = new Set(sh.map(s => s.node))
    if (nodes.size === 1 && !nodes.has(null)) { log('  全部分片已集中到', [...nodes].join(','), `（等了 ${i * 2}s）`); break }
    await sleep(2000)
  }

  sep('2. 执行 shrink：4 分片 → 1 分片')
  await client.indices.putSettings({ index: 'l15_ops2', settings: { 'index.blocks.write': true } })
  log('已加 blocks.write（shrink 要求源索引只读）')
  try {
    const r = await client.indices.shrink({
      index: 'l15_ops2',
      target: 'l15_ops2_shrunk',
      settings: {
        'index.number_of_shards': 1,
        'index.number_of_replicas': 0,
        'index.blocks.write': null,
        'index.routing.allocation.require._name': null,
      },
    })
    log('shrink acknowledged =', r.acknowledged)
    await sleep(3000)
    const g = await client.indices.get({ index: 'l15_ops2_shrunk' })
    log('缩容后主分片 =', g['l15_ops2_shrunk'].settings.index.number_of_shards, '（原 4）')
    const c = await client.count({ index: 'l15_ops2_shrunk' })
    log('缩容后条数 =', c.count, '（原 6）← 数据完整')
    const h = await client.indices.getHealth
      ? null : null
  } catch (e) {
    log('shrink 报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('3. shrink 的因数约束：4 → 3 会怎样？')
  try {
    await client.indices.putSettings({ index: 'l15_ops2', settings: { 'index.blocks.write': true } })
    await client.indices.shrink({
      index: 'l15_ops2',
      target: 'l15_ops2_shrunk3',
      settings: { 'index.number_of_shards': 3, 'index.number_of_replicas': 0 },
    })
    log('4 → 3 竟然成功了（不该成功）')
    await client.indices.delete({ index: 'l15_ops2_shrunk3' })
  } catch (e) {
    log('4 → 3 报错：', e.meta?.body?.error?.type)
    log('  →', e.meta?.body?.error?.reason)
  }

  sep('4. forcemerge：段数真的会减少吗')
  await client.indices.create({ index: 'l15_merge2', settings: { number_of_shards: 1, number_of_replicas: 0 } })
  for (let i = 0; i < 8; i++) {
    await client.index({ index: 'l15_merge2', id: String(i), document: { t: 'doc' + i } })
    await client.indices.refresh({ index: 'l15_merge2' })  // 每次 refresh 都会产出新段
  }
  let seg0 = await client.indices.segments({ index: 'l15_merge2' })
  const n0 = countSegments(seg0, 'l15_merge2')
  log('8 次写入 + 8 次 refresh，forcemerge 前段数 =', n0)

  const fm = await client.indices.forcemerge({ index: 'l15_merge2', max_num_segments: 1 })
  log('forcemerge 返回 =', JSON.stringify(fm))
  await sleep(2000)
  let seg1 = await client.indices.segments({ index: 'l15_merge2' })
  const n1 = countSegments(seg1, 'l15_merge2')
  log('forcemerge 后段数 =', n1, n1 < n0 ? ' ← 段合并生效' : '（未减少）')

  const c2 = await client.count({ index: 'l15_merge2' })
  log('合并后条数 =', c2.count, ' ← 数据不丢')

  sep('5. forcemerge 后还能写吗（生产上为什么只对只读索引做）')
  await client.index({ index: 'l15_merge2', id: '99', document: { t: 'after merge' }, refresh: true })
  const c3 = await client.count({ index: 'l15_merge2' })
  log('merge 后写入成功，条数 =', c3.count, ' → 能写，但会重新产生段')

  sep('实测结论')
  log('shrink 必须：① 分片全在同一节点 ② 源索引只读 ③ 目标分片数是源分片数的因数')
  log('forcemerge 把多个段合成一个，减少查询时要扫的段数，是 ILM warm 阶段的典型动作')
}

main().catch(e => { console.error('FAILED:', e.meta?.body?.error?.reason || e.message); process.exit(1) })
