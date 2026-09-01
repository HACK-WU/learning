// 清理 l15 残留（上一轮脚本中断留下的）
const { Client } = require('@elastic/elasticsearch')
const c = new Client({ node: 'http://localhost:9201' })
async function main () {
  const idx = await c.cat.indices({ format: 'json' })
  const l15 = idx.filter(i => /^l15-/.test(i.index)).map(i => i.index)
  if (l15.length) { await c.indices.delete({ index: l15 }); console.log('删除索引:', l15.join(', ')) }
  else console.log('无 l15 索引残留')
  try { await c.indices.deleteIndexTemplate({ name: 'l15_shop_tpl' }); console.log('删除索引模板 l15_shop_tpl') }
  catch (e) { console.log('索引模板不存在') }
  for (const n of ['l15_shop_settings', 'l15_shop_mappings']) {
    try { await c.cluster.deleteComponentTemplate({ name: n }); console.log('删除组件模板', n) }
    catch (e) { console.log('组件模板不存在:', n) }
  }
  try { await c.ilm.deleteLifecycle({ name: 'l15_shop_policy' }); console.log('删除 ILM 策略') }
  catch (e) { console.log('ILM 策略不存在') }
  console.log('清理完成')
}
main().catch(e => console.error('失败:', e.message))
