"""记忆声明：两层都开。

agent 层（/memories/agent/）：全团队共用的值班约定，比如"每周三凌晨是例行发布窗口"
user 层（/memories/user/）：某个值班人的个人偏好，比如"给我看表格不要看段落"

注意（课 6 实测）：Python 侧是 MemoryLayer() 类，TS 侧是 memoryLayer() 工厂函数。
"""

from managed_deepagents import MemoryLayer, define_memory

memory = define_memory(
    agent=MemoryLayer(),
    user=MemoryLayer(),
)
