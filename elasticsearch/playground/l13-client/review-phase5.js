// Phase 5 三份产物评审 · 合并视角（A 事实核查 + B 学习者视角 + 专项维度）
// 专项维度 B1-B8（收尾产物）+ C1-C7（场景解法库）
const fs = require('fs')
const ROOT = 'D:/projects/learning/elasticsearch/'
const FILES = {
  '08-实战经验.md': ROOT + '08-实战经验.md',
  '09-排障速查手册.md': ROOT + '09-排障速查手册.md',
  '10-场景解法库.md': ROOT + '10-场景解法库.md',
}
const LESSON_DIR = ROOT + 'stages/4-分布式与工程实践/lessons'
const issues = []
const P0 = (s) => { issues.push(['P0', s]); console.log('  ❌ P0:', s) }
const P1 = (s) => { issues.push(['P1', s]); console.log('  ⚠️ P1:', s) }
const P2 = (s) => { issues.push(['P2', s]); console.log('  ⚪ P2:', s) }
const ok = (s) => console.log('  ✅', s)
const path = require('path')

for (const [name, p] of Object.entries(FILES)) {
  console.log('\n############ ' + name + ' ############')
  const md = fs.readFileSync(p, 'utf8')
  console.log('字数 =', md.length, '行数 =', md.split('\n').length)

  // ===== 通用：命令可运行性 =====
  // 说明：本块只检查"给学员执行的命令"，不检查"提醒学员不要用 X"的正文。
  // 因此先剔除引用块（> 开头的提醒行）与行内代码（`...`），只保留代码块里的可执行命令。
  // 语言标签必须通用：漏掉 mermaid/yml 等会使围栏配对错位，导致后续命令检查失真
  const CODE = [...md.matchAll(/```[a-z]*\n([\s\S]*?)```/g)]
    .map(m => m[1]).join('\n')
  const IS_DESIGN = /设计态/.test(md)          // 10 场景解法库：设计态，不给可执行命令
  console.log('\n[命令可运行性]')
  if (!/grep/.test(CODE)) ok('可执行命令中无 grep') ; else P0('可执行命令里用了 grep（本机无 grep）')
  if (!/docker/i.test(CODE)) ok('不依赖 Docker') ; else P0('依赖 Docker')
  if (!/Invoke-RestMethod/.test(CODE)) ok('未用 Invoke-RestMethod') ; else P0('用了 Invoke-RestMethod')
  if (IS_DESIGN) ok('设计态产物，豁免 curl 要求（已声明不给可执行命令）')
  else if (md.includes('curl.exe')) ok('统一 curl.exe') ; else P1('未使用 curl.exe')
  const bashTick = (CODE.match(/\\\n/g) || []).length
  if (bashTick === 0) ok('无 Git Bash 反斜杠续行') ; else P1(`${bashTick} 处 Git Bash 续行（本机无 Git Bash）`)
  if (/--data-binary\s+["']?@/.test(CODE) || !/curl\.exe/.test(CODE)) ok('JSON 用文件写法') ; else P2('内联 JSON 需确认')

  // ===== 通用：中文与外链 =====
  console.log('\n[语言与链接]')
  const mixed = [/\bkicks in\b/, /\bunder the hood\b/, /\bout of the box\b/, /\bby the way\b/]
  const fm = mixed.filter(re => re.test(md))
  if (!fm.length) ok('无中英混杂口语') ; else P1('有英文口语：' + fm.map(String).join(' | '))
  const urls = [...new Set([...md.matchAll(/\]\((https?:\/\/[^)]+)\)/g)].map(m => m[1]))]
  const nonOff = urls.filter(u => !/elastic\.co/.test(u))
  if (!nonOff.length) ok(`全部 ${urls.length} 个外链均为 elastic.co`) ; else P1('非官方外链：' + nonOff.join(', '))

  // ===== 通用：跨文件链接有效性 =====
  const rel = [...new Set([...md.matchAll(/\]\((\.\.?\/[^)#]+|\d\d-[^)]+)\)/g)].map(m => m[1]))]
  const brokenRel = rel.filter(l => !fs.existsSync(path.resolve(ROOT, l)))
  if (!brokenRel.length) ok(`${rel.length} 个内部链接均有效`) ; else P0('断链：' + brokenRel.join(', '))

  // ===== 通用：Mermaid 合规 =====
  const mm = [...md.matchAll(/```mermaid\n([\s\S]*?)```/g)].map(m => m[1])
  let badTick = 0
  mm.forEach(b => { badTick += (b.match(/-->\s*\|`[^`]*`\|/g) || []).length })
  if (!badTick) ok(`Mermaid 图 ${mm.length} 个，无反引号边标签`) ; else P0(`${badTick} 处 Mermaid 反引号边标签`)
  if (!/style\s+\w+\s+fill:#[0-2]/.test(md)) ok('无深色背景') ; else P1('疑似深色背景')

  // ===== 专项 B1：三份分工不混 =====
  if (name === '08-实战经验.md') {
    console.log('\n[B1 学习态定位：讲原理，给五段式]')
    const modes = (md.match(/故障模式 \d/g) || []).length
    if (modes >= 5) ok(`故障模式 ${modes} 条（要求 5-10）`) ; else P1(`故障模式仅 ${modes} 条`)
    for (const seg of ['症状', '根因', '排查路径', '修复', '预防']) {
      if (md.includes(seg)) ok(`五段式含「${seg}」`) ; else P1(`五段式缺「${seg}」`)
    }
    console.log('\n[B2 症状可观测]')
    // 症状必须含具体数字或报错原文
    if (/HTTP 4\d\d|HTTP \*\*4\d\d|报错原文|一眼识别/.test(md)) ok('症状给了报错原文/HTTP 码')
    else P1('症状不够可观测')
    console.log('\n[B3 适用边界]')
    if (/适用边界|反模式|别用/.test(md)) ok('有适用边界/反模式段') ; else P0('缺适用边界')
    console.log('\n[B4 证据纪律：可溯源]')
    const evi = (md.match(/【本机实测】/g) || []).length
    const doc = (md.match(/【官方文档】/g) || []).length
    ok(`证据标注：本机实测 ${evi} 处、官方文档 ${doc} 处`)
    if (/核查于/.test(md)) ok('官方来源标注了核查时间') ; else P1('官方来源未标核查时间')
    if (/未实测|本机.*未复现|无法.*复现/.test(md)) ok('明确声明了未实测项') ; else P1('未声明哪些未实测')
    console.log('\n[B5 不硬凑]')
    if (/宁缺毋滥|不硬凑|如实写/.test(md) || evi + doc >= 7) ok('条目均有证据支撑') ; else P2('需确认是否凑数')
    console.log('\n[B6 案例可溯源]')
    if (/真实事故|案例复盘/.test(md)) {
      if (/本机.*没有真实生产事故|非虚构|均来自.*实测/.test(md)) ok('案例来源已诚实声明')
      else P1('案例可能虚构或来源不明')
    }
    console.log('\n[B7 与另两份的分工]')
    if (/与另两份产物的分工|去哪/.test(md)) ok('有分工说明') ; else P1('缺分工说明')
  }

  if (name === '09-排障速查手册.md') {
    console.log('\n[B8 QRH 五特征]')
    if (/索引表/.test(md)) ok('① 有症状索引表（按现象倒查）') ; else P0('① 缺症状索引表')
    if (/一眼识别/.test(md)) ok('② 每条有「一眼识别」') ; else P0('② 缺一眼识别')
    if (/止血/.test(md)) ok('③ 有止血步骤')
    else P0('③ 缺止血步骤')
    // 止血必须是表格第一行
    const rows = [...md.matchAll(/\|\s\*\*止血 1\*\*/g)].length
    if (rows >= 3) ok(`③ 「止血 1」出现在 ${rows} 个条目的首位`) ; else P1('③ 止血步骤偏少')
    // 条件-动作表：表头为 | 步骤 | 动作 | 预期 |（动作随条件分叉）
    const condTbl = (md.match(/\|\s*步骤\s*\|\s*动作\s*\|\s*预期\s*\|/g) || []).length
    if (condTbl >= 5) ok(`④ 条件-动作表 ${condTbl} 张（步骤/动作/预期）`) ; else P1(`④ 条件-动作表仅 ${condTbl} 张`)
    if (/若无效/.test(md)) ok('⑤ 每条有升级出口「若无效」') ; else P0('⑤ 缺升级出口（死胡同）')
    const exits = (md.match(/若无效/g) || []).length
    ok(`⑤ 升级出口出现 ${exits} 次`)
    console.log('\n[B9 紧急度分级]')
    if (/🔴/.test(md) && /🟡/.test(md) && /⚪/.test(md)) ok('有三档紧急度') ; else P1('紧急度分级不全')
    console.log('\n[B10 手册只给动作不给原理]')
    if (/只给动作|不给原理|想懂原理/.test(md)) ok('声明了"只给动作"') ; else P2('未声明定位')
    // 每条应回指经验层
    const back = (md.match(/原理\*\*：→ \[08-实战经验/g) || []).length
    if (back >= 5) ok(`回指经验层 ${back} 处`) ; else P1(`回指经验层仅 ${back} 处`)
    console.log('\n[B11 条目数]')
    const entries = [...new Set([...md.matchAll(/## (?:🔴|🟡|⚪) (E\d+)/g)].map(m => m[1]))]
    ok(`收录条目 ${entries.length} 个：${entries.join(', ')}`)
  }

  if (name === '10-场景解法库.md') {
    console.log('\n[C1 多解法：每场景 ≥3 个]')
    const scenes = [...md.matchAll(/## 场景 (\d)/g)].map(m => m[1])
    ok(`场景数 = ${scenes.length}（要求 5-8）`)
    // 每个场景的"解法一览"表格行数
    const tables = [...md.matchAll(/解法一览([\s\S]*?)### 推荐路径/g)]
    tables.forEach((t, i) => {
      const rows = (t[1].match(/^\| \*\*[A-F]\./gm) || []).length
      if (rows >= 3) ok(`场景 ${i + 1} 有 ${rows} 个解法（≥3 ✓）`)
      else P0(`场景 ${i + 1} 仅 ${rows} 个解法（要求 ≥3）`)
    })
    console.log('\n[C2 先想后看：折叠]')
    const details = (md.match(/<details>/g) || []).length
    const closers = (md.match(/<\/details>/g) || []).length
    if (details === closers && details > 0) ok(`<details> 标签配对：${details} 组`) ; else P0('details 标签不配对')
    if (/🔒 先自己想/.test(md)) ok('每场景有「🔒 先自己想」') ; else P0('缺「先自己想」环节')
    if (/💡 提示/.test(md)) ok('有折叠提示') ; else P1('缺折叠提示')
    if (/📖 展开解法/.test(md)) ok('有折叠解法') ; else P0('缺折叠解法')
    console.log('\n[C3 知识点挂钩]')
    const hooks = (md.match(/知识点挂钩/g) || []).length
    if (hooks >= scenes.length) ok(`知识点挂钩 ${hooks} 处，覆盖全部场景`) ; else P1(`知识点挂钩仅 ${hooks} 处`)
    console.log('\n[C4 递进路径 + 不适用边界]')
    if (/推荐路径/g.test(md)) ok('有推荐路径（递进）') ; else P0('缺推荐路径')
    const nb = (md.match(/不适用边界/g) || []).length
    if (nb >= scenes.length) ok(`不适用边界 ${nb} 处，覆盖全部场景`) ; else P1(`不适用边界仅 ${nb} 处`)
    console.log('\n[C5 场景具体可观测]')
    if (/可观测指标/.test(md)) ok('场景给了可观测指标') ; else P1('场景不够具体')
    console.log('\n[C6 解法有代价与边界]')
    const cost = (md.match(/\| 代价 \|/g) || []).length
    if (cost >= scenes.length) ok(`${cost} 个解法表含「代价」列`) ; else P1('解法表缺代价列')
    console.log('\n[C7 与课程课时挂钩（非孤立文章）]')
    if (/课 \d|课\d/.test(md)) ok('回指了课程课时') ; else P0('与课程脱节')
  }
}

console.log('\n================ 总结论 ================')
const c0 = issues.filter(i => i[0] === 'P0').length
const c1 = issues.filter(i => i[0] === 'P1').length
const c2 = issues.filter(i => i[0] === 'P2').length
console.log(`P0=${c0}  P1=${c1}  P2=${c2}`)
for (const [lv, s] of issues) console.log(` ${lv}: ${s}`)
