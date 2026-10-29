"""值班研究助手 —— 入口文件。

这个文件只做一件事：把散落在各目录里的声明拼成一张"发货单"。
真正的内容（提示词、技能、记忆、沙箱、调度、通道）都在同目录的其它文件里。

静态入口约束（本教程课 3、课 7 实测结论）：
  - name 必须是字面量字符串，静态扫描认不出变量
  - 这里不要写 checkpointer / store / backend / state_schema，运行时会拒
  - 声明了 sandbox/ 之后，permissions 会被静默清空，所以这里刻意不写 permissions
"""

from managed_deepagents import define_deep_agent

from tools.duty import DutyContext, escalate_incident, query_open_alerts, read_oncall_roster

agent = define_deep_agent(
    name="duty-assistant",
    model="openai:gpt-5.5",
    tools=[read_oncall_roster, query_open_alerts, escalate_incident],
    context_schema=DutyContext,
)
