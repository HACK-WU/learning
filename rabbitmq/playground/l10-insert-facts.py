#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""向学习档案追加课 10 的事实核查记录与大纲调整记录。"""
import os

ARCHIVE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '..', '00-学习档案.md')

FACTS = [
    ('2026-09-01',
     '**nack 与 reject 在 4.3 不再等价：延迟退避只看 delivery-count（P0）**',
     '4.3 起 quorum 队列区分 acquired-count（每次 requeue 都涨）与 delivery-count'
     '（仅投递失败才涨），延迟公式 min(min_delay × delivery_count, max_delay) 与'
     ' delivery-limit **都只看 delivery-count**。实测对照（min=3000ms/max=12000ms，'
     '连续返回同一条消息、不 ack 不重发）：reject 组 3.06→6.11→9.15→12.01→12.20s '
     '线性递增并在 12s 封顶，与官方公式吻合；nack 组恒为 3.04~3.06s 永不递增；'
     '两组 x-acquired-count 均增长（1→5）。结论：acquired-count 不参与延迟计算，'
     'nack 语义为"取过但没失败"，故延迟恒为最小值',
     '实测（l10-backoff-final.py），RabbitMQ 4.3.5 / pika 1.4.4'),

    ('2026-09-01',
     '**quorum 队列不接受 x-max-priority（P0，纠正常见迁移错误）**',
     '实测给 quorum 队列传 x-max-priority（取值 1/2/3/5/8/10/16/31/32/33/64/255）'
     '**全部被拒**，报 PRECONDITION_FAILED - invalid arg \'x-max-priority\' for queue '
     '... of queue type rabbit_quorum_queue（首个失败后会关闭 channel）。'
     '官方原文："Priorities Are Always Enabled. Quorum queues always provide the full '
     '0-31 priority range. There is no opt-in argument: x-max-priority applies only to '
     'classic queues and is ignored by quorum queues."',
     '实测 + 官方文档 Quorum Queues / Priority Support in Queues'),

    ('2026-09-01',
     '**classic 的 x-max-priority 边界：0~255 接受，256 被拒**',
     '实测 classic 队列声明 x-max-priority=0/1/10/255 均接受，256 被拒'
     '（PRECONDITION_FAILED - invalid arg \'x-max-priority\'）',
     '实测（l10-priority-fixed.py）'),

    ('2026-09-01',
     '**quorum 32 级严格优先级：严格降序且超出钳制**',
     'quorum 队列不传任何参数即可用优先级。实测乱序发布 12 条（优先级 0-11），'
     '消费顺序为 [11,10,9,8,7,6,5,4,3,2,1,0] 严格降序。'
     'priority=100 与 priority=5 同队列时，100 先出（被钳制到 31）',
     '实测（l10-priority-fixed.py 场景 B/C）'),

    ('2026-09-01',
     '**未设 priority 时的默认值：quorum=4，classic=0（不同！）**',
     '实测同发三条（无优先级 / priority=2 / priority=8）：'
     'quorum 消费顺序 [P8, NO_PRIORITY, P2]（无优先级消息居中，符合默认 4）；'
     'classic 消费顺序 [P8, P2, NO_PRIORITY]（无优先级消息垫底，符合默认 0）',
     '实测（l10-priority-fixed.py 场景 D）'),

    ('2026-09-01',
     '**优先级只在有积压时生效，消费者空闲时完全无效**',
     '实测无积压场景（发一条立刻取一条）：发布优先级 [1,9,2,8,3] → 取出 [1,9,2,8,3]，'
     '与发布顺序完全一致，优先级不起作用。有积压场景（先堆 12 条再消费）：'
     '严格按优先级降序',
     '实测（l10-priority-fixed.py 场景 E）'),

    ('2026-09-01',
     '**TTL+DLX 的顺序陷阱：per-message TTL 只对队首生效**',
     '实测先发 TTL=20s、0.5s 后再发 TTL=3s：后者实际 20.06s 才到达业务队列，'
     '被队首的长 TTL 消息堵住。单条消息场景则准确（TTL=5000ms → 5.14s）',
     '实测（l10-delay-ttl-dlx.py）'),

    ('2026-09-01',
     '**x-delayed-retry-type 写错值不报错（静默失效）**',
     '实测 disabled/all/failed/returned/bogus_value 五个取值全部被接受，'
     'bogus_value 无任何报错但延迟重试静默失效',
     '实测（l10-delayed-retry.py 场景 A）'),

    ('2026-09-01',
     '**延迟消息插件：本环境未安装**',
     '实测 rabbitmq-plugins list（完整列表约 50 项）中**不存在** '
     'rabbitmq_delayed_message_exchange，故插件方案未能实测。'
     '已启用插件仅 management / management_agent / prometheus / stream / '
     'stream_management / web_dispatch',
     '实测（rabbitmq-plugins list）'),

    ('2026-09-01',
     '**流控：告警可触发但 publish 未被阻塞（与常见说法不符）**',
     '用 rabbitmqctl set_vm_memory_high_watermark 0.000001 安全触发内存告警'
     '（避免压满用户内存），确认 "Memory alarm on node" 生效，且客户端收到成对的 '
     'BLOCKED/UNBLOCKED 事件。但告警期间的那次 publish **0.00s 立即返回、未被挂起**。'
     '"告警后 publish 必被阻塞"在本环境未获证实，已如实标注',
     '实测（l10-flow-blocked.py）'),

    ('2026-09-01',
     '**blocked 回调属于 Connection 而非 Channel（pika 1.4.4）**',
     '实测 BlockingChannel 无 add_on_connection_blocked_callback 属性'
     '（AttributeError），正确用法是 conn.add_on_connection_blocked_callback()。'
     '且 blocked/unblocked 帧需 process_data_events() 驱动才被处理——实测两事件的'
     '相对时间均为 0.0，即在同一轮 pump 时才被读到',
     '实测（l10-flow-control.py / l10-flow-blocked.py）'),

    ('2026-09-01',
     '**本环境流控基线配置**',
     'vm_memory_high_watermark = 0.6（60% 可用内存，实测换算为 20.0189 gb）；'
     'disk_free_limit = 50000000（50 MB，UI 显示 0.05 gb）；'
     '当前可用磁盘 908.2 gb。实验后已确认恢复：Alarms (none)、水位回到 0.6',
     '实测（rabbitmqctl environment / status）'),

    ('2026-09-01',
     '**方法学教训：延迟退避测量经历三次失败才测准**',
     '① ack + 重发 → 变成新消息、计数归零，测不到退避；'
     '② 等待窗口不足 → 误报"消息消失"（l10-trace-message.py 用 HTTP API 证明'
     'total 恒为 1，消息从未消失）；'
     '③ 以 HTTP API 的 messages_ready 0→1 为信号 → nack 后 requeue 瞬时完成、'
     'ready 立刻回到 1，测到的是 0.21s 的 requeue 耗时而非延迟。'
     '最终以 basic_get 能否取到消息为信号才测准（延迟期间 basic_get 返回 None）',
     '实测（l10-retry-multiroound.py / l10-retry-strict.py / l10-backoff-measure.py '
     '/ l10-trace-message.py / l10-backoff-final.py）'),
]

