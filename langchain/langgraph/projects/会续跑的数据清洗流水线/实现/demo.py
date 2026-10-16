"""六个演示场景——每个对应一个知识点。

跑法：
    PYTHONPATH=. uv run --no-sync --project ../../../../langchain/playground python demo.py
"""
import time

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task

from pipeline.flow import pipeline, resume_batch, run_batch
from pipeline.models import make_batch


def line(t: str) -> None:
    print(f"\n{'=' * 62}\n{t}\n{'=' * 62}")


DIRTY = [
    {"name": " 张三 ", "age": "30", "amount": "100", "city": "北京"},
    {"name": "李四", "age": "abc", "amount": "99999", "city": "N/A"},
    {"name": "", "age": "25", "amount": "50", "city": "上海"},
]


def main() -> None:
    line("场景 1：干净数据 —— 一路跑完，不中断")
    b = make_batch("干净批次", [
        {"name": "张三", "age": "30", "amount": "100", "city": "北京"},
        {"name": "李四", "age": "40", "amount": "200", "city": "上海"},
    ])
    r = run_batch(b, "s1")
    if "result" in r:
        print(r["result"].summary())
    else:
        print("  （无中断，结果为:", r, "）")

    line("场景 2：脏数据 —— 卡住等人工裁决")
    b2 = make_batch("脏批次", DIRTY)
    r2 = run_batch(b2, "s2")
    assert "__interrupt__" in r2, "应中断"
    payload = r2["__interrupt__"][0].value
    print(f"  ⏸ 批次「{payload['batch']}」有 {len(payload['rows'])} 行需人工确认：")
    for row in payload["rows"]:
        print(f"    行 {row['id']}: {row['errors']}")
    print("\n  >>> 此时流水线暂停，前面的清洗结果已进存档点")

    line("场景 3：续跑 —— 人工裁决后继续（核心）")
    ids = [row["id"] for row in payload["rows"]]
    r3 = resume_batch("s2", {i: "accept" for i in ids})
    print(r3["result"].summary())
    print("\n  >>> 关键：clean_row / detect_outliers 的结果从存档点取，不重算")

    line("场景 4：对照 —— 拒绝会怎样")
    b4 = make_batch("脏批次", DIRTY)
    r4 = run_batch(b4, "s4")
    ids4 = [row["id"] for row in r4["__interrupt__"][0].value["rows"]]
    r4b = resume_batch("s4", {i: "reject" for i in ids4})
    print(r4b["result"].summary())
    for row in r4b["result"].rows:
        if row.errors:
            print(f"    行 {row.id} 错误: {row.errors}")

    line("场景 5：并发 —— 不立即 .result() 才并发")

    @task
    def slow(x: int) -> int:
        time.sleep(0.3)
        return x

    @entrypoint(checkpointer=InMemorySaver())
    def par(x: int) -> int:
        f1 = slow(x)
        f2 = slow(x + 10)
        return f1.result() + f2.result()

    @entrypoint(checkpointer=InMemorySaver())
    def ser(x: int) -> int:
        return slow(x).result() + slow(x + 10).result()

    t0 = time.time()
    v1 = par.invoke(1, {"configurable": {"thread_id": "pc"}})
    dt_par = time.time() - t0
    t0 = time.time()
    v2 = ser.invoke(1, {"configurable": {"thread_id": "sc"}})
    dt_ser = time.time() - t0
    print(f"  并发（先全提交再收）: {v1}  耗时 {dt_par:.2f}s")
    print(f"  串行（立即 .result()）: {v2}  耗时 {dt_ser:.2f}s")
    print(f"  >>> 快了 {dt_ser / dt_par:.1f} 倍")

    line("场景 6：Functional API 的状态长什么样")
    hist = list(pipeline.get_state_history({"configurable": {"thread_id": "s1"}}))
    print(f"  历史条数: {len(hist)}")
    for s in hist:
        print(f"    next={s.next}")
    print("\n  >>> 对比 Graph API（2 节点有 4 条历史），Functional 只有 entrypoint 一层")
    print("  >>> 这就是选型的代价：中间过程没有具名字段可 inspect")


if __name__ == "__main__":
    main()
