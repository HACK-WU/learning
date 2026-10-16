"""六个演示场景——每个对应一个知识点。

跑法：
    PYTHONPATH=. uv run --no-sync --project ../../../../langchain/playground python demo.py
"""
from research_agent import (
    DeadSource,
    FlakySource,
    GoodSource,
    SourceRegistry,
    run,
)


def line(t: str) -> None:
    print(f"\n{'=' * 62}\n{t}\n{'=' * 62}")


def main() -> None:
    line("场景 1：全部来源正常 → 扇出并行 + 汇总")
    reg = SourceRegistry([GoodSource("官方文档"), GoodSource("GitHub"), GoodSource("博客")])
    r = run("LangGraph 重试机制", ["官方文档", "GitHub", "博客"], reg)
    print(r["report"])
    print("\n  trace:", r["trace"])

    line("场景 2：部分来源挂了 → 优雅降级（核心）")
    reg2 = SourceRegistry([GoodSource("官方文档"), DeadSource("内部Wiki"), GoodSource("博客")])
    r2 = run("LangGraph 重试机制", ["官方文档", "内部Wiki", "博客"], reg2)
    print(r2["report"])
    print(f"\n  成功: {r2['succeeded']}  降级: {r2['failed']}")

    line("场景 3：来源抖动 → 重试真的生效")
    flaky = FlakySource("不稳定API", fail_times=2)
    reg3 = SourceRegistry([flaky, GoodSource("官方文档")])
    r3 = run("LangGraph", ["不稳定API", "官方文档"], reg3)
    print(f"  不稳定API 最终: {'成功' if '不稳定API' in r3['succeeded'] else '失败'}")
    print(f"  实际调用次数: {flaky.calls} 次（前 2 次抖动，第 3 次成功）")
    print(f"  成功: {r3['succeeded']}")

    line("场景 4：永久失败 → 不浪费重试次数")
    dead = DeadSource("已下线服务")
    reg4 = SourceRegistry([dead])
    r4 = run("q", ["已下线服务"], reg4)
    res = r4["results"][0]
    print(f"  ok: {res['ok']}")
    print(f"  error: {res['error']}")
    print("  >>> PermanentError 不在 retry_on 里，重试 0 次直接降级")

    line("场景 5：全部来源挂了 → 不崩，给说明性报告")
    reg5 = SourceRegistry([DeadSource("A"), DeadSource("B")])
    r5 = run("q", ["A", "B"], reg5)
    print(" ", r5["report"])

    line("场景 6：子图状态隔离 —— 父图拿不到子图私有字段")
    reg6 = SourceRegistry([GoodSource("官方文档")])
    r6 = run("q", ["官方文档"], reg6)
    print("  父图 state 的字段:", sorted(r6.keys()))
    print("  含 'scratch'（子图私有）吗:", "scratch" in r6)
    print("  >>> 实测：父子只传两边都声明的字段")


if __name__ == "__main__":
    main()
