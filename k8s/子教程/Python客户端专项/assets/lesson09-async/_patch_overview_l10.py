"""回写 overview.md：课 10

1. 课程表：在课 9 番外行后插入课 10
2. 交付记录：插入课 10 交付行
3. 进度：勾选课 10
"""
import io
import os
import shutil

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")

COURSE_ROW = (
    "| [课 10：重试中间件工程化](lessons/lesson-10-重试中间件工程化.md)"
    "（✅ 已交付 2026-09-29） | 把课 6 番外 4 的教学版 `retry_async` 升级为"
    "**生产可用中间件**（306 行），补齐它未覆盖的三块：**① 429 与 `Retry-After`**"
    "——支持 RFC 9110 的 `delay-seconds` 与 `HTTP-date` 两种形式，头名大小写不敏感、"
    "负数归零、解析失败退回 jitter，并用 `retry_after_cap=30.0` 截断离谱大值"
    "（实测服务端给 999s 被截到 0.0300s）；**② 并发闸门**——`Semaphore` 限在飞数，"
    "实测峰值 5 vs 无闸门 50；**③ 重试预算**——放大精确控制在 `1+ratio`"
    "（ratio=0.5 → 1.50x）。**错误分类**：4xx 中只放行 409/429，"
    "400/401/403/404/405/410/422 判 **fatal 立即放弃**（实测 404 只调用 1 次）；"
    "非 `ApiException`（超时/连接）按可重试。**底线**：放弃时 **raise**，"
    "绝不返回 `(None, False)`（课 6 番外 4 坑 1 的静默失败）。"
    "🚨 **抓到 1 个真实现缺陷——预算时序饥饿**：原 `allowed = first_round * ratio` "
    "用的是**已观察到**的首轮数，批量并发时先失败者抢光额度——实测 `ratio=0.5`、n=30 "
    "同时发起**只成功 15/30**，而\"先灌满基数\"对照组 **30/30**。根因不是限流而是"
    "**额度分配不公**。修复：批量场景 `total` 已知，改为 `total × ratio` 固定额度，"
    "`gather_with_retry` 自动传 `total=len(calls)`，修复后与时序无关且无回归。"
    "🚨 **第 9 次测法错误**：断言\"jitter 等待 < 0.1s\"偶发失败（实测 0.1096s）——"
    "**断言写错了**，equal jitter 两次等待理论范围 `[0.075, 0.150]` 本就可能 >0.1；"
    "判据与性质不对应：要验证**随机性**却用**大小比较**；改为多次运行的波动 "
    "`spread > 0.005`。**测试 48 项全通过**（主套件 41 + 修复验证 7，连跑 3 次稳定），"
    "全部注入式故障验证。⚠️ 交付核验抓到并修正 2 处不实：讲义原称\"48 项\"未说明是两套件之和"
    "（主套件实为 41）、`2.00x` 原标 B3 实为 `_verify_budget.py` V2 的输出。"
    "本地链接 11 条全在、外链 0、敏感 0、29 个脚本 `py_compile` 全过 | 主线课 14 |\n"
)

DELIVERY_ROW = (
    "| 2026-09-29 | **课 10 交付**（重试中间件工程化 · 433 行 / 6 幕） | "
    "主 agent 内联（pedagogy + learner，独立性受限）+ 48 项断言实测 | P0=0。"
    "**产出**：`retry_middleware.py`（306 行，生产可用）+ 测试套件。"
    "**五项能力均有实测**：错误分类（4xx 只放行 409/429，fatal 立即放弃，"
    "404 实测只调用 1 次）、`Retry-After` 解析（秒数/HTTP-date/大小写/负数/非法值 "
    "8 项全过，cap 截断 999s→0.0300s）、并发闸门（峰值 5 vs 无闸门 50）、"
    "重试预算（放大精确 1+ratio）、**放弃时 raise 不静默**（A5）。"
    "🚨 **发现并修复 1 个真实现缺陷**：预算**时序饥饿**——原实现按"
    "`first_round * ratio` 算额度，批量并发时先失败者抢光额度，"
    "实测 ratio=0.5/n=30 同时发起只成功 **15/30**，而预热对照组 **30/30**；"
    "根因是**额度分配不公**而非限流；修复为按已知 `total` 固定额度。"
    "抓到它的线索是**数字太整齐**（放大恰好 1.50x、耗尽恰好 50 次 = 全部被拒），"
    "这是\"先怀疑测量方法\"铁律在**实现层面**的延伸。"
    "🚨 **第 9 次测法错误**：断言\"jitter 等待 < 0.1s\"偶发失败（0.1096s），"
    "**是断言错了不是代码错了**——equal jitter 两次等待理论范围 [0.075,0.150] 本就可能 >0.1；"
    "判据与性质不对应（要验随机性却比大小），改为波动 spread > 0.005。"
    "**交付核验抓到并修正 2 处表述不实**：① 讲义称\"48 项断言\"但未说明是"
    "两套件之和（主套件实为 41）② `2.00x` 原标注为 B3 输出，实为 `_verify_budget.py` V2。"
    "⚠️ 未实测标注 1 处：`Retry-After` 的 HTTP-date 分支本机 0 次真 429 触发，"
    "属注入式验证。本地链接 11 条全在、外链 0、敏感 0、29 个脚本 `py_compile` 全过 |\n"
)

PROGRESS_ROW = "- [x] 课 10：重试中间件工程化（429 / Retry-After / 放大控制）\n"


def main():
    with io.open(TARGET, encoding="utf-8") as f:
        lines = f.readlines()

    changed = []

    # 1. 课程表：插到课 9 番外行之后
    if not any("课 10：重试中间件工程化" in l and l.startswith("|") for l in lines):
        idx = None
        for i, l in enumerate(lines):
            if l.startswith("|") and "课 9 番外：异步三个未实测项" in l:
                idx = i
                break
        if idx is not None:
            lines.insert(idx + 1, COURSE_ROW)
            changed.append("课程表")

    # 2. 交付记录：插到课 9 番外交付行之后
    if not any("**课 10 交付**" in l for l in lines):
        idx = None
        for i, l in enumerate(lines):
            if "课 9 番外交付" in l:
                idx = i
                break
        if idx is not None:
            lines.insert(idx + 1, DELIVERY_ROW)
            changed.append("交付记录")

    # 3. 进度：插到课 9 番外进度行之后
    prog = [i for i, l in enumerate(lines) if l.startswith("- [x] 课 ")]
    if not any("重试中间件工程化" in lines[i] for i in prog):
        idx = None
        for i in prog:
            if "番外：异步三个未实测项" in lines[i]:
                idx = i
                break
        if idx is not None:
            lines.insert(idx + 1, PROGRESS_ROW)
            changed.append("进度")

    if changed:
        shutil.copyfile(TARGET, TARGET + ".bakL10")
        with io.open(TARGET, "w", encoding="utf-8") as f:
            f.writelines(lines)
        print("已更新:", ", ".join(changed))
    else:
        print("无需更新")

    # 校验
    with io.open(TARGET, encoding="utf-8") as f:
        t = f.read()
    print()
    print("校验:")
    print("  课程表含课 10 :", "✓" if "课 10：重试中间件工程化" in t else "✗")
    print("  交付记录含课10:", "✓" if "**课 10 交付**" in t else "✗")
    print("  进度含课 10   :", "✓" if "- [x] 课 10" in t else "✗")

    if os.path.exists(TARGET + ".bakL10"):
        os.remove(TARGET + ".bakL10")
        print("  备份已清理")


if __name__ == "__main__":
    main()
