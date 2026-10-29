"""每日值班晨报 —— 部署时声明（写死在挂历上）。

设计取舍（课 8）：这里刻意不写 new_thread=True。
  默认就是每次跑开新话题、跑完即删 —— 晨报是"一次性快照"，
  昨天的晨报没有任何后续价值，留着只会污染线程列表。
  反过来，如果要它接着上次聊，就必须显式 new_thread=False 并配持久线程。

时区必须显式写。cron 里写 "0 8 * * *" 而 timezone 省略时，
用的是平台默认时区 —— 团队在上海却按 UTC 跑，晨报会变成下午 4 点。
"""

from managed_deepagents import define_schedule

schedule = define_schedule(
    cron="0 8 * * 1-5",              # 工作日早八点
    timezone="Asia/Shanghai",        # 显式写，不吃平台默认
    prompt=(
        "生成今天的值班晨报：先确认各团队谁在值班，再列出当前未恢复告警，"
        "按 P1 → P2 排序。只写查到的内容，没查到就说没查到。"
    ),
)
