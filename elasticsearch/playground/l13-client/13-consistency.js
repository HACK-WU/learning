// 收官一致性核查：确认五份活文档的进度表述一致，且讲义链接可访问
const fs = require('fs');
const path = require('path');
const ROOT = 'D:/projects/learning/elasticsearch';

console.log('===== 收官一致性核查 =====\n');

// 1. 进度表述
console.log('【1】各文档的进度表述');
const checks = [
  { file: '00-学习档案.md', re: /\| 5 \| 课14 \| 知识体系收束 \| ✅ 已完成/, desc: '档案：课14 三知识点已完成' },
  { file: '00-评审清单.md', re: /^- \[x\] 阶段 5 · 课14/m, desc: '评审清单：课14 已勾选' },
  { file: '02-课程目录.md', re: /42 \/ 42 已完成/, desc: '目录：42/42' },
  { file: 'stages/5-生产与选型/overview.md', re: /✅ \*\*已完成\*\*（6\/6）/, desc: '阶段5概览：6/6 已完成' },
  { file: '01-学习路径总览.md', re: /阶段 5：生产与选型 ✅（课 13-14 · 6 知识点 · 已完成 6）/, desc: '总览：阶段5 已完成' },
];
let allOk = true;
checks.forEach(c => {
  let txt = '';
  try { txt = fs.readFileSync(path.join(ROOT, c.file), 'utf8'); } catch (e) { console.log(`  ❌ 读不到 ${c.file}`); allOk = false; return; }
  const ok = c.re.test(txt);
  if (!ok) allOk = false;
  console.log(`  ${ok ? '✅' : '❌'} ${c.desc}`);
});

// 2. 档案里还有没有"待学"
console.log('\n【2】档案中残留的「待学」');
const archive = fs.readFileSync(path.join(ROOT, '00-学习档案.md'), 'utf8');
const pending = (archive.match(/⬜ 待学/g) || []).length;
const done = (archive.match(/✅ 已完成/g) || []).length;
console.log(`  待学：${pending} 处 ｜ 已完成：${done} 处`);
if (pending > 0) {
  allOk = false;
  archive.split('\n').forEach((l, i) => { if (l.includes('⬜ 待学')) console.log(`    行 ${i + 1}: ${l.slice(0, 70)}`); });
}

// 3. 讲义文件与链接
console.log('\n【3】14 课讲义是否全部落盘');
const lessonDirs = [
  'stages/1-为什么需要ES/lessons',
  'stages/2-核心原理与上手/lessons',
  'stages/3-查询与聚合/lessons',
  'stages/4-分布式与工程实践/lessons',
  'stages/5-生产与选型/lessons',
];
let lessonCount = 0;
lessonDirs.forEach(d => {
  const full = path.join(ROOT, d);
  if (!fs.existsSync(full)) { console.log(`  ❌ 目录不存在：${d}`); allOk = false; return; }
  const files = fs.readdirSync(full).filter(f => f.endsWith('.md'));
  lessonCount += files.length;
  console.log(`  ✅ ${d.split('/')[1]}：${files.length} 篇`);
});
console.log(`  合计 ${lessonCount} 课 ${lessonCount === 14 ? '✅' : '❌（应为 14）'}`);
if (lessonCount !== 14) allOk = false;

// 4. 课14 讲义结尾两段
console.log('\n【4】课14 结尾两段');
const l14 = fs.readFileSync(path.join(ROOT, 'stages/5-生产与选型/lessons/lesson-14-该不该用ES.md'), 'utf8');
const hasHandoff = l14.includes('🚀 下一批接力提示词');
const hasNav = l14.includes('🧭 课程导航');
console.log(`  ${hasHandoff ? '✅' : '❌'} 接力提示词`);
console.log(`  ${hasNav ? '✅' : '❌'} 课程导航`);
if (!hasHandoff || !hasNav) allOk = false;

// 5. 课14 五幕
console.log('\n【5】课14 五幕结构');
['第一幕', '第二幕', '第三幕', '第四幕', '第五幕'].forEach(a => {
  const ok = l14.includes(a);
  if (!ok) allOk = false;
  console.log(`  ${ok ? '✅' : '❌'} ${a}`);
});

// 6. 课14 脚本是否都在
console.log('\n【6】课14 引用的脚本');
const scripts = ['04-benchmark.js', '05-limits.js', '06-nrt.js', '07-syllabus.js'];
scripts.forEach(s => {
  const p = path.join(ROOT, 'playground/l13-client', s);
  const ok = fs.existsSync(p);
  if (!ok) allOk = false;
  console.log(`  ${ok ? '✅' : '❌'} ${s}`);
});

console.log('\n===== 结论 =====');
console.log(allOk ? '✅ 全部一致，课程可以收官交付。' : '❌ 存在不一致，需修正。');
