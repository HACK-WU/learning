"""回写 overview.md：追加课 9 番外的交付记录行

插到「课 9 交付」那一行之后（保持时间倒序的既有风格）。
"""
import io
import os
import shutil
import sys

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

ROW = (
    "| 2026-09-29 | **课 9 番外交付**（异步三个未实测项 · 547 行 / 5 部分） | "
    "主 agent 内联（pedagogy + learner，独立性受限）+ 实测核验 | "
    "P0=0。**补齐课 9 遗留三处未实测**。① **写操作并发共享 client 安全性**："
    "分 S1~S4 四种场景——S1 共享 client 并发写 20 个不同 ConfigMap **20/20**、"
    "0.037s、回读**值不符 0 个**；S2 同名写 **1 OK + 9×409**（409 是服务端语义，"
    "非客户端缺陷）；S3 每协程独立 client **20/20 但慢 43%**（0.053s vs 0.037s，"
    "因重复建 TCP + ClientSession）；S4 并发 patch 同一对象 **15/15**"
    "（不带 rv 天然避 409）。🚨 **数字异常先查测法**：回读 21 个 vs 写入 20 个，"
    "经查空 ns 自带 1 个 k8s 自动注入的 `kube-root-ca.crt`，非残留污染。"
    "② **429 打不出来，且已证明非测法问题**：L1~L3 三级加压至 4000 请求 / 3562 QPS、"
    "再持续 8 秒 23096 请求 / 2852 QPS，**429 恒为 0**；三条独立取证——E1 请求真被 "
    "apiserver 处理（`Audit-Id` 存在）、E2 客户端能正确捕获 404、E3 APF 配置查明根因："
    "我方请求落 **`global-default`（Queue 型，128 队列 / 上限 50，排队而非拒绝）**，"
    "唯一 `Reject` 型的 `catch-all`（nominal=5）正常身份命中不了、匿名又被 kind 拒。"
    "如实标注为**环境级结论**，并说明生产集群仍可能触发。"
    "③ **重试风暴**：改用**注入故障**法（不依赖真 429），p=0.9 时 3 次重试放大 "
    "**2.69x**、5 次放大 **4.10x**。⚠️ **反直觉结论**：退避+jitter 与朴素重试的"
    "**放大倍数几乎相同**（2.69x vs 2.69x / 4.10x vs 4.11x）——jitter **不降总量**，"
    "其价值在**打散扎堆**（1ms 窗口内「峰值/重试数」**0.583 → 0.121**，差 4.8 倍）。"
    "**顺带修正课 9 两处表述**：① 异步 API 方法是**普通 `def`**"
    "（`iscoroutinefunction=False`），靠内层 **`ApiClient.__call_api` 是 `async def`** "
    "整体成为可等待；判断要不要 await 须看**调用后返回值**是否 `isawaitable`，"
    "不能用 `iscoroutinefunction` 看类属性。② 🚨 **`async_req=True` 在异步包里不是"
    "\"假异步\"而是完全坏掉**——返回 `multiprocessing.pool.ApplyResult`，`await` 直接 "
    "`TypeError`；源码显示异步包仍 `from multiprocessing.pool import ThreadPool`，"
    "把协程丢进线程池而线程不会 await 它，刷 `RuntimeWarning: coroutine was never awaited`。"
    "🚨 **新抓硬坑 2 个**：`ApiClient` **必须在 running loop 内实例化**"
    "（loop 外 `RuntimeError: no running event loop`，因 `RESTClientObject` 构造 "
    "aiohttp `TCPConnector` 需 running loop）；**不能跨线程跨 loop 复用**——"
    "`rest_client.pool_manager` 是 aiohttp `ClientSession`，绑定创建时的 loop，"
    "跨用报 `RuntimeError: ... attached to a different loop`；反证：线程内新建 loop "
    "+ 新建 client 则成功。**测法错误 3 处**（本系列第 6、7、8 次应验铁律）："
    "① 用 `iscoroutinefunction` 判协程性，得\"异步包 0 个协程方法\"荒谬结论；"
    "② 拿\"读不存在的 namespace\"当 404 正对照，结果没报错——因 **list 空 ns 本就返回 "
    "200 + 空列表**，正对照选错，改用 `read` 具体对象才抛 `ApiException(404)`；"
    "③ 惊群度量分桶窗口 5ms 与模拟 RTT 2ms 尺度不匹配，三种策略\"最大同窗\"恒等于并发数 "
    "200（指标无区分力）→ 修正为 RTT 拉到 20ms + 窗口缩到 1ms + **只看重试请求**"
    "（首轮齐发是业务行为会稀释信号）+ 用归一判据。「未实测标注 1 处」："
    "429 分支的 `Retry-After` 取值方式依据 HTTP 标准与库源码推断，本机 0 次触发未经真验。"
    "本地链接 9 条全在（修 1 条 `overview.md` → `../overview.md` 层级错误）、"
    "外链 0、敏感 0、ns 残留 0、17 个脚本 `py_compile` 全过 |\n"
)


def main():
    with io.open(TARGET, encoding="utf-8") as f:
        lines = f.readlines()

    if any("课 9 番外交付" in l for l in lines):
        print("已存在交付记录，跳过")
        return

    idx = None
    for i, l in enumerate(lines):
        if "**课 9 交付**" in l:
            idx = i
            break
    if idx is None:
        print("未找到课 9 交付行，中止")
        sys.exit(1)

    print(f"在行 {idx+1} 后插入交付记录")
    shutil.copyfile(TARGET, TARGET + ".bak2")
    lines.insert(idx + 1, ROW)
    with io.open(TARGET, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("写入完成")


if __name__ == "__main__":
    main()
