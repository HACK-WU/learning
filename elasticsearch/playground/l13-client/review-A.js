// 评审视角 A：技术事实核查
// 职责：讲义里的每个数字、每条命令、每个考纲条目，是否都能在本机复现 / 有权威来源支撑
const fs = require('fs');
const path = require('path');

const LESSON = 'D:/projects/learning/elasticsearch/stages/5-生产与选型/lessons/lesson-14-该不该用ES.md';
const text = fs.readFileSync(LESSON, 'utf8');

const findings = [];
function add(level, section, issue, evidence) {
  findings.push({ level, section, issue, evidence });
}

console.log('===== 评审 A：技术事实核查 =====');
console.log(`讲义字数：${text.length} 字符\n`);

// --- 检查 1：五幕结构（必查项 #2）---
console.log('【检查 1】五幕结构完整性');
const acts = ['第一幕', '第二幕', '第三幕', '第四幕', '第五幕'];
const missingActs = acts.filter(a => !text.includes(a));
if (missingActs.length) {
  add('P1', '结构', `缺少五幕结构标记：${missingActs.join('、')}`, '必查项 #2 要求：场景引入→认知冲突→层层揭示→实操验证→体系收束');
  console.log(`  ❌ 缺少：${missingActs.join('、')}`);
} else {
  console.log('  ✅ 五幕齐全');
}

// --- 检查 2：结尾两段（必查项 #1）---
console.log('\n【检查 2】结尾两段（接力提示词 + 课程导航）');
const hasHandoff = text.includes('下一批接力提示词') || text.includes('接力提示词');
const hasNav = text.includes('课程导航');
if (!hasHandoff) { add('P1', '结尾', '缺少「🚀 下一批接力提示词」段', '必查项 #1，PromQL L1 / ZK L1 曾两次遗漏'); console.log('  ❌ 缺接力提示词'); }
else console.log('  ✅ 有接力提示词');
if (!hasNav) { add('P1', '结尾', '缺少「🧭 课程导航」段', '必查项 #1'); console.log('  ❌ 缺课程导航'); }
else console.log('  ✅ 有课程导航');

// --- 检查 3：实测数据是否都有出处 ---
console.log('\n【检查 3】讲义中的关键数字 vs 实测记录');
const claims = [
  { num: '15.23', src: 'benchmark p50 (1分片)', ok: true },
  { num: '35.90', src: 'benchmark p95 (50分片)', ok: true },
  { num: '16.58', src: 'benchmark p95 (1分片)', ok: true },
  { num: '361.9', src: '50分片存储 kb', ok: true },
  { num: '77.3', src: '1分片存储 kb', ok: true },
  { num: '82', src: 'doc_count_error_upper_bound', ok: true },
  { num: '409', src: 'version_conflict HTTP码', ok: true },
];
claims.forEach(c => {
  const inText = text.includes(c.num);
  console.log(`  ${inText ? '✅' : '❌'} ${c.num.padEnd(8)} (${c.src})`);
  if (!inText) add('P2', '数据', `讲义未引用实测数字 ${c.num}`, c.src);
});

// --- 检查 4：p95 倍数说法是否与数据一致 ---
console.log('\n【检查 4】结论与数据是否自洽');
const p50_1 = 15.23, p95_1 = 16.58, p95_50 = 35.90;
const ratio = (p95_50 / p95_1).toFixed(1);
console.log(`  实测 p95 倍数 = ${p95_50} / ${p95_1} = ${ratio} 倍`);
if (text.includes('2.2 倍') || text.includes('2.2倍')) {
  console.log(`  ✅ 讲义写 2.2 倍，与实测 ${ratio} 倍一致`);
} else {
  add('P2', '数据', `p95 倍数说法与实测(${ratio}倍)不符`, '讲义写了其他倍数');
  console.log(`  ⚠️ 讲义的倍数说法需核对（实测 ${ratio} 倍）`);
}
const storeRatio = (361.9 / 77.3).toFixed(1);
console.log(`  存储倍数 = 361.9 / 77.3 = ${storeRatio} 倍`);
if (text.includes('4.7')) console.log('  ✅ 讲义写 4.7 倍，与实测一致');
else { add('P2', '数据', `存储倍数应为 ${storeRatio}`, ''); console.log(`  ⚠️ 应为 ${storeRatio} 倍`); }

