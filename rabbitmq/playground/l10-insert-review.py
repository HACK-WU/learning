#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""向学习档案的评审记录表顶部插入课 10 的记录行（避免超长行匹配问题）。"""
import os

ARCHIVE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', '00-学习档案.md')

MARK = '| 2026-09-01 | 阶段 4·课 9《Python 客户端工程实践》'

ROW = (
    '| 2026-09-01 | 阶段 4·课 10《高级特性》 | 主 agent 内联（pedagogy + learner） | '
    'P0×2 已修、P1×2 已修：'
    '**P0-1（实测纠正课 6/课 9 的旧假设）** 4.3 起 `nack` 与 `reject` **不再等价**：'
    'quorum 队列区分 `acquired-count`（每次 requeue 都涨）与 `delivery-count`'
    '（仅投递失败才涨），而延迟退避与 `delivery-limit` **只看 delivery-count**。'
    '实测对照（min=3s/max=12s）：`reject` 组延迟 3.06→6.11→9.15→12.01s 线性递增并封顶，'
    '与官方公式 min(min×delivery_count, max) 吻合；`nack` 组恒定 3.05s 永不递增；'
    '两组 `x-acquired-count` 均增长（1→5）——证明 acquired-count 不参与延迟计算。'
    '已设独立小节 + 速查卡 + 误区表第 3 条 + 小测 Q2/Q5。'
    '**P0-2（实测纠正常见迁移错误）** quorum 队列**不接受** `x-max-priority`'
    '（实测 1/2/3/5/8/10/16/31/32/33/64/255 全部被拒，报 PRECONDITION_FAILED），'
    '官方原文为其默认启用 32 级（0-31）、该参数"applies only to classic queues and is '
    'ignored by quorum queues"。已在讲义引官方原文并设误区表第 7 条 + 小测 Q3。'
    '**P1-1（实测发现）** `x-delayed-retry-type` 写错枚举值（bogus_value）**不报错**、静默失效。'
    '**P1-2（实测纠正初判）** 流控告警确实触发（Memory alarm on node）且客户端收到成对 '
    'BLOCKED/UNBLOCKED，但告警期间的 publish **未被挂起**（0.00s 返回），'
    '"告警后 publish 必被阻塞"**未获证实**，已如实标注并写入误区表第 10 条与 Q6。'
    '另如实记录两项**未完成验证**：延迟消息插件（本环境未安装）、流控阻塞未复现 '
    '| 全部采纳：nack/reject 语义差异成节并配 5 轮对照数据；quorum 优先级配置差异引官方原文；'
    '参数静默失效与流控未复现均如实标注未编造 |\n'
)


def main():
    with open(ARCHIVE, encoding='utf-8') as f:
        lines = f.readlines()

    idx = None
    for i, ln in enumerate(lines):
        if ln.startswith(MARK):
            idx = i
            break
    if idx is None:
        print("未找到锚点行")
        return 1

    # 避免重复插入
    if any('课 10《高级特性》' in ln for ln in lines):
        print("课 10 记录已存在，跳过")
        return 0

    lines.insert(idx, ROW)
    with open(ARCHIVE, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("已在第 %d 行前插入课 10 评审记录" % (idx + 1))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
