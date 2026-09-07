# -*- coding: utf-8 -*-
"""课 3 档案回写：进度表 + 评审记录 + 断点信息 + 环境资产（幂等，可重复执行）"""
import io, re, sys

BASE = '/mnt/d/projects/learning/grafana/'

def rw(path, fn):
    with io.open(path, encoding='utf-8') as f:
        t = f.read()
    new = fn(t)
    if new == t:
        print('  未变更:', path.split('/')[-1]); return False
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(new)
    print('  已更新:', path.split('/')[-1]); return True

# ---------- 1. 学习档案：进度表 ----------
def f_archive(t):
    rows = [
        ('| 3.1 | Dashboard 与 Panel 的关系：时间选择器是共享的 | 课 3 | ⬜ 未开始 |',
         '| 3.1 | Dashboard 与 Panel 的关系：时间选择器是共享的 | 课 3 | ✅ 已完成 |'),
        ('| 3.2 | 变量入门：`$host` 从哪来、怎么注入查询 | 课 3 | ⬜ 未开始 |',
         '| 3.2 | 变量入门：`$host` 从哪来、怎么注入查询 | 课 3 | ✅ 已完成 |'),
        ('| 3.3 | Row 与折叠、面板复用与 JSON Model 初见 | 课 3 | ⬜ 未开始 |',
         '| 3.3 | Row 与折叠、面板复用与 JSON Model 初见 | 课 3 | ✅ 已完成 |'),
    ]
    for old, new in rows:
        if old in t: t = t.replace(old, new)
    t = t.replace(
        '**进度统计**：6 / 36 知识点（阶段 1：6/9 ✅进行中，阶段 2：0/9，阶段 3：0/9，阶段 4：0/9）',
        '**进度统计**：9 / 36 知识点（阶段 1：9/9 ✅已完成，阶段 2：0/9，阶段 3：0/9，阶段 4：0/9）')
    return t

rw(BASE + '00-学习档案.md', f_archive)

# ---------- 2. 学习档案：评审记录追加 ----------
REVIEW_ROW = (
'| 2026-09-04 | 课 3《变量与 Dashboard 组织》 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） | 0 | '
'**两个推翻性实测发现**：'
'①**面板 `timeFrom` 是前端概念，后端不认**——三重取证（API 读回确认持久化 + 后端查询步长对照 + 数据库直查）：dashboard 窗口 6h 时，声明 `timeFrom=\'10m\'` 的面板 B 与跟随 dashboard 的面板 A 步长**同为 20000ms**，而 10m 窗口基准应为 1000ms。结论：`timeFrom` 只裁剪显示、不改取数窗口。'
'②**自定义变量与内置变量的插值位置不同**——探针抓包（在 Grafana 与数据源之间放记录型代理）实测：后端真正发出的 HTTP 报文里，`$__rate_interval` 已被替换成 `1m0s`，而 `$host` **原样透传**（body 中为 `%24host`）。即自定义变量由**前端**替换、内置时间变量由**后端**替换。直接调 `/api/ds/query` 传 `scopedVars` 不生效（放 query 里、放顶层 payload 里均试过），这正是"用 API 查不出数据"的根因。'
'**多值写法实测**：`up{instance=~"$host"}` → 3 帧 3 点；误用 `=` → 1 帧 **0 点**（静默无数据，不报错）。'
'**P1×3 已修**：①`timeFrom` 初稿仅单一接口证据，已补三重取证；②3 台 node-exporter 来源未说明（课 2 交付时只有 1 台），已补环境说明块；③Prometheus 未开 lifecycle、改配置需重启，已在第四幕标注原因。'
'**死链 5 条已修**（与课 2 同一个坑）：返回根目录链接写成 `../../` 应为 `../../../`（`lessons/` 距根三层）；课 4 链接写成 `../2-查得到/` 应为 `../../2-查得到/`。'
'**评审中判定为脚本缺陷、未改文档×3**：①探针日志写在容器内 `/tmp` 而检查读宿主机 `/tmp`（路径不共享）→ 改 bind mount；②测试脚本命名 `bisect.py` 与 Python 标准库冲突致循环导入 → 重命名；③转发探针未处理 gzip 致 500 → 解压后转发即正常。'
'**校验脚本自身缺陷 1 项已修**：B3 用 `if grep -q` 判空，未匹配时也报 ✅，与 B2 死链报告自相矛盾 → 改为显式判定存在性 + 单独检测两级误写。'
'**环境变更（跨课有效）**：为讲"N 台机器"新增 `grafana-node2`(9102,hostname=node-alpha)、`grafana-node3`(9103,hostname=node-beta)，`prometheus.yml` 的 node job 改为 3 个 targets；另修 gzip 问题（Prometheus 返回 gzip 而本环境插件解压失败，导致空 frame 不报错），已给 PromLab 加 `Accept-Encoding: identity` 请求头。'
' |')

