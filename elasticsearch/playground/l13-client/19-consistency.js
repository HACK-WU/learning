// 收官一致性核查：课 15 + Phase 5 三份产物 + 五份活文档
// 查：文件存在 / 内部链接可达 / 规模数字一致 / 无孤立引用 / Mermaid 合规
const fs = require('fs')
const path = require('path')
const ROOT = 'D:/projects/learning/elasticsearch/'
const issues = []
const P0 = s => { issues.push(['P0', s]); console.log('  ❌ P0:', s) }
const P1 = s => { issues.push(['P1', s]); console.log('  ⚠️ P1:', s) }
const ok = s => console.log('  ✅', s)
const rd = p => fs.readFileSync(ROOT + p, 'utf8')

console.log('============ 1. 产物文件存在性 ============')
const FILES = [
  'stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md',
  '08-实战经验.md', '09-排障速查手册.md', '10-场景解法库.md',
]
for (const f of FILES) {
  const p = ROOT + f
  if (!fs.existsSync(p)) { P0('缺文件: ' + f); continue }
  const st = fs.statSync(p)
  ok(`${f} — ${(st.size / 1024).toFixed(1)} KB`)
}

console.log('\n============ 2. 活文档内部链接可达 ============')
const LIVING = ['00-学习档案.md', '01-学习路径总览.md', '02-课程目录.md', '00-评审清单.md']
for (const name of LIVING) {
  const md = rd(name)
  const links = [...new Set([...md.matchAll(/\]\(([^)#]+?)(?:#[^)]*)?\)/g)].map(m => m[1]))]
    .filter(l => !/^https?:/.test(l))
  const broken = []
  for (const l of links) {
    const abs = path.resolve(ROOT, l)
    if (!fs.existsSync(abs)) broken.push(l)
  }
  if (!broken.length) ok(`${name}: ${links.length} 个内部链接全部可达`)
  else P0(`${name} 断链 ${broken.length} 个: ${broken.join(', ')}`)
}

console.log('\n============ 3. 三份产物互链闭环 ============')
const ref = { '08-实战经验.md': ['09-排障速查手册.md', '10-场景解法库.md'],
              '09-排障速查手册.md': ['08-实战经验.md', '10-场景解法库.md'],
              '10-场景解法库.md': ['08-实战经验.md', '09-排障速查手册.md'] }
for (const [f, want] of Object.entries(ref)) {
  const md = rd(f)
  const miss = want.filter(w => !md.includes(w))
  if (!miss.length) ok(`${f} 互链完整`)
  else P1(`${f} 缺互链: ${miss.join(', ')}`)
}

console.log('\n============ 4. 规模数字一致性（15 课 / 46 知识点）============')
const scale = { '02-课程目录.md': /15 课 \/ 46 知识点/, '01-学习路径总览.md': /15 课 \/ 46 知识点/, '00-学习档案.md': /15 课 \/ 46 知识点/ }
for (const [f, re] of Object.entries(scale)) {
  const md = rd(f)
  if (re.test(md)) ok(`${f} 规模已更新为 15 课 / 46 知识点`)
  else P0(`${f} 规模数字未同步`)
  // 「大纲调整记录」里的旧数字是历史事实（记录"由 14 课扩到 15 课"），必须保留；
  // 只在没有"增补/调整记录"语境的普通行里出现旧数字才算过时表述
  const lines = md.split('\n').filter(l => !/增补课|初始大纲落盘|→|扩到/.test(l))
  const stale = lines.filter(l => /14 课 ?\/ ?42 知识点/.test(l))
  if (!stale.length) ok(`${f} 无过时的 14 课/42 知识点表述`)
  else P1(`${f} ${stale.length} 处旧数字未同步（已排除历史记录行）: ${stale.map(s => s.trim().slice(0, 60)).join(' | ')}`)
}

console.log('\n============ 5. 课 15 在各处均已登记 ============')
const L15 = 'lesson-15-索引管理与生命周期策略.md'
// 活文档用中文简称（"课15《索引管理与生命周期策略》"），不是讲义文件名；
// 精确匹配文件名会产生假 P0，故按"课15 存在 + 标题关键词存在"判定
for (const f of ['02-课程目录.md', '01-学习路径总览.md', '00-学习档案.md',
                 '00-评审清单.md', 'stages/4-分布式与工程实践/overview.md']) {
  const md = rd(f)
  if (/课15|课 15/.test(md) && /索引管理与生命周期/.test(md)) ok(`${f} 已登记课 15`)
  else if (md.includes(L15)) ok(`${f} 已登记课 15（讲义文件名）`)
  else P0(`${f} 未登记课 15`)
}

console.log('\n============ 6. 三份手册在各处均已登记 ============')
// 同样按中文简称判定：实战经验 / 排障速查手册 / 场景解法库
for (const f of ['02-课程目录.md', '01-学习路径总览.md', '00-评审清单.md']) {
  const md = rd(f)
  const has = ['实战经验', '排障速查', '场景解法库'].filter(k => md.includes(k))
  if (has.length === 3) ok(`${f} 已登记三份手册`)
  else P1(`${f} 只登记了 ${has.length}/3 份手册（缺 ${['实战经验','排障速查','场景解法库'].filter(k=>has.includes(k)?false:true).join('、')}）`)
}

console.log('\n============ 7. Mermaid 合规（全量产物）============')
const ALL = [...FILES, ...LIVING, 'stages/4-分布式与工程实践/overview.md']
let total = 0, bad = 0
for (const f of ALL) {
  const md = rd(f)
  const mm = [...md.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(m => m[1])
  total += mm.length
  mm.forEach(b => { bad += (b.match(/-->\s*\|`[^`]*`\|/g) || []).length })
}
if (!bad) ok(`${ALL.length} 份文档共 ${total} 个 Mermaid 图，无反引号边标签`)
else P0(`${bad} 处 Mermaid 反引号边标签`)

console.log('\n============ 8. 课 15 讲义收尾两段 ============')
const l15 = rd(FILES[0])
if (/🚀 下一批接力提示词/.test(l15)) ok('含「🚀 下一批接力提示词」')
else P0('缺「🚀 下一批接力提示词」')
if (/🧭 课程导航/.test(l15)) ok('含「🧭 课程导航」')
else P0('缺「🧭 课程导航」')

console.log('\n================ 总结论 ================')
const c = lv => issues.filter(i => i[0] === lv).length
console.log(`P0=${c('P0')}  P1=${c('P1')}`)
for (const [lv, s] of issues) console.log(` ${lv}: ${s}`)
