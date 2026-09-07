# -*- coding: utf-8 -*-
"""评审清单：追加课 3 评审记录行（幂等）"""
import io
P = '/mnt/d/projects/learning/grafana/00-评审清单.md'
MARK = '| 2026-09-04 | 课 3《变量与 Dashboard 组织》 |'

with io.open(P, encoding='utf-8') as f:
    lines = f.read().split('\n')

if any(MARK in l for l in lines):
    print('  课 3 评审记录已存在，跳过')
    raise SystemExit(0)

ROW = (
'| 2026-09-04 | 课 3《变量与 Dashboard 组织》 | 主 agent 内联（pedagogy + learner，子 agent 未创建，独立性受限） | 0 | '
'**两个推翻性实测发现**：'
'①**面板 `timeFrom` 是前端概念、后端不认**——三重取证（API 读回确认持久化／后端查询步长对照／数据库直查）：'
'dashboard 窗口 6h 时，声明 `timeFrom=\'10m\'` 的面板 B 与跟随 dashboard 的面板 A 步长**同为 20000ms**，'
'而 10m 窗口基准应为 1000ms。'
'②**自定义变量与内置变量插值位置不同**——探针抓包实测后端真实 HTTP 报文：`$__rate_interval` 已被替换为 `1m0s`，'
'`$host` **原样透传**（body 中 `%24host`）。'
'**多值写法实测**：`=~` → 3 帧 3 点；误用 `=` → 1 帧 0 点（静默无数据，不报错）。'
'**P1×3 已修**：`timeFrom` 补三重取证；3 台 node-exporter 来源补环境说明；Prometheus 未开 lifecycle 已标注原因。'
'**死链 5 条已修**（与课 2 同坑）：根目录链接 `../../`→`../../../`；课 4 链接 `../2-查得到/`→`../../2-查得到/`。'
'**脚本缺陷×3、未改文档**：探针日志路径容器内外不共享／`bisect.py` 与 Python 标准库冲突致循环导入／转发探针未处理 gzip 致 500。'
'**校验脚本缺陷 1 项已修**：B3 用 `if grep -q` 判空，未匹配时也报 ✅，与 B2 死链报告自相矛盾 → 改显式判定。'
'**环境变更跨课有效**：新增 `grafana-node2`/`grafana-node3`；PromLab 加 `Accept-Encoding: identity` 绕开 gzip |'
)

# 插到表格最后一行之后（即最后一个以 '| 2026-' 开头的行之后）
last = max(i for i, l in enumerate(lines) if l.startswith('| 2026-'))
lines.insert(last + 1, ROW)

with io.open(P, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('  ✅ 已追加课 3 评审记录')
