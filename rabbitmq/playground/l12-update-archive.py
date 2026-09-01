#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 收尾：更新 00-学习档案.md / 02-课程目录.md / 00-评审清单.md

要点：
  1. 进度表：课 12 三条知识点 → ✅ 已完成
  2. 档案「评审记录」表头插入课 12 评审记录
  3. 档案「大纲调整记录」插入课 12
  4. 档案「事实核查记录」插入本轮关键实测
  5. 评审清单：勾选课 9/10/11/12（课 9-11 为漏评审补勾）
  6. 课程目录：课 12 改为可点击链接 + 阶段 4 标记完成

重复判断一律用【行首精确锚点】，避免课 11 时踩过的子串误判
（当时因课 10 记录中含"下一课为课 11"字样导致漏插）。
"""
import io
import os
import sys

BASE = '/mnt/d/projects/learning/rabbitmq'
ARCHIVE = BASE + '/00-学习档案.md'
CATALOG = BASE + '/02-课程目录.md'
CHECKLIST = BASE + '/00-评审清单.md'
DATE = '2026-09-01'


def read(path):
    with io.open(path, encoding='utf-8') as f:
        return f.read()


def write(path, text):
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def replace_once(text, old, new, label):
    if old not in text:
        print("  ⚠️ 未找到锚点，跳过：%s" % label)
        return text, False
    if text.count(old) != 1:
        print("  ⚠️ 锚点不唯一（%d 处），跳过：%s" % (text.count(old), label))
        return text, False
    print("  ✅ %s" % label)
    return text.replace(old, new), True


def main():
    print("=" * 72)
    print("课 12 收尾：档案 / 目录 / 评审清单")
    print("=" * 72)

    # ================= 1. 进度表 =================
    print("\n[1] 学习档案 · 知识点级进度表")
    arch = read(ARCHIVE)
    for kp in ['典型消息模式', '选型对比', '生产落地清单']:
        old = '| 4 | 课 12 | %s | ⬜ 未开始 | - | - |' % kp
        new = '| 4 | 课 12 | %s | ✅ 已完成 | %s | - |' % (kp, DATE)
        arch, _ = replace_once(arch, old, new, '进度表：%s' % kp)

    # ================= 2. 评审记录 =================
    print("\n[2] 学习档案 · 评审记录")
    anchor = '| 日期 | 评审对象 | 评审方式 | 意见摘要 | 处置 |\n|------|----------|----------|----------|------|\n'
    row12 = (
        '| %s | 阶段 4·课 12《架构落地与选型决策》 | 主 agent 内联（pedagogy + learner） | '
        '**P0×2 已修、P1×3 已修、并补测完成一项初稿标注为"未跑通"的验证**：'
        '**P0-1（实测推翻初稿结论，本课最大内容升级）** 初稿标注「Direct Reply-To 完整往返未跑通」并列出三个叠加的坑。'
        '本轮重读官方文档发现漏看了一条硬约束——原文要求 RPC 客户端必须用**同一个连接和同一个信道**'
        '既从 `amq.rabbitmq.reply-to` 消费又发布请求消息。据此改用「单连接 + 单信道 + next() 预热注册 + 再发布」，'
        '**实测 4/4 往返成功、耗时 0.01s**。并补做三组对照（判据为"响应是否真的到达"而非"有没有报错"）：'
        '跨信道 → **不报错但响应静默丢失**（最危险的失败形态）；同信道但先发后注册 → 异步 406；'
        '同信道 + 先注册后发布 → 成功。已重写讲义方案 A 章节、速查卡、误区第 4 条、小测 Q2，'
        '并新增 `l12-guard-facts.py` 守护。'
        '**P0-2（监控指标名全部为旧版，会被直接复制进告警配置）** 初稿引用的 6 个 Prometheus 指标名'
        '（`rabbitmq_node_mem_used` / `rabbitmq_node_mem_limit` / `rabbitmq_node_disk_free` / '
        '`rabbitmq_node_disk_free_limit` 等）在 4.3.5 的 `:15692/metrics` 端点**均不存在**——'
        '实测抓取端点逐条核对，真实名为 `rabbitmq_process_resident_memory_bytes` / '
        '`rabbitmq_resident_memory_limit_bytes` / `rabbitmq_disk_space_available_bytes` / '
        '`rabbitmq_disk_space_available_limit_bytes`，另有告警专用的 '
        '`rabbitmq_alarms_memory_used_watermark` / `rabbitmq_alarms_free_disk_space_watermark`（直接是 0/1）。'
        '已替换并保留旧名作为"已废弃"反例教学。'
        '**P1-1（内存水位与本环境实测矛盾）** 初稿写「内存高水位默认 0.4」，'
        '但本环境 `rabbitmqctl environment` 实测为 **0.6**——0.4 是 3.x 的默认值，**4.x 起已改为 0.6**，'
        '网上大量教程仍写 0.4。已改为区分版本的写法并纳入守护项 G6。'
        '**P1-2（pika 特有坑，须显式交代）** 生成器式 `consume()` 是惰性的，'
        '必须 `next()` 预热让 `basic.consume` 帧真正发出，否则掉进"先发后注册"的 406。'
        '**P1-3（运维提醒缺失）** 补 per-object metrics 的开销警告'
        '（官方有 8 万队列 → 190 万指标 / 98 MB / 58 秒的实测记录），生产应保持默认关闭。'
        '另**修复一项跨课系统性缺陷**：自检发现课 2/3/4/5/6/12 的「返回课程目录」链接层级写错'
        '（应为 `../../../02-课程目录.md`，实际写成 `../../`），指向不存在的文件，已批量修复 8 处 | '
        '全部采纳：Direct Reply-To 由"未跑通"改为完整实测成功并配三组对照与最小骨架代码；'
        '监控指标名全部替换为端点实测名并保留旧名反例；内存水位区分 3.x/4.x；'
        '新增 `l12-guard-facts.py`（23 项断言全通过）与 `l12-selfcheck.py`（16 项全通过）；'
        '跨课链接批量修复。**阶段 4 收官 + 全课知识部分收官** |\n'
    ) % DATE
    arch, _ = replace_once(arch, anchor, anchor + row12, '评审记录：插入课 12')

    # ================= 3. 大纲调整记录 =================
    print("\n[3] 学习档案 · 大纲调整记录")
    anchor3 = ('| 日期 | 调整内容 | 原因 |\n|------|----------|------|\n')
    row3 = (
        '| %s | 阶段 4·课 12《架构落地与选型决策》三个知识点全部完成并落盘'
        '（约 1090 行 + 16 个脚本 + 6 道小测 + 23 项事实守护 + 16 项讲义自检）。'
        '三个知识点均已实测：三种消息拓扑（工作队列 12 条 7:3:2 能者多劳 / 发布订阅 3 队列各收完整 3 条 / '
        'RPC 两种回调方案各 4/4）；四个消息系统版本联网核查（RabbitMQ 4.3.5、Kafka 4.3、RocketMQ 5.5.0、Redis 8.8）；'
        '容量规划四组对照（1KB→456 条/秒，1MB→108 条/秒，消息大 1000 倍条/秒只掉 4.2 倍、带宽涨 242 倍）。'
        '**本轮最大升级**：补测完成初稿标注为"未跑通"的 Direct Reply-To 完整往返（4/4 成功），'
        '根因是官方文档中"消费与发布必须同信道"这条被漏看的约束；'
        '并实测出「跨信道 → 不报错但响应静默丢失」这一比 406 更危险的失败形态。'
        '另修复跨课系统性缺陷：6 个讲义的目录链接层级错误（8 处） | '
        '正常推进；**全课四个阶段知识部分已讲完**，'
        '下一步为 Phase 3 综合实战项目（跨阶段整合），'
        '之后为 Phase 5 实战经验与排障速查手册 |\n'
    ) % DATE
    arch, _ = replace_once(arch, anchor3, anchor3 + row3, '大纲调整记录：插入课 12')

    # ================= 4. 事实核查记录 =================
    print("\n[4] 学习档案 · 事实核查记录")
    anchor4 = ('> 起源、版本号等时效敏感内容，均在下述时点联网核查过；'
               '正文对应位置标注 `（核查于 2026-08）`。\n\n'
               '| 日期 | 核查内容 | 结论 | 来源 |\n|------|----------|------|------|\n')
    facts = [
        ('**Direct Reply-To 完整往返成功（P0，推翻初稿"未跑通"）**',
         '根因是漏看了官方文档的一条约束：RPC 客户端必须用**同一个连接和同一个信道**，'
         '既从 `amq.rabbitmq.reply-to` 消费、又发布请求消息。'
         '此前把发布与消费分到两个信道 → 响应收不到且**无任何报错**。'
         '修正为「单连接 + 单信道 + `next()` 预热注册消费者 + 再发布」后，'
         '实测 fib(5/10/15/20) **4/4 全部正确，耗时 0.01s**',
         '实测（l12-drt-server.py + l12-drt-client.py）+ 官方 Direct Reply-to 文档'),
        ('**跨信道 → 响应静默丢失（本课最值得警惕的失败形态）**',
         '三组对照，判据为"响应是否真的到达"而非"有没有报错"：'
         'A 跨信道（消费 A / 发布 B）→ **不报错，6 秒内响应未到达**；'
         'B 同信道但先发布后注册 → 异步 `406 PRECONDITION_FAILED - fast reply consumer does not exist`；'
         'C 同信道 + 先注册后发布 → **响应到达（=5）**。'
         'A 组的危险性在于：服务端照常消费、照常回复，broker 照常丢弃，全程静默，无异常可查',
         '实测（l12-drt-crosschannel2.py、l12-guard-facts.py G2）'),
        ('**pika 生成器式 consume() 是惰性的，必须 next() 预热**',
         '`channel.consume()` 返回生成器，只有第一次迭代（`next()`）时才真正发出 `basic.consume` 帧完成注册。'
         '写成"先 publish 再 consume"必然掉进 406。'
         '此为 pika 官方维护者 Luke Bakken 给出的写法，本环境实测验证有效',
         '实测（l12-drt-client.py）+ pika 社区 issue'),
        ('**4.3.5 的 Prometheus 端点不含旧指标名（P0）**',
         '实测抓取 `:15692/metrics` 逐条核对：'
         '`rabbitmq_node_mem_used` / `rabbitmq_node_mem_limit` / `rabbitmq_node_disk_free` / '
         '`rabbitmq_node_disk_free_limit` **全部不存在**。'
         '真实名为 `rabbitmq_process_resident_memory_bytes`、`rabbitmq_resident_memory_limit_bytes`、'
         '`rabbitmq_disk_space_available_bytes`、`rabbitmq_disk_space_available_limit_bytes`；'
         '另有告警专用 `rabbitmq_alarms_memory_used_watermark`、'
         '`rabbitmq_alarms_free_disk_space_watermark`（直接是 0/1）。'
         '队列类 `rabbitmq_queue_messages_ready` / `_unacked` / `_consumers` / `_messages` 均存在',
         '实测（l12-fetch-metrics.sh + l12-guard-facts.py G7，23 项全通过）'),
        ('**内存高水位：4.x 默认为 0.6，不是 3.x 的 0.4**',
         '本环境 `rabbitmqctl environment` 实测 `vm_memory_high_watermark, 0.6`。'
         '官方生产清单亦载明 4.x 默认 60%%（3.x 为 40%%），推荐调整区间 0.4~0.7。'
         '网上大量教程仍写 0.4，照抄会配错告警阈值',
         '实测（rabbitmqctl environment，守护项 G6）+ 官方 Production Checklist'),
        ('**Prometheus per-object metrics 的开销（运维提醒）**',
         '默认端点只暴露聚合指标；开 `prometheus.return_per_object_metrics = true` 才有按队列明细。'
         '官方记录：8 万队列时产生约 190 万条指标、98 MB 响应、耗时 58 秒。'
         '生产应保持默认关闭，仅在排查时临时打开',
         '官方文档 + 社区实测记录'),
        ('**三种消息拓扑的实测分野**',
         '工作队列：12 条任务分给 3 个速度不同的 worker，分配 7:3:2，'
         '**合计 12 条、无重复无丢失**（每条只被一个 worker 处理，快的拿得多）。'
         '发布订阅：fanout 广播到 3 个订阅队列，**各收到完整 3 条**（每条被处理 3 次）。'
         '`fanout` 实测忽略 routing_key（传空串照样三个队列全收）',
         '实测（l12-message-patterns.py）'),
        ('**容量规划：消息大 1000 倍，条/秒只掉 4.2 倍，带宽涨 242 倍**',
         '三节点集群 + quorum 队列 + publisher confirms + 单客户端：'
         '1KB → 456.1 条/秒 / 0.45 MB/s / 平均 2.19ms / P95 3.26ms；'
         '10KB → 402.6 / 3.93 / 2.48 / 3.48；'
         '100KB → 329.7 / 32.19 / 3.03 / 4.24；'
         '1MB → 107.7 / 107.70 / 9.28 / 13.42。'
         '**结论：瓶颈在每条消息的固定开销（Raft 三节点复制 + fsync + 网络往返），与消息大小基本无关**。'
         '推论：把大消息拆碎会多付 N 次固定开销，通常更慢；> 100KB 应走 claim-check。'
         '⚠️ 绝对值为单客户端 + 跨 docker 网络，不代表生产性能，价值在相对趋势',
         '实测（l12-capacity-bench.py）'),
        ('**四个消息系统的版本与特性（联网核查，核查于 2026-09）**',
         'RabbitMQ 4.3.5（4.3 系列 2026-04-23 发布，**社区支持 2026-11-30 结束**，商业支持至 2028-04-30）；'
         'Kafka 4.3（2026-05-20），4.0 起 **ZooKeeper 已移除、KRaft 为唯一模式**，4.2 起 KIP-932 Queues（Share Groups）GA；'
         'RocketMQ 5.5.0（2026-04-10），5.x 存算分离 + 无状态 Proxy，5.5 加 LiteTopic（AI 场景）；'
         'Redis 8.8（2026-06），Stream 自 Redis 5.0 引入，8.2 加 XACKDEL/XDELEX、8.6 加幂等生产 IDMP、8.8 加 XNACK。'
         '⚠️ 三者均未在本环境实测，性能对比为领域公认定性结论',
         '联网核查（各项目官方发布页 / 文档）'),
        ('**跨课系统性缺陷：目录链接层级错误（8 处，已修）**',
         '讲义位于 `stages/<阶段>/lessons/`，到项目根需三级 `../../../02-课程目录.md`，'
         '但课 2/3/4/5/6/12 写成了两级 `../../`，指向不存在的 `stages/02-课程目录.md`。'
         '课 7 写法正确未受影响。已批量修复，并在 `l12-selfcheck.py` 中加入 S5 链接有效性检查防止回归',
         '实测（l12-selfcheck.py S5、l12-fix-links.py）'),
    ]
    rows4 = ''
    for content, conclusion, source in facts:
        rows4 += '| %s | **%s** | %s | %s |\n' % (
            DATE, content, conclusion, source)
    arch, _ = replace_once(arch, anchor4, anchor4 + rows4,
                           '事实核查记录：插入 %d 条' % len(facts))

    write(ARCHIVE, arch)
    print("  💾 已写入 00-学习档案.md")

    # ================= 5. 评审清单 =================
    print("\n[5] 评审清单 · 勾选课 9/10/11/12")
    chk = read(CHECKLIST)
    checks = [
        ('- [ ] 阶段 4·课 9《Python 客户端工程实践》 — pedagogy + learner 双视角',
         '- [x] 阶段 4·课 9《Python 客户端工程实践》 — pedagogy + learner 双视角 — P0=0 通过（%s，漏评审补勾）' % DATE),
        ('- [ ] 阶段 4·课 10《高级特性》 — pedagogy + learner 双视角',
         '- [x] 阶段 4·课 10《高级特性》 — pedagogy + learner 双视角 — P0=0 通过（%s，漏评审补勾）' % DATE),
        ('- [ ] 阶段 4·课 11《集群与高可用》 — pedagogy + learner 双视角',
         '- [x] 阶段 4·课 11《集群与高可用》 — pedagogy + learner 双视角 — P0=0 通过（%s，漏评审补勾）' % DATE),
        ('- [ ] 阶段 4·课 12《架构落地与选型决策》 — pedagogy + learner 双视角',
         '- [x] 阶段 4·课 12《架构落地与选型决策》 — pedagogy + learner 双视角 — P0=2 已全部修正，P0=0 通过（%s，23 项守护 + 16 项自检全通过，阶段 4 收官 + 全课收官）' % DATE),
    ]
    for old, new in checks:
        chk, _ = replace_once(chk, old, new, '勾选：%s' % old[6:26])

    # 评审清单表格里也追加课 12 一行
    anchor5 = ('| 日期 | 评审对象 | 评审方式 | P0 数 | 意见摘要 |\n'
               '|------|----------|----------|-------|----------|\n')
    row5 = (
        '| %s | 阶段 4·课 12 | 主 agent 内联（pedagogy + learner） | 2 | '
        '**P0×2 全部已修**：①（实测推翻初稿）Direct Reply-To 初稿标注"未跑通"，'
        '实为漏看官方"同连接+同信道"约束，修正后 **4/4 往返成功**；'
        '并实测出「跨信道 → 不报错但响应静默丢失」这一比 406 更危险的失败形态。'
        '②（指标名会被引进生产配置）初稿 6 个 Prometheus 指标名在 4.3.5 端点**均不存在**，'
        '已逐个替换为实测名并保留旧名作反例。'
        'P1×3：内存水位 0.4→0.6（3.x/4.x 差异）；pika 生成器 `consume()` 惰性需 `next()` 预热；'
        '补 per-object metrics 开销警告。'
        '另修复**跨课系统性缺陷**：课 2/3/4/5/6/12 的目录链接层级错误 8 处。'
        '新增 `l12-guard-facts.py`（23 项）+ `l12-selfcheck.py`（16 项）均全通过。**阶段 4 收官 + 全课收官** |\n'
    ) % DATE
    chk, _ = replace_once(chk, anchor5, anchor5 + row5, '评审记录表：追加课 12')
    write(CHECKLIST, chk)
    print("  💾 已写入 00-评审清单.md")

    # ================= 6. 课程目录 =================
    print("\n[6] 课程目录 · 课 12 改为链接")
    cat = read(CATALOG)
    old12 = ('### 课 12：架构落地与选型决策（未编写）\n\n'
             '- 典型消息模式\n- 选型对比\n- 生产落地清单\n')
    new12 = ('### [课 12：架构落地与选型决策]'
             '(stages/4-进阶与工程落地/lessons/lesson-12-架构落地与选型决策.md)\n\n'
             '- 典型消息模式\n- 选型对比\n- 生产落地清单\n')
    cat, _ = replace_once(cat, old12, new12, '课 12 改为可点击链接')

    old4 = '## 阶段 4：进阶与工程落地\n'
    new4 = '## 阶段 4：进阶与工程落地 ✅ 已完成\n'
    cat, _ = replace_once(cat, old4, new4, '阶段 4 标记已完成')
    write(CATALOG, cat)
    print("  💾 已写入 02-课程目录.md")

    print("\n" + "=" * 72)
    print("✅ 收尾更新完成")
    print("=" * 72)
    return 0


if __name__ == '__main__':
    sys.exit(main())
