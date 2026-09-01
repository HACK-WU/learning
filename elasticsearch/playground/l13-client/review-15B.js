// 课 15 评审 · B 视角：结构合规 + 零基础学习者体验
// 按 00-评审清单.md 的 10 项每课必查项逐项检查
const fs = require('fs')
const LESSON = 'D:/projects/learning/elasticsearch/stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md'
const md = fs.readFileSync(LESSON, 'utf8')
const issues = []
const P0 = (s) => { issues.push(['P0', s]); console.log('  ❌ P0:', s) }
const P1 = (s) => { issues.push(['P1', s]); console.log('  ⚠️ P1:', s) }
const P2 = (s) => { issues.push(['P2', s]); console.log('  ⚪ P2:', s) }
const ok = (s) => console.log('  ✅', s)
const has = (re) => re.test(md)

console.log('讲义字数 =', md.length, '行数 =', md.split('\n').length)

// ===== 必查 1：结尾两段 =====
console.log('\n[必查 1] 结尾必须含「🚀 下一批接力提示词」+「🧭 课程导航」')
if (has(/## 🚀 下一批接力提示词/)) ok('有「🚀 下一批接力提示词」段')
else P0('缺「🚀 下一批接力提示词」段（PromQL L1、ZooKeeper L1 曾两次遗漏）')
if (has(/## 🧭 课程导航/)) ok('有「🧭 课程导航」段')
else P0('缺「🧭 课程导航」段')
// 导航三要素
if (has(/\*\*上一课\*\*/)) ok('导航含「上一课」')
else P0('导航缺「上一课」')
if (has(/返回目录/)) ok('导航含「返回目录」')
else P0('导航缺「返回目录」')
// 链接有效性
const links = [...md.matchAll(/\]\((\.\.?\/[^)]+)\)/g)].map(m => m[1])
const LESSON_DIR = 'D:/projects/learning/elasticsearch/stages/4-分布式与工程实践/lessons'
let broken = []
for (const l of new Set(links)) {
  const abs = require('path').resolve(LESSON_DIR, l)
  if (!fs.existsSync(abs)) broken.push(l)
}
if (!broken.length) ok(`全部 ${new Set(links).size} 个相对链接均有效`)
else P0(`存在断链：${broken.join(', ')}`)

// ===== 必查 2：五幕结构 =====
console.log('\n[必查 2] 五幕结构完整')
const acts = [
  ['第一幕', /## 第一幕[^\n]*场景引入/],
  ['第二幕', /## 第二幕[^\n]*认知冲突/],
  ['第三幕', /## 第三幕[^\n]*层层揭示/],
  ['第四幕', /## 第四幕[^\n]*实操验证/],
  ['第五幕', /## 第五幕[^\n]*体系收束/],
]
for (const [n, re] of acts) {
  if (has(re)) ok(`${n} 存在`) ; else P0(`缺${n}`)
}

// ===== 必查 3：全程中文 =====
console.log('\n[必查 3] 全程中文（无中英混杂口语）')
const mixed = [
  /\bkicks in\b/, /\bunder the hood\b/, /\bout of the box\b/, /\bby the way\b/,
  /\blet'?s\b/i, /\bactually,?\s/i,
]
let found = mixed.filter(re => re.test(md))
if (!found.length) ok('无中英混杂口语表述')
else P1(`发现英文口语：${found.map(String).join(' | ')}`)
// 术语首次出现是否有中文解释
const terms = [
  ['索引模板', /索引模板（Index Template）/],
  ['组件模板', /组件模板（Component Template）/],
  ['ILM', /ILM（Index Lifecycle Management/],
  ['index_patterns', /`index_patterns`（索引模式）/],
]
for (const [t, re] of terms) {
  if (has(re)) ok(`术语「${t}」首次出现给了中文解释`)
  else P1(`术语「${t}」首次出现缺中文解释`)
}

// ===== 必查 4：零基础友好 =====
console.log('\n[必查 4] 零基础友好（类比 + 类比失效边界）')
const analogies = (md.match(/类比/g) || []).length
if (analogies >= 2) ok(`类比出现 ${analogies} 次`)
else P1('类比偏少')
if (has(/类比的边界|失效边界/)) ok('说明了类比的失效边界')
else P1('未说明类比失效边界（评审清单要求）')
if (has(/术语通俗化|💡 \*\*/)) ok('有术语通俗化提示')
else P2('缺术语通俗化提示')

// ===== 必查 5：命令可运行性 =====
console.log('\n[必查 5] 实操命令可运行（本机约束）')
if (!/\| grep/.test(md)) ok('未使用 | grep（本机无 grep）')
else P0('使用了 | grep，本机无法执行')
if (!/docker/i.test(md)) ok('未依赖 Docker')
else P0('依赖 Docker，本机未安装')
if (!/Invoke-RestMethod/.test(md)) ok('未使用 Invoke-RestMethod')
else P0('使用了 Invoke-RestMethod（实测连不上 ES 9.5.1 HTTPS）')
const bashTick = (md.match(/\\\n/g) || []).length
console.log(`  ℹ️ 反斜杠续行 ${bashTick} 处（Git Bash 写法，本机无 Git Bash）`)
if (bashTick === 0) ok('无 Git Bash 反斜杠续行写法')
else P0(`有 ${bashTick} 处 Git Bash 续行写法，本机无 Git Bash 无法执行`)
const psTick = (md.match(/`\n/g) || []).length
console.log(`  ℹ️ PowerShell 反引号续行 ${psTick} 处`)
if (psTick > 0) ok('使用 PowerShell 反引号续行（本机可用）')
else P1('未使用 PowerShell 反引号续行')
if (/--data-binary @/.test(md)) ok('复杂 JSON 用了 --data-binary @文件（本机唯一可靠写法）')
else P1('未使用 --data-binary @文件 写法')
if (/curl\.exe/.test(md)) ok('统一用 curl.exe')
else P0('未使用 curl.exe')
// 内联双引号转义检查
const inlineEscapes = (md.match(/-d\s+"\\"/g) || []).length
if (inlineEscapes === 0) ok('无 CMD 反斜杠转义内联 JSON')
else P1(`有 ${inlineEscapes} 处 CMD 转义内联 JSON（PowerShell 下会失败）`)

// ===== 必查 6：版本号准确 =====
console.log('\n[必查 6] 版本号准确')
const LOCAL_VER = '9.5.1' // 本机 ES 实测版本（GET / 返回）
const vers = [...new Set((md.match(/9\.\d+\.\d+/g) || []))]
console.log('  出现的版本号：', vers.length ? vers.join(', ') : '无')
const badVer = vers.filter(v => v !== LOCAL_VER)
if (!badVer.length) ok(`全部版本号与本机一致（${LOCAL_VER}）`)
else P1(`出现与本机不符的版本号：${badVer.join(', ')}`)

// ===== 必查 7：跨课引用准确 =====
console.log('\n[必查 7] 跨课引用准确（引用的课确实讲了此内容）')
const refs = [...new Set((md.match(/课 ?\d+/g) || []).map(s => s.replace(/\s/g, '')))]
console.log('  引用的课时：', refs.join(', '))
const CLAIMS = {
  '课5': ['映射'], '课9': ['分片'], '课10': ['分片'], '课11': ['reindex', '快照'],
  '课13': ['RBAC', 'data stream', 'Data Stream', 'data_stream'],
}
for (const [k, kws] of Object.entries(CLAIMS)) {
  if (!refs.includes(k)) continue
  const hit = kws.some(w => new RegExp(w, 'i').test(md))
  if (hit) ok(`${k} 引用上下文含其知识点关键词`)
  else P1(`${k} 引用可能失真`)
}

// ===== 必查 8：Mermaid 兼容性 =====
console.log('\n[必查 8] Mermaid 兼容性（边标签不用反引号，无孤立节点）')
const mermaidBlocks = [...md.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(m => m[1])
console.log(`  Mermaid 图数量 = ${mermaidBlocks.length}`)
let badTick = 0
mermaidBlocks.forEach((b, i) => {
  const t = (b.match(/-->\s*\|`[^`]*`\|/g) || []).length
  if (t) { badTick += t; console.log(`  图 ${i + 1} 有 ${t} 处反引号边标签`) }
})
if (!badTick) ok('无 Mermaid 反引号边标签')
else P0(`${badTick} 处 Mermaid 反引号边标签（Mermaid <10.3 渲染失败）`)
// 孤立节点粗检： flowchart/graph 中被方括号定义但未出现在任何连线里
let orphans = []
mermaidBlocks.forEach((b, i) => {
  if (!/(flowchart|graph)/.test(b)) return
  const defs = [...b.matchAll(/^\s*(\w+)\[/gm)].map(m => m[1])
  const conns = b.split('\n').filter(l => /-->|---|\|/.test(l)).join('\n')
  for (const d of new Set(defs)) {
    if (!new RegExp(`\\b${d}\\b`).test(conns)) orphans.push(`图${i + 1}:${d}`)
  }
})
if (!orphans.length) ok('未发现孤立节点')
else P1(`疑似孤立节点：${orphans.join(', ')}`)
// 配色：不得深色背景
if (!/style\s+\w+\s+fill:#[0-2]/.test(md)) ok('无深色背景填充（fill 非 #0-#2 开头）')
else P1('疑似深色背景填充')

// ===== 必查 9：SVG 浅色主题 =====
console.log('\n[必查 9] SVG 使用情况')
if (md.includes('.svg')) {
  console.log('  引用了 SVG，需人工确认浅色主题')
} else {
  ok('本课未使用独立 SVG（全部 Mermaid 内嵌），不适用')
}

// ===== 必查 10：无孤立节点 =====
console.log('\n[必查 10] 图中无孤立节点（已在必查 8 一并检查）')

// ===== B 视角：学习者体验 L1-L6 =====
console.log('\n===== 学习者视角 L1-L6 =====')
console.log('\n[L1] 场景吸引力')
if (has(/凌晨三点/)) ok('开场有具体故事（凌晨三点事故）')
else P1('开场缺故事性')
if (has(/😖 认知冲突|三个"为什么这么难"|认知冲突/)) ok('有明确的认知冲突段')
else P1('认知冲突不明显')
if (has(/88 块的车厘子|3\.25 元的香蕉/)) ok('场景有具体数字，代入感强')
else P2('场景数字不够具体')

console.log('\n[L2] 由浅入深（认知阶梯）')
const order = ['知识点 1', '知识点 2', '知识点 3', '知识点 4']
const pos = order.map(o => md.indexOf(o))
const ascending = pos.every((p, i) => i === 0 || (p > pos[i - 1] && p > 0))
if (ascending) ok('四个知识点按 1→4 顺序排列')
else P1('知识点顺序错乱')
if (md.indexOf('一句话定义') < md.indexOf('核心原理')) ok('每个知识点先「一句话定义」再「核心原理」')
else P1('缺「一句话定义 → 核心原理」的递进')

console.log('\n[L3] 认知阶梯（感知→概念→机制→实操→定位）')
const ladder = ['一句话定义', '直觉建立', '核心原理', '示例演示', '一句话记住']
const lpos = ladder.map(l => md.indexOf(l))
if (lpos.every(p => p > 0)) ok('五段式要素齐全：' + ladder.join(' / '))
else P1('六要素有缺失：' + ladder.filter((l, i) => lpos[i] < 0).join(', '))

console.log('\n[L4] 故事弧完整性')
if (has(/第一幕[\s\S]*凌晨三点/) && has(/第四幕[\s\S]*第 1 步/) && has(/第五幕[\s\S]*现在你会了什么/)) ok('故事弧完整：开场事故 → 实操救回 → 收束')
else P1('故事弧不完整')
if (has(/场景回顾/)) ok('第四幕回扣了第一幕场景')
else P0('第四幕未回扣第一幕场景（脱节成命令清单）')

console.log('\n[L5] 困惑点预判')
if (has(/常见误区/)) ok(`有常见误区段（${(md.match(/常见误区/g) || []).length} 处）`)
else P1('缺常见误区段')
if (has(/⚠️/)) ok(`有 ⚠️ 风险提示（${(md.match(/⚠️/g) || []).length} 处）`)
else P1('缺风险提示')
if (has(/💡/)) ok(`有 💡 提示（${(md.match(/💡/g) || []).length} 处）`)
else P2('提示偏少')

console.log('\n[L6] 全局定位')
if (has(/本课在全局中的位置/)) ok('有「本课在全局中的位置」段')
else P0('缺全局定位段')
if (has(/与其他课的连接/)) ok('有跨课连接表')
else P1('缺跨课连接')
if (has(/命令速查卡/)) ok('有命令速查卡')
else P1('缺命令速查卡')
if (has(/📚 官方文档/)) ok('有官方文档链接')
else P1('缺官方文档链接')
// 文档链接是否为真实官方域名
const urls = [...new Set([...md.matchAll(/\]\((https?:\/\/[^)]+)\)/g)].map(m => m[1]))]
const nonElastic = urls.filter(u => !/elastic\.co/.test(u))
if (!nonElastic.length) ok(`全部 ${urls.length} 个外链均为 elastic.co 官方域名`)
else P1(`存在非官方外链：${nonElastic.join(', ')}`)

// ===== 额外：本课特有检查 =====
console.log('\n===== 本课特有检查 =====')
if (has(/实测/)) ok(`标注了实测（${(md.match(/实测/g) || []).length} 处）`)
else P0('未标注实测来源')
if (/课 15|本课/.test(md)) ok('有本课标识')
else P2('缺本课标识')
// 命令数
const cmds = (md.match(/curl\.exe/g) || []).length
if (cmds >= 15) ok(`可执行命令 ${cmds} 条，实操充分`)
else P1(`命令仅 ${cmds} 条，实操不足`)
// 时效性标注
if (has(/核查于/) || has(/置信度/)) ok('有事实核查或置信度标注')
else P2('无时效性标注（本课内容不涉及时效敏感项，可豁免）')

console.log('\n================ B 视角结论 ================')
const c0 = issues.filter(i => i[0] === 'P0').length
const c1 = issues.filter(i => i[0] === 'P1').length
const c2 = issues.filter(i => i[0] === 'P2').length
console.log(`P0=${c0}  P1=${c1}  P2=${c2}`)
for (const [lv, s] of issues) console.log(` ${lv}: ${s}`)
