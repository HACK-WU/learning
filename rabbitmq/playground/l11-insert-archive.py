#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""向学习档案追加课 11 的评审记录、事实核查记录与大纲调整记录。"""
import os

ARCHIVE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', '00-学习档案.md')

MARK = '| 2026-09-01 | 阶段 4·课 10《高级特性》'

REVIEW = (
    '| 2026-09-01 | 阶段 4·课 11《集群与高可用》 | 主 agent 内联（pedagogy + learner） | '
    'P0×3 已修、P1×2 已修：**P0-1（搭建真实三节点集群，使本课从"讲概念"升级为"可实测"）** '
    '新建独立 docker 网络 rabbitmq-cluster 与三个 4.3.5 节点（rmq1/rmq2/rmq3，'
    'AMQP 5681-5683、UI 15681-15683），与既有 rabbitmq-learn 完全隔离、零干扰。'
    '**P0-2（实测 leader 故障切换，数据零丢失）** 停掉 leader 节点后 **0.07s** '
    '选出新 leader，20 条已确认消息**一条不少**，故障期间仍可继续写入；'
    '对照组 classic 队列宿主宕机后**完全不可用**（'
    'NOT_FOUND - process is stopped by supervisor）。'
    '**P0-3（实测多数派语义）** 停 1 个可写、停 2 个报 NackError、恢复 1 个自动恢复，'
    '且失败形态是 **NACK 而非异常**——未开 confirm 则完全感知不到（呼应课 6）。'
    '**P1-1（实测纠正 Federation 认知）** Federation 下游去上游找**同名队列**拉取；'
    '初版两端异名导致链路 running 却拉到 0 条，**状态正常 ≠ 数据到达**。'
    '**P1-2（实测确认 4.x 移除项）** `ha-mode` 策略被拒（Validation failed，镜像队列 4.0 移除）；'
    'rabbitmqctl help 中无 change_cluster_node_type（ram 节点 4.3 移除）；'
    'environment 中无 cluster_partition_handling（旧分区策略已移除）。'
    '另如实标注三项**未完成验证**：Shovel/Federation 跨站点场景（上游容器两次搭建失败）、'
    'stream 高可用未单独实测、rabbitmqctl quorum_status 在 4.3.5 已不存在 '
    '| 全部采纳：leader 切换与多数派均配实测数据表；Federation 同名陷阱设为误区表第 5 条 + 小测 Q5；'
    '4.x 移除项逐条引实测证据；未完成验证写入讲义末尾不编造 |'
)