// --- 检查 5：考纲条目的准确性 ---
console.log('\n【检查 5】9.3 考纲表述');
const syllabusFacts = [
  { kw: '2026-09-01', desc: '考纲升级生效日' },
  { kw: '8.15', desc: '旧版本' },
  { kw: '9.3', desc: '新版本' },
  { kw: 'Architecture', desc: '新增大类' },
  { kw: 'semantic search', desc: '新增考点' },
  { kw: 'runtime fields', desc: '已移除' },
  { kw: '$500', desc: '考试费用' },
];
syllabusFacts.forEach(f => {
  const ok = text.includes(f.kw);
  console.log(`  ${ok ? '✅' : '❌'} ${f.kw.padEnd(18)} ${f.desc}`);
  if (!ok) add('P1', '考纲', `缺少关键事实 ${f.kw}`, f.desc);
});

// --- 检查 6：license 相关表述 ---
console.log('\n【检查 6】basic license 限制表述');
if (text.includes('non-compliant for [inference]')) console.log('  ✅ 引用了 semantic_text 报错原文');
else add('P2', 'license', '未引用 semantic_text 报错原文', '');
if (text.includes('basic')) console.log('  ✅ 说明了 license=basic');
else add('P1', 'license', '未说明两个集群 license 为 basic', '');

// --- 检查 7：跨课引用（必查项 #7）---
console.log('\n【检查 7】跨课引用准确性');
const crossRefs = [
  { kw: 'l10_shard_1', desc: '课10 数据', stage: '课10' },
  { kw: 'l9_orders', desc: '课9 数据', stage: '课9' },
  { kw: 'l13_vector_demo', desc: '课13 数据', stage: '课13' },
  { kw: 'l13_rag_kb', desc: '课13 数据', stage: '课13' },
  { kw: 'l13-logs-app', desc: '课13 data stream', stage: '课13' },
];
crossRefs.forEach(r => {
  const ok = text.includes(r.kw);
  console.log(`  ${ok ? '✅' : '⚠️ '} ${r.kw.padEnd(20)} (${r.desc})`);
});

// --- 检查 8：命令可运行性（必查项 #5）---
console.log('\n【检查 8】命令可运行性');
const badPatterns = [
  { re: /\| grep/, desc: '用了 grep（本机无）', level: 'P0' },
  { re: /docker/i, desc: '依赖 Docker（本机未装）', level: 'P0' },
  { re: /Invoke-RestMethod/, desc: '用 Invoke-RestMethod（实测连不上）', level: 'P0' },
  { re: /-d '\{/, desc: 'Git Bash 单引号内联 JSON（本机无 Git Bash）', level: 'P1' },
];
badPatterns.forEach(p => {
  const m = text.match(p.re);
  if (m) { add(p.level, '命令', p.desc, `匹配到：${m[0]}`); console.log(`  ❌ ${p.desc}`); }
  else console.log(`  ✅ 无「${p.desc}」问题`);
});

// --- 检查 9：全文中文（必查项 #3）---
console.log('\n【检查 9】中英混杂');
const mixed = ['kicks in', 'under the hood', 'trade-off 是', 'best practice 是'];
let mixedFound = 0;
mixed.forEach(m => { if (text.includes(m)) { mixedFound++; add('P2', '语言', `中英混杂：${m}`, ''); } });
console.log(mixedFound === 0 ? '  ✅ 未发现中英混杂' : `  ❌ 发现 ${mixedFound} 处`);

// --- 检查 10：Mermaid / SVG（必查项 #8 #9 #10）---
console.log('\n【检查 10】图表');
const hasMermaid = text.includes('```mermaid');
const hasSvg = text.includes('<svg');
console.log(`  ${hasMermaid ? '有 Mermaid' : '无 Mermaid'}`);
if (hasMermaid) {
  const backtickLabel = /\|.*`.*\|/.test(text);
  if (backtickLabel) { add('P1', 'Mermaid', '边标签含反引号（Mermaid<10.3 渲染失败）', ''); console.log('  ❌ 边标签含反引号'); }
  else console.log('  ✅ 无反引号边标签');
}
console.log(`  ${hasSvg ? '有 SVG（需检查浅色主题）' : '无 SVG'}`);

// --- 汇总 ---
console.log('\n\n===== A 视角汇总 =====');
const byLevel = { P0: 0, P1: 0, P2: 0 };
findings.forEach(f => byLevel[f.level]++);
console.log(`P0 × ${byLevel.P0} ｜ P1 × ${byLevel.P1} ｜ P2 × ${byLevel.P2}`);
console.log('');
findings.forEach((f, i) => {
  console.log(`${i + 1}. [${f.level}] ${f.section}｜${f.issue}`);
  if (f.evidence) console.log(`   证据/说明：${f.evidence}`);
});