OUTLINE = (
    '| 2026-09-01 | 阶段 4·课 10《高级特性》三个知识点全部完成并落盘'
    '（800 行 + 12 个实验脚本 + 6 道小测）；讲义含延迟消息 TTL+DLX 顺序陷阱实测、'
    '4.3 原生延迟重试的 nack/reject 对照、quorum 32 级优先级、流控安全触发方法。'
    '两项验证如实标注未完成：延迟消息插件（环境未安装）、流控阻塞未复现 '
    '| 正常推进；下一课为课 11《集群与高可用》 |'
)


def main():
    with open(ARCHIVE, encoding='utf-8') as f:
        text = f.read()

    # 1. 事实核查记录：在表头后插入
    fact_header = '| 日期 | 核查内容 | 结论 | 来源 |\n|------|----------|------|------|'
    if fact_header in text:
        if 'nack 与 reject 在 4.3 不再等价' not in text:
            rows = ''.join(
                '| %s | %s | %s | %s |\n' % (d, t, c, s)
                for d, t, c, s in FACTS)
            text = text.replace(fact_header, fact_header + '\n' + rows.rstrip('\n'), 1)
            print("已插入 %d 条事实核查记录" % len(FACTS))
        else:
            print("事实核查记录已存在，跳过")
    else:
        print("未找到事实核查表头")

    # 2. 大纲调整记录
    outline_header = '| 日期 | 调整内容 | 原因 |\n|------|----------|------|'
    if outline_header in text:
        if '课 10《高级特性》三个知识点全部完成' not in text:
            text = text.replace(outline_header,
                                outline_header + '\n' + OUTLINE, 1)
            print("已插入大纲调整记录")
        else:
            print("大纲调整记录已存在，跳过")
    else:
        print("未找到大纲调整表头")

    with open(ARCHIVE, 'w', encoding='utf-8') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
