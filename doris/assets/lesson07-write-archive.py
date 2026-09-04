import io

# 学习档案：追加评审记录 + 更新断点
p = '/mnt/d/projects/learning/doris/00-学习档案.md'
s = io.open(p, encoding='utf-8').read()

rec = (
    '| 2026-09-02 | 阶段 3·课 7 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） | '
    'P0×3 / P1×2 / P2×2。'
    'P0-1【learner·L2 可运行性】setup 脚本 docker exec 缺 -i，不转发 stdin，'
    'echo "$SQL" 管道给 docker exec mysql 静默无输出，建表/造数全部失败却不报错，后续 7 步全对不上 '
    '→ 补 docker exec -i + 注释说明。'
    'P0-2【learner·L2 可运行性】SHOW DATA 紧跟 INSERT 返回 0（依赖后台统计，实测延迟约 45 秒），'
    '正文预期输出写 5.17MB，读者照抄必然对不上 → 脚本加 sleep 60 + 正文说明。'
    'P0-3【pedagogy·数据真实性】第四幕步骤 4 的 1/2/3 个 pad 列耗时与 OutputBlockBytes 为未经实测的推测值'
    '（940MB/1.88GB/2.82GB），实测为 3.92MB/7.84MB/8.00MB → 全部替换为实测数据，并补口径说明。'
    'P1-1【learner·L3 预期一致】步骤 3/4 只给绝对值未说明浮动范围，读者数字对不上会误判跑错 '
    '→ 补浮动范围 + 「判断跑对看三件事」清单。'
    'P1-2【learner·L3】grep -A 12 取 OutputBlockBytes 得单 instance 值（8MB 上限）非全局（2.82GB），'
    '与步骤 2 口径冲突 → 补口径说明，声明本步骤不依赖该字段。'
    'P2-1【pedagogy·P3 图表一致】Profile 三层结构图未标注每层回答什么问题 → 已在图中补。'
    'P2-2【learner·L1】Block 切分规则未解释宽列为何块数更多（264→368）→ 补说明 | '
    '全部采纳并修订落盘，P0 清零后交付 |\n'
)

anchor = '| 2026-09-02 | 阶段 3·课 6 |'
assert anchor in s, 'anchor not found'
s = s.replace(anchor, rec + anchor, 1)

old_break = '- **当前位置**：阶段 3《数据导入与查询》课 6《数据导入全家桶》已完成（2026-09-02）；阶段 3 进度 1/3 课，整体 18/36 知识点'
new_break = '- **当前位置**：阶段 3《数据导入与查询》课 7《查询引擎与执行计划》已完成（2026-09-02）；阶段 3 进度 2/3 课，整体 21/36 知识点'
assert old_break in s, 'break not found'
s = s.replace(old_break, new_break)

old_next = '- **下一批**：阶段 3《数据导入与查询》课 7《查询引擎与执行计划》（知识点：MPP 执行流程、向量化执行与列存、EXPLAIN 与 Profile）'
new_next = '- **下一批**：阶段 3《数据导入与查询》课 8《多表关联与高级 SQL》（知识点：Join 与分布式 Join 策略、复杂类型与半结构化数据、异步物化视图与查询改写）'
assert old_next in s, 'next not found'
s = s.replace(old_next, new_next)

io.open(p, 'w', encoding='utf-8').write(s)
print('archive done')
