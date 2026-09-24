"""在 00-评审清单.md 的课 3 记录前插入课 4 记录。"""
import io

P = "/mnt/d/projects/learning/kafka/kafka-python-client/00-评审清单.md"

ROW4 = (
    "| 2026-09-21 | 课 4 生产者内部机制 | 主 agent 内联（pedagogy + learner 双视角，命令照抄复验） | "
    "**P0 清零**。复验抓出 1 个真缺陷：acks rf=3 的「慢 188%」为单次测量不可复现（复验仅 66.4%）。"
    "已改为 5 轮取中位数+区间：`acks=-1/acks=0` 中位 2.19×（区间 1.24~3.49×），"
    "`acks=-1/acks=1` 中位 1.32×（最乐观 0.93×，三副本同机时接近打平），并显式标注单机集群局限。"
    "另修正 `_allocate` 不存在（课 2 同类错误：不猜名字，全量列举后定位） | "
    "已修并复验通过：背压结论二次确认、链接零断链、集群无残留 |\n"
)

with io.open(P, encoding="utf-8") as f:
    lines = f.readlines()

if any(r.startswith("| 2026-09-21 | 课 4") for r in lines):
    print("已有课 4 记录，跳过")
else:
    out = []
    done = False
    for ln in lines:
        if not done and ln.startswith("| 2026-09-21 | 课 3 AdminClient"):
            out.append(ROW4)
            done = True
        out.append(ln)
    with io.open(P, "w", encoding="utf-8") as f:
        f.writelines(out)
    print("已插入课 4 记录" if done else "未找到课 3 锚点")

# 验证
with io.open(P, encoding="utf-8") as f:
    for ln in f:
        if ln.startswith("| 2026-09-21 | 课 "):
            print("  ->", ln.split("|")[2].strip())
