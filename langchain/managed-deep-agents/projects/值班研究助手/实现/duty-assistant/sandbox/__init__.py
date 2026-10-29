"""沙箱声明。

为什么这个项目需要沙箱：值班人要 agent 帮他跑诊断命令（看日志尾部、算错误率），
这些必须在隔离环境里跑，不能在宿主上直连。

代价（课 6 实测结论，必须知道）：
  声明 sandbox 之后，agent.py 里的 permissions 会被静默清空 ——
  源码 runtime.py 里 `if sandbox_backend is not None: merged["permissions"] = []`，
  没有任何警告。所以本项目的文件访问限制不靠 permissions，靠"只给这三个工具"。
"""

from managed_deepagents import define_sandbox

sandbox = define_sandbox(
    idle_ttl_seconds=900,   # 15 分钟没人用就回收，里面的临时文件不可恢复
    default_timeout=120,    # 单条诊断命令最多跑 2 分钟
    docker_image="python:3.12-slim",
)