FACTS = [
    ('2026-09-01',
     '**三节点集群搭建成功（本课从概念讲解升级为可实测）**',
     '新建独立 docker 网络 rabbitmq-cluster，三个节点 rmq1/rmq2/rmq3 全为 '
     'RabbitMQ 4.3.5 on Erlang 27.3.4.16，全为 disc 节点，共享 cookie。'
     '端口 AMQP 5681/5682/5683、UI 15681/15682/15683，与既有 rabbitmq-learn 完全隔离',
     '实测（l11-cluster-setup.sh + cluster_status）'),

    ('2026-09-01',
     '**leader 故障切换：0.07s 完成选举，已确认消息零丢失（P0）**',
     'quorum 队列（3 副本，leader 在 rmq1），发布 20 条经 confirm 确认的持久化消息后 '
     'docker stop rmq1。实测：新 leader = rabbit@rmq3，选举耗时 **0.07 秒**；'
     '通过 rmq2 查询队列深度 = 20，实际消费到 20 条（msg-000 ~ msg-019 完整）；'
     '故障期间继续写入 5 条成功。恢复 rmq1 后副本自动同步，'
     '但 leader **未**切回 rmq1（Raft 不做无谓的二次选举）',
     '实测（l11-failover.py）'),

    ('2026-09-01',
     '**classic 队列宿主宕机后完全不可用（对照组）**',
     'classic 队列（durable=True，宿主 rmq1）发布 20 条后停掉 rmq1，'
     '两个存活节点均报：NOT_FOUND - queue \'l11.failover.classic\' in vhost \'/\' '
     'process is stopped by supervisor。消息虽持久化在 rmq1 磁盘上，但无其他副本，'
     '4.0 移除镜像队列后 classic 即单点',
     '实测（l11-failover.py）'),

    ('2026-09-01',
     '**多数派语义：停 1 可写、停 2 NACK、恢复 1 自动恢复（P0）**',
     '三节点多数派 = 2。实测：停 rmq3（剩 2）→ rmq1/rmq2 均 ✅ 可写；'
     '再停 rmq2（剩 1）→ rmq1 报 **NackError: 0 message(s) NACKed**；'
     '恢复 rmq2（剩 2）→ 自动恢复可写；全恢复后三节点均可写。'
     '关键：失败形态是 **NACK 而非断连/异常**，不开 publisher confirms 则感知不到',
     '实测（l11-majority.py）'),

    ('2026-09-01',
     '**Shovel 是 move 语义：源端被消费掉**',
     'rmq1 源队列发 5 条，配置 Shovel 搬到 rmq2。实测结果：源队列 l11.shovel.src 深度 '
     '**0**，目标 l11.shovel.dst 深度 **5**。取回内容 payload-000~004 一致，'
     'shovel_status 显示 state=running',
     '实测（l11-shovel.py）'),

    ('2026-09-01',
     '**Federation 是 copy 语义：上游保留副本**',
     '同名队列 l11.fed.queue，上游 rmq1 发 5 条。实测：上游深度 **5**、下游深度 **5**，'
     '两边都在 → copy 语义确认，与 Shovel 的 move 形成清晰对照。'
     'federation_status 显示 status=running、consumer_tag=federation-link-rmq1-up',
     '实测（l11-federation.py）'),

    ('2026-09-01',
     '**Federation 陷阱：两端队列必须同名（P1，实测踩坑）**',
     '初版用 l11.fed.up（上游）与 l11.fed.down（下游）异名，链路 status=running 但下游拉到 0 条。'
     'federation_status 显示 upstream_queue = <<"l11.fed.down">>，'
     '即它去上游找**下游同名**的队列。改为同名后立刻正常。'
     '教训：状态正常 ≠ 数据到达',
     '实测（l11-federation.py）'),

    ('2026-09-01',
     '**quorum 副本分布与请求转发**',
     'quorum 队列 leader=rabbit@rmq1，members=[rmq1,rmq2,rmq3] 三副本。'
     '连非 leader 节点 rmq2 发布并取回消息成功（via-rmq2），'
     '证明非 leader 节点会把请求转发给 leader。'
     'x-quorum-initial-group-size=1 时 members=1（无高可用），=3 时 members=3',
     '实测（l11-quorum-replication.py）'),

    ('2026-09-01',
     '**classic 队列的宿主判断：看 node 字段，不是看能否查到**',
     '集群中**所有节点都能看到队列元数据**（list_queues 在 rmq1/rmq2/rmq3 上都能查到），'
     '但数据只在 node 字段标识的节点上。实测 classic 队列 node=rabbit@rmq1、'
     'members 为空。我初版就是用"每个节点都能查到"误判为"已复制到所有节点"',
     '实测（l11-quorum-replication.py 场景 C，含我自己的误判修正）'),

    ('2026-09-01',
     '**4.3.5 已移除 rabbitmqctl quorum_status**',
     '执行报 Command \'quorum_status\' not found。改用 Management API 的 '
     'leader / members / online / node / type 字段读取副本信息',
     '实测（rabbitmqctl quorum_status）'),

    ('2026-09-01',
     '**镜像队列已移除：ha-mode 策略被拒**',
     '执行 set_policy ha-mode=all 返回 **Validation failed**，'
     '镜像队列（classic mirrored queues）在 4.0 起已移除',
     '实测（l11-khepri-check.py 场景 C）'),

    ('2026-09-01',
     '**ram 节点类型已移除 / 节点重命名已废弃**',
     'rabbitmqctl help 中**无** change_cluster_node_type（ram 节点 4.3 移除）；'
     'cluster_status 只有 Disk Nodes 一栏、无 RAM Nodes。'
     '另 help 原文标注：rename_cluster_node 已 DEPRECATED 且为 no-op，'
     '"Node renaming is incompatible with Raft-based features such as '
     'quorum queues, streams, Khepri"',
     '实测（rabbitmqctl help / cluster_status）'),

    ('2026-09-01',
     '**4.3 元数据后端为 Khepri，旧分区策略已移除**',
     'environment 输出含 {khepri, ...} 与 metadata_store 字段，确认为 Khepri（Raft）。'
     'environment 中**不存在** cluster_partition_handling，'
     '即 pause_minority / autoheal / ignore 三选一已随 Mnesia 移除。'
     '⚠️ 注意：扫描时匹配到 {prevent_overlapping_partitions,false}，'
     '但它是**不同**的配置项（控制是否阻止重叠分区），'
     '不作为"旧策略仍存在"的证据，已如实说明',
     '实测（l11-khepri-check.py 场景 A/B）'),

    ('2026-09-01',
     '**Erlang cookie 不同则无法组集群（本课两种环境的实测对照）**',
     '集群节点 rmq1 的 cookie 为 JGXNRXISCQUV...，既有容器 rabbitmq-learn 为 '
     'BXUAQVRDYRNC...，两者不同 → 无法加入同一集群。这正是 Federation/Shovel '
     '（松耦合、靠 AMQP URI 连接、不需共享 cookie）存在的理由',
     '实测（cat /var/lib/rabbitmq/.erlang.cookie）'),

    ('2026-09-01',
     '**上游站点容器两次搭建失败（未完成验证，如实记录）**',
     '想用独立上游容器演示跨站点 Shovel/Federation：'
     '① 既有容器 rabbitmq-learn 在**不同的 docker 网络**，集群容器访问不到'
     '（host.docker.internal 无法解析、网关 IP 不可达）；'
     '② 新建独立上游容器 rmq-upstream 遭遇宿主文件权限问题：'
     'Error when reading /var/lib/rabbitmq/.erlang.cookie: eacces，'
     '去掉 RABBITMQ_ERLANG_COOKIE 改用随机 cookie 仍失败，容器内无 python3/ip 可供诊断。'
     '两次失败后改为在**集群内部**两节点间演示，机制语义已实测确认，'
     '但跨信任边界场景未实测',
     '实测（l11-upstream-setup.sh / l11-netcheck.py，均已失败）'),

    ('2026-09-01',
     '**方法学教训：集群实验的三处取数与判定错误**',
     '① 用 list_queues 判断"哪个节点有队列"→ 错，集群中元数据全局可见，'
     '必须看 node 字段；'
     '② 用 rabbitmqctl quorum_status → 4.3.5 已移除该命令；'
     '③ Federation 两端异名 → 链路 running 但拉空。'
     '三处均通过实测暴露并修正，未依赖文档推断',
     '实测（l11-quorum-replication.py / l11-federation.py）'),
]

