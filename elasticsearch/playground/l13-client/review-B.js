// 评审视角 B：零基础教学体验
// 职责：假设读者只学过前 13 课、对 ES 无更多背景，逐段检查能不能看懂、能不能照做
const fs = require('fs');
const LESSON = 'D:/projects/learning/elasticsearch/stages/5-生产与选型/lessons/lesson-14-该不该用ES.md';
const text = fs.readFileSync(LESSON, 'utf8');
const lines = text.split('\n');

const findings = [];
function add(level, section, issue, suggestion) {
  findings.push({ level, section, issue, suggestion });
}

console.log('===== 评审 B：零基础教学体验 =====\n');

// --- 1. 术语首次出现是否有解释 ---
console.log('【1】术语解释（首次出现是否通俗化）');
const terms = [
  { kw: '近实时', desc: 'NRT', needExplain: true },
  { kw: '乐观锁', desc: 'optimistic concurrency', needExplain: true },
  { kw: '反范式', desc: 'denormalize', needExplain: true },
  { kw: '协调节点', desc: 'coordinating node', needExplain: true },
  { kw: '段', desc: 'segment', needExplain: true },
  { kw: 'translog', desc: '事务日志', needExplain: true },
  { kw: '分位数', desc: 'p50/p95', needExplain: true },
  { kw: '扇出', desc: 'fan-out', needExplain: true },
];
terms.forEach(t => {
  const idx = text.indexOf(t.kw);
  if (idx === -1) { console.log(`  ⚠️  讲义未出现：${t.kw}`); return; }
  // 看前后 200 字符内有没有解释性文字
  const ctx = text.slice(Math.max(0, idx - 200), idx + 200);
  const hasExplain = /（|\(|:|：|就是|指的是|意思是/.test(ctx);
  console.log(`  ${hasExplain ? '✅' : '⚠️ '} ${t.kw.padEnd(10)} ${hasExplain ? '有解释' : '可能缺解释'}`);
  if (!hasExplain && t.needExplain) add('P2', '术语', `「${t.kw}」首次出现未见解释`, `补一句通俗说明（${t.desc}）`);
});

// --- 2. 类比是否贯穿且有失效说明 ---
console.log('\n【2】类比使用');
const hasAnalogy = text.includes('消防车');
console.log(`  ${hasAnalogy ? '✅' : '❌'} 有贯穿类比（消防车）`);
const analogyCount = (text.match(/消防车/g) || []).length;
console.log(`     出现 ${analogyCount} 次`);
if (analogyCount < 3) add('P2', '类比', '类比出现次数偏少，未真正贯穿', '在三个知识点各回扣一次');
const hasLimit = text.includes('类比失效') || text.includes('边界');
console.log(`  ${hasLimit ? '✅' : '❌'} 有类比失效说明`);
if (!hasLimit) add('P1', '类比', '未说明类比的适用边界', '补「类比失效的地方」小节');

// --- 3. 五幕结构的叙事弧 ---
console.log('\n【3】叙事弧（认知冲突是否建立）');
const conflictWords = ['想当然', '反直觉', '坑', '误区', '不是', '错了', '陷阱'];
let conflictHits = 0;
conflictWords.forEach(w => { if (text.includes(w)) conflictHits++; });
console.log(`  认知冲突关键词命中 ${conflictHits} 个（${conflictWords.filter(w => text.includes(w)).join('、')}）`);
if (conflictHits < 3) add('P2', '叙事', '认知冲突建立不足', '开篇先抛一个反直觉现象');

// --- 4. 可执行性：读者能照着做吗 ---
console.log('\n【4】可执行性');
const scriptRefs = (text.match(/playground\/l13-client\/\d+-\w+\.js/g) || []);
console.log(`  引用本机脚本 ${scriptRefs.length} 处：${[...new Set(scriptRefs)].join(', ')}`);
if (scriptRefs.length === 0) add('P1', '可执行', '未给出可复现的脚本路径', '补脚本路径让读者能重跑');

const hasRebuildCmd = text.includes('curl.exe');
console.log(`  ${hasRebuildCmd ? '✅' : '⚠️ '} 有 curl.exe 命令示例`);
if (!hasRebuildCmd) add('P2', '可执行', '缺少可直接复制的命令', '关键验证步骤给命令');

// --- 5. 每个知识点是否有"我学会了吗"的检验 ---
console.log('\n【5】学习闭环');
const hasSummary = text.includes('本课小结') || text.includes('小结');
console.log(`  ${hasSummary ? '✅' : '❌'} 有本课小结`);
if (!hasSummary) add('P1', '闭环', '缺少本课小结', '补小结表');

const hasNext = text.includes('下一步') || text.includes('接下来');
console.log(`  ${hasNext ? '✅' : '❌'} 有下一步指引`);
if (!hasNext) add('P2', '闭环', '缺少学完之后做什么的指引', '');

// --- 6. 收官课的特殊要求 ---
console.log('\n【6】收官课 special：全课收束');
const hasFullMap = text.includes('42') && (text.includes('知识点'));
console.log(`  ${hasFullMap ? '✅' : '❌'} 有 42 知识点全景`);
if (!hasFullMap) add('P1', '收官', '收官课未给出 42 知识点全景', '补全景地图');

const hasCheatsheet = text.includes('排查') || text.includes('速查');
console.log(`  ${hasCheatsheet ? '✅' : '❌'} 有排查/速查内容`);
if (!hasCheatsheet) add('P2', '收官', '缺少可查阅的排查清单', '补四层排查法');

// --- 7. 认知负荷：单节是否过长 ---
console.log('\n【7】认知负荷');
let curSection = '', curLen = 0, maxLen = 0, maxSec = '';
lines.forEach(l => {
  if (l.startsWith('# ')) {
    if (curLen > maxLen) { maxLen = curLen; maxSec = curSection; }
    curSection = l; curLen = 0;
  } else curLen += l.length;
});
if (curLen > maxLen) { maxLen = curLen; maxSec = curSection; }
console.log(`  最长章节：${maxSec.slice(0, 40)}（约 ${maxLen} 字符）`);
if (maxLen > 8000) add('P2', '认知负荷', `单节过长（${maxLen} 字符）`, '考虑拆分');
else console.log('  ✅ 章节长度适中');

// --- 8. 是否有"陷阱预警" ---
console.log('\n【8】陷阱预警');
const warnCount = (text.match(/⚠️|❌|⛔/g) || []).length;
console.log(`  警告标记 ${warnCount} 处`);
if (warnCount < 5) add('P2', '预警', '陷阱预警偏少', '关键坑位加 ⚠️ 标记');

// --- 9. 数字是否有"这是什么"的说明 ---
console.log('\n【9】实测数据的可读性');
const bareNumbers = text.match(/(?<![\d.])\d{2,}\.\d{2} ?ms/g) || [];
console.log(`  出现 ${bareNumbers.length} 处延迟数字：${bareNumbers.slice(0, 5).join(', ')}`);
console.log(`  ${text.includes('p50') && text.includes('p95') ? '✅' : '⚠️ '} 有 p50/p95 说明`);
if (!(text.includes('p50') && text.includes('分位'))) {
  add('P2', '可读性', 'p50/p95 未解释含义', '补一句"p95 = 95% 的请求快于这个值"');
}

// --- 汇总 ---
console.log('\n\n===== B 视角汇总 =====');
const byLevel = { P0: 0, P1: 0, P2: 0 };
findings.forEach(f => byLevel[f.level]++);
console.log(`P0 × ${byLevel.P0} ｜ P1 × ${byLevel.P1} ｜ P2 × ${byLevel.P2}`);
console.log('');
findings.forEach((f, i) => {
  console.log(`${i + 1}. [${f.level}] ${f.section}｜${f.issue}`);
  if (f.suggestion) console.log(`   建议：${f.suggestion}`);
});