def f_review(t):
    if '课 3《变量与 Dashboard 组织》' in t:
        return t
    marker = '| 2026-09-04 | 课 2《第一个面板》 |'
    idx = t.find(marker)
    if idx < 0:
        print('  ⚠️ 未找到课 2 评审行锚点'); return t
    end = t.find('\n', idx)
    return t[:end+1] + REVIEW_ROW + '\n' + t[end+1:]

rw(BASE + '00-学习档案.md', f_review)

# ---------- 3. 学习档案：断点信息与环境资产 ----------
def f_break(t):
    t = t.replace(
        '- **当前位置**：阶段 1 课 2 已交付（6/36 知识点），等待用户确认后进入课 3\n'
        '- **下一批**：阶段 1 课 3《变量与 Dashboard 组织：一张图服务 N 台机器》知识点 3.1 / 3.2 / 3.3',
        '- **当前位置**：阶段 1 课 3 已交付（9/36 知识点，阶段 1 全部完成），等待用户确认后进入阶段 2\n'
        '- **下一批**：阶段 2 课 4《查询编辑器与数据源协议：一次查询的完整旅程》知识点 4.1 / 4.2 / 4.3')
    t = t.replace(
        '- **环境状态**：`grafana-lab`(3001) + `grafana-prom`(9201) + `grafana-node`(9101) 在 `grafana-net` 内运行中；数据源 `PromLab` 已建（uid=afx7x6dx803y8e）',
        '- **环境状态**：`grafana-lab`(3001) + `grafana-prom`(9201) + 3 台 node-exporter(9101/9102/9103) 在 `grafana-net` 内运行中；数据源 `PromLab` 已建（uid=afx7x6dx803y8e，已加 `Accept-Encoding: identity` 头绕开 gzip 问题）')
    return t

rw(BASE + '00-学习档案.md', f_break)

# ---------- 4. 学习档案：环境资产表 ----------
def f_assets(t):
    old = '| 容器 | `grafana-lab`(3001) / `grafana-prom`(9201) / `grafana-node`(9101) |'
    new = ('| 容器 | `grafana-lab`(3001) / `grafana-prom`(9201) / `grafana-node`(9101) / '
           '`grafana-node2`(9102,hostname=node-alpha) / `grafana-node3`(9103,hostname=node-beta) |')
    if old in t: t = t.replace(old, new)
    add = ('| 多实例环境 | 课 3 起 node 共 3 台，脚本 `playground/l03-nodes-up.sh`（幂等）；'
           '`prometheus.yml` 的 node job 含 3 个 targets，改完需 `docker restart grafana-prom`（未开 lifecycle） |\n'
           '| gzip 规避 | PromLab 数据源 jsonData 设 `httpHeaderName1=Accept-Encoding` / `httpHeaderValue1=identity`，'
           '脚本 `playground/l03-fix-gzip.sh`（幂等）。症状：面板无数据但不报错 |\n'
           '| 存储层变化 | Grafana 13.2.1 的 dashboard 存在 **`resource`** 表（k8s 风格，`group=dashboard.grafana.app`），'
           '旧 `dashboard` 表 0 行；`resource_history` 保存历史版本 |\n'
           '| 代理路径 | 13.2.1 用 `/api/datasources/proxy/uid/{uid}/...`，按 id 的旧路径已 **404** |')
    anchor = '| 端口避让 | 9091 已被 pushgateway 占'
    idx = t.find(anchor)
    if idx > 0 and 'gzip 规避' not in t:
        end = t.find('\n', idx)
        t = t[:end+1] + add + '\n' + t[end+1:]
    return t

rw(BASE + '00-学习档案.md', f_assets)

print('\n=== 学习档案回写完成 ===')
