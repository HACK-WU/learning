"""回写 overview.md：在课 9 行之后插入课 9 番外行

用 replace_in_file 因整行太长匹配失败，改用脚本按行定位插入，更可靠。
"""
import io
import os
import shutil
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

NEW_ROW = (
    "| [课 9 番外：异步三个未实测项]"
    "(lessons/lesson-09-async-异步三个未实测项.md)（✅ 已交付 2026-09-29） | "
    "补齐课 9 留下的三处未实测。**① 写共享安全**：S1 并发写 20 个不同 ConfigMap "
    "**20/20**、值无错乱；S2 同名写 **1 OK + 9×409**（服务端语义非客户端缺陷）；"
    "S3 独立 client 反慢 **43%**（0.053s vs 0.037s，重复建连）；S4 并发 patch 同一对象 "
    "**15/15**。⚠️ 回读 21 个 vs 写入 20 个，经查是 k8s 自动注入的 `kube-root-ca.crt`，"
    "非残留污染。**② 429 打不出来且已证非测法问题**：三级加压 4000 请求 / 3562 QPS "
    "+ 持续 8 秒 23096 请求 / 2852 QPS，**429 恒为 0**；三条取证：请求真打到 apiserver"
    "（`Audit-Id` 存在）、客户端能正确捕获 404（`read` 不存在对象）、APF 配置查明根因——"
    "我方请求落 **`global-default`（Queue 型，128 队列/上限 50，排队非拒绝）**，"
    "唯一 `Reject` 型的 `catch-all` 正常身份命中不了，匿名又被 kind 拒。"
    "**③ 重试风暴**：注入故障实测，p=0.9 时 3 次重试放大 **2.69x**、5 次放大 **4.10x**。"
    "⚠️ **反直觉结论**：退避+jitter 与朴素重试的**放大倍数几乎相同**（2.69x vs 2.69x），"
    "jitter 的价值是**打散扎堆**而非降低总量（1ms 窗口内峰值/重试数 **0.583 → 0.121**，"
    "差 4.8 倍）。**顺带修正课 9 两处表述**：异步 API 方法是**普通 `def`**"
    "（`iscoroutinefunction=False`），靠内层 **`__call_api` 是 `async def`** 成为可等待，"
    "判断要不要 await 须看**调用后返回值**；🚨 **`async_req=True` 在异步包里不是\"假异步\""
    "而是完全坏掉**——返回 `multiprocessing.pool.ApplyResult`，`await` 直接 `TypeError`，"
    "协程被塞进线程池永不执行（刷 `RuntimeWarning: coroutine was never awaited`）。"
    "🚨 **新抓硬坑**：`ApiClient` **必须在 running loop 内实例化**（loop 外 "
    "`RuntimeError: no running event loop`），且**不能跨线程跨 loop 复用**"
    "（`pool_manager` 是 `ClientSession`，绑定创建时的 loop → "
    "`attached to a different loop`）；多线程混合架构须每线程独立 loop + client。"
    "**测法错误 3 处**（本系列第 6、7、8 次）：`iscoroutinefunction` 判协程性得"
    "\"0 个协程方法\"荒谬结论；拿\"读不存在的 ns\"当 404 正对照（list 空 ns 本就 200，"
    "正对照选错）；惊群分桶窗口 5ms 与 RTT 2ms 尺度不匹配致三种策略结果恒等于并发数 200 "
    "→ 修正为 RTT 20ms + 窗口 1ms + 只看重试请求。ns 残留 0，脚本 17 个 `py_compile` 全过，"
    "外链 0、敏感 0 | 主线课 14 |\n"
)


def main():
    with io.open(TARGET, encoding="utf-8") as f:
        lines = f.readlines()

    # 已插入则跳过
    if any("课 9 番外" in l for l in lines):
        print("已存在课 9 番外行，跳过")
        return

    # 找课 9 那一行
    idx = None
    for i, l in enumerate(lines):
        if l.startswith("| [课 9：异步客户端与并发]"):
            idx = i
            break
    if idx is None:
        print("未找到课 9 行，中止")
        sys.exit(1)

    print(f"在行 {idx+1} 之后插入课 9 番外行")
    shutil.copyfile(TARGET, TARGET + ".bak")
    lines.insert(idx + 1, NEW_ROW)
    with io.open(TARGET, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("写入完成（已备份 .bak）")


if __name__ == "__main__":
    main()
