#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
补齐课 10、课 11 的评审记录。

原因追溯：
  l10-insert-review.py 与 l11-insert-archive.py 都用
  "《XXX》" 之类的子串做重复判断，而这些子串在**别的记录行**里也会出现
  （例如课 10 记录里写了"下一课为课 11《集群与高可用》"），
  导致误判为"已存在"而跳过插入。

实际情况：评审记录表（以 | 2026-09-01 | 阶段 4·课 9... | 开头的行为顶行）
中，课 10 与课 11 的记录都缺失。

本脚本改用【精确行首锚点】判断，并在课 9 行之前一次性插入课 11、课 10 两行
（保持倒序：新的在上）。
"""
import os

ARCHIVE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', '00-学习档案.md')

# 评审记录表的顶行（课 9）
MARK = '| 2026-09-01 | 阶段 4·课 9《Python 客户端工程实践》 | 主 agent 内联'

ROW11 = '| 2026-09-01 | 阶段 4·课 11《集群与高可用》 | 主 agent 内联（pedagogy + learner） | '
ROW10 = '| 2026-09-01 | 阶段 4·课 10《高级特性》 | 主 agent 内联（pedagogy + learner） | '

BODY11 = (
    'P0×3 已修、P1×2 已修：'
    '**P0-1（搭建真实三节点集群，本课从"讲概念"升级为"可实测"）** '
    '新建独立 docker 网络 rabbitmq-cluster 与三个 4.3.5 节点（rmq1/rmq2/rmq3，'
    'AMQP 5681-5683、UI 15681-15683），与既有 rabbitmq-learn 完全隔离、零干扰。'
    '**P0-2（实测 leader 故障切换）** 停掉 leader 后 **0.07s** 选出新 leader，'
    '20 条已确认消息**一条不少**，故障期间仍可继续写入；对照组 classic 队列宿主宕机后'
    '**完全不可用**（NOT_FOUND - process is stopped by supervisor）。'
    '**P0-3（实测多数派语义）** 停 1 个可写、停 2 个报 NackError、恢复 1 个自动恢复，'
    '失败形态是 **NACK 而非异常**——未开 confirm 则完全感知不到（呼应课 6）。'
    '**P1-1（实测纠正 Federation 认知）** Federation 下游去上游找**同名队列**拉取；'
    '初版两端异名导致链路 running 却拉到 0 条，**状态正常 ≠ 数据到达**。'
    '**P1-2（实测确认 4.x 移除项）** ha-mode 策略被拒（Validation failed，镜像队列 4.0 移除）；'
    'help 中无 change_cluster_node_type（ram 节点 4.3 移除）；'
    'environment 中无 cluster_partition_handling（旧分区策略已移除）。'
    '另如实标注三项**未完成验证**：Shovel/Federation 跨站点场景（上游容器两次搭建失败）、'
    'stream 高可用未单独实测、quorum_status 命令在 4.3.5 已不存在 '
    '| 全部采纳：leader 切换与多数派均配实测数据表；Federation 同名陷阱设为误区表第 5 条 + 小测 Q5；'
    '4.x 移除项逐条引实测证据；未完成验证写入讲义末尾不编造 |\n'
)

BODY10 = (
    'P0×2 已修、P1×2 已修：'
    '**P0-1（实测纠正课 6/课 9 的旧假设）** 4.3 起 `nack` 与 `reject` **不再等价**：'
    'quorum 队列区分 `acquired-count`（每次 requeue 都涨）与 `delivery-count`'
    '（仅投递失败才涨），而延迟退避与 `delivery-limit` **只看 delivery-count**。'
    '实测对照（min=3s/max=12s）：`reject` 组 3.06→6.11→9.15→12.01s 线性递增并封顶，'
    '与官方公式 min(min×delivery_count, max) 吻合；`nack` 组恒定 3.05s 永不递增；'
    '两组 `x-acquired-count` 均增长（1→5）——证明 acquired-count 不参与延迟计算。'
    '**P0-2（实测纠正常见迁移错误）** quorum 队列**不接受** `x-max-priority`'
    '（实测 1/2/3/5/8/10/16/31/32/33/64/255 全部被拒，报 PRECONDITION_FAILED），'
    '官方原文为其默认启用 32 级（0-31）、该参数"applies only to classic queues and is '
    'ignored by quorum queues"。'
    '**P1-1（实测发现）** `x-delayed-retry-type` 写错枚举值（bogus_value）**不报错**、静默失效。'
    '**P1-2（实测纠正初判）** 流控告警确实触发（Memory alarm on node）且客户端收到成对 '
    'BLOCKED/UNBLOCKED，但告警期间的 publish **未被挂起**（0.00s 返回），'
    '"告警后 publish 必被阻塞"**未获证实**，已如实标注。'
    '另如实记录两项**未完成验证**：延迟消息插件（本环境未安装）、流控阻塞未复现 '
    '| 全部采纳：nack/reject 语义差异成节并配 5 轮对照数据；quorum 优先级配置差异引官方原文；'
    '参数静默失效与流控未复现均如实标注未编造 |\n'
)


def main():
    with open(ARCHIVE, encoding='utf-8') as f:
        lines = f.readlines()

    # 精确判断：按行首锚点
    has10 = any(ln.startswith(ROW10) for ln in lines)
    has11 = any(ln.startswith(ROW11) for ln in lines)
    print("课 10 评审记录：%s" % ("已存在" if has10 else "缺失，需插入"))
    print("课 11 评审记录：%s" % ("已存在" if has11 else "缺失，需插入"))

    to_insert = []
    if not has11:
        to_insert.append(ROW11 + BODY11)
    if not has10:
        to_insert.append(ROW10 + BODY10)

    if not to_insert:
        print("无需插入")
        return 0

    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith(MARK):
            idx = i
            break
    if idx is None:
        print("未找到课 9 锚点行")
        return 1

    # 倒序插入，保证最终顺序为 课11、课10、课9
    for row in to_insert:
        lines.insert(idx, row)

    with open(ARCHIVE, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("已在第 %d 行前插入 %d 条评审记录" % (idx + 1, len(to_insert)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