OUTLINE = (
    '| 2026-09-01 | 阶段 4·课 11《集群与高可用》三个知识点全部完成并落盘'
    '（894 行 + 8 个脚本 + 6 道小测）。本课**新建真实三节点集群**（rmq1/rmq2/rmq3，'
    '4.3.5，独立网络与端口段，与既有环境零干扰），使 leader 故障切换与多数派语义'
    '从"讲概念"变为"可实测"：实测 leader 宕机后 0.07s 完成选举、20 条已确认消息零丢失；'
    '多数派验证停 1 可写 / 停 2 NACK / 恢复自动恢复。另实测 Shovel=move、'
    'Federation=copy 的语义差异与同名队列陷阱。三项验证如实标注未完成：'
    'Shovel/Federation 跨站点场景、stream 高可用、quorum_status 命令已不存在 '
    '| 正常推进；下一课为课 12《架构落地与选型决策》（阶段 4 收官 + 全课收官） |'
)


def main():
    with open(ARCHIVE, encoding='utf-8') as f:
        text = f.read()

    # 1. 评审记录
    if MARK in text:
        if '课 11《集群与高可用》' not in text:
            text = text.replace(MARK, REVIEW + '\n' + MARK, 1)
            print("已插入评审记录")
        else:
            print("评审记录已存在，跳过")
    else:
        print("未找到评审表锚点")

    # 2. 事实核查
    fh = '| 日期 | 核查内容 | 结论 | 来源 |\n|------|----------|------|------|'
    if fh in text and 'leader 故障切换：0.07s 完成选举' not in text:
        rows = ''.join('| %s | %s | %s | %s |\n' % (d, t, c, s)
                       for d, t, c, s in FACTS)
        text = text.replace(fh, fh + '\n' + rows.rstrip('\n'), 1)
        print("已插入 %d 条事实核查记录" % len(FACTS))
    else:
        print("事实核查已存在或表头缺失")

    # 3. 大纲调整
    oh = '| 日期 | 调整内容 | 原因 |\n|------|----------|------|'
    if oh in text and '课 11《集群与高可用》三个知识点全部完成' not in text:
        text = text.replace(oh, oh + '\n' + OUTLINE, 1)
        print("已插入大纲调整记录")
    else:
        print("大纲调整已存在或表头缺失")

    with open(ARCHIVE, 'w', encoding='utf-8') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
