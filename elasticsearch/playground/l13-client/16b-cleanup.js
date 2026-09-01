// 课 15 环境清理：清掉 l15 前缀的所有残留（索引、别名、模板、策略、transient 设置）
const { Client } = require('@elastic/elasticsearch')
const client = new Client({ node: 'http://localhost:9201' })
const log = (...a) => console.log(...a)

async function main() {
  // 1. 先删别名（避免删索引时受 is_write_index 干扰）
  try {
    const al = await client.indices.getAlias({ name: '*' })
    const targets = []
    for (const [idx, info] of Object.entries(al)) {
      for (const name of Object.keys(info.aliases || {})) {
        if (name.startsWith('l15')) targets.push({ index: idx, alias: name })
      }
    }
    log('待删 l15 别名数量 =', targets.length)
    for (const t of targets) {
      try { await client.indices.updateAliases({ actions: [{ remove: t }] }); log('  已删别名', t.alias, '←', t.index) }
      catch (e) { log('  删别名失败', t.alias, e.meta?.body?.error?.reason || e.message) }
    }
  } catch (e) { log('查别名失败：', e.message) }

  // 2. 删索引（含 .ds- 后备索引）
  for (const p of ['l15*', '.ds-l15*', 'l15-lifecycle*']) {
    try { await client.indices.delete({ index: p }); log('已删索引匹配', p) }
    catch (e) { log('删索引', p, '→', e.meta?.body?.error?.type || e.message) }
  }

  // 3. 删模板与组件模板
  for (const n of ['l15_tpl_base', 'l15_tpl_override', 'l15_lc_template']) {
    try { await client.indices.deleteIndexTemplate({ name: n }); log('已删索引模板', n) } catch (e) {}
  }
  for (const n of ['l15_ct_settings', 'l15_ct_mappings']) {
    try { await client.cluster.deleteComponentTemplate({ name: n }); log('已删组件模板', n) } catch (e) {}
  }

  // 4. 删 ILM 策略
  try { await client.ilm.deleteLifecycle({ name: 'l15_fast_policy' }); log('已删 ILM 策略 l15_fast_policy') } catch (e) {}

  // 5. 还原 transient 设置
  await client.cluster.putSettings({ transient: { 'indices.lifecycle.poll_interval': null } })
  const st = await client.cluster.getSettings({ include_defaults: true })
  log('poll_interval transient =', JSON.stringify(st.transient?.indices?.lifecycle || {}),
      '；默认值 =', st.defaults?.indices?.lifecycle?.poll_interval)

  // 6. 复查
  const cat = await client.cat.indices({ h: ['index'] })
  const left = cat.map(x => x.index).filter(i => i && i.includes('l15'))
  log('剩余 l15 相关索引 =', left.length ? left.join(', ') : '无')
}
main().catch(e => console.error('FAILED:', e.meta?.body?.error?.reason || e.message))
