"""回写 overview.md：
1. 学习进度勾选课 9 番外
2. 环境基线补异步包实测结论（ApplyResult / loop 绑定）
3. 清理 .bak 备份
"""
import io
import os
import shutil

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

PROGRESS_OLD = "- [x] 课 9：异步客户端与并发\n"
PROGRESS_NEW = (
    "- [x] 课 9：异步客户端与并发\n"
    "- [x] 课 9 番外：异步三个未实测项（写共享 · 429 · 重试风暴）\n"
)

ENV_OLD = (
    "| ⚠️ 实测发现 | PyPI 装到的 `kubernetes` **没有 `kubernetes.aio` 子模块**"
    "（官方 sdist 中 `aio` 文件数 = 0）→ README 的 async 示例**对 pip 用户不可用**，"
    "课 9 必须讲清这一点 |"
)
ENV_NEW = ENV_OLD + (
    "\n| ⚠️ 异步包硬约束（课 9 番外 2026-09-29 实测） | "
    "① 异步 API 方法是**普通 `def`**，靠内层 `ApiClient.__call_api` 是 `async def` "
    "成为可等待；判断要不要 await 看**调用后返回值**是否 `isawaitable`，"
    "不可用 `iscoroutinefunction` 看类属性。② 🚨 **`async_req=True` 在异步包里返回 "
    "`multiprocessing.pool.ApplyResult`，不能 `await`**（协程被丢进线程池永不执行）"
    "——异步并发一律用 `asyncio.gather`。③ 🚨 **`ApiClient` 必须在 running loop 内实例化**"
    "（loop 外 `RuntimeError: no running event loop`）。④ 🚨 **不可跨线程跨 loop 复用**"
    "（`rest_client.pool_manager` 是 `ClientSession`，绑定创建时的 loop，跨用报 "
    "`attached to a different loop`）；多线程混合架构须每线程独立 loop + client。 |"
)


def main():
    with io.open(TARGET, encoding="utf-8") as f:
        text = f.read()

    changed = []

    if PROGRESS_OLD in text and "课 9 番外：异步三个未实测项" not in text:
        text = text.replace(PROGRESS_OLD, PROGRESS_NEW, 1)
        changed.append("进度勾选")

    if ENV_OLD in text and "异步包硬约束" not in text:
        text = text.replace(ENV_OLD, ENV_NEW, 1)
        changed.append("环境基线")

    if changed:
        shutil.copyfile(TARGET, TARGET + ".bak3")
        with io.open(TARGET, "w", encoding="utf-8") as f:
            f.write(text)
        print("已更新:", ", ".join(changed))
    else:
        print("无需更新（可能已存在）")

    # 清理备份
    for b in (".bak", ".bak2", ".bak3"):
        p = TARGET + b
        if os.path.exists(p):
            os.remove(p)
            print("删除备份:", b)


if __name__ == "__main__":
    main()
