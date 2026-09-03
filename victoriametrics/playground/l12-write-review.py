#!/usr/bin/env python3
# 课 12 档案回写 2/2：00-评审清单.md
# 1) 勾选课 12 一行
# 2) 评审记录表追加课 12 一行
import sys

P = "/mnt/d/projects/learning/victoriametrics/00-评审清单.md"
src = open(P, encoding="utf-8").read()
orig = src
DATE = "2026-09-02"

# ---------- 1) 勾选 ----------
old = "- [ ] 阶段 5·课 12《备份恢复、迁移与选型决策》 — pedagogy + learner 双视角"
new = f"- [x] 阶段 5·课 12《备份恢复、迁移与选型决策》 — pedagogy + learner 双视角 — P0=0（{DATE}）"
if new in src:
    print("  [SKIP] 已勾选")
elif old in src:
    src = src.replace(old, new, 1)
    print("  [OK] 课 12 已勾选")
else:
    print("  [WARN] 未找到勾选行"); sys.exit(1)

# ---------- 2) 评审记录追加 ----------
REC = (
    f"| {DATE} | 课 12《备份恢复、迁移与选型决策》 | 主 agent 内联（pedagogy + learner） | 0 | "
    "**14 组实验全部真跑，均给出判据**。① **快照是硬链接冻结视图**：快照与原始文件同一 inode"
    "（`7318349394894097`）、`links=3`，建快照 df 仅增 **184 KB**（`du` 增 54 KB 属硬链接重复计数，"
    "判据：必须用 df 不能用 du），写入 300 条后快照 md5 不变。② **vmbackup 拒绝无快照备份**"
    "（`-origin cannot be empty`），是设计非缺陷。③ **增量备份**：首次 7,169,266 B → 第二次 "
    "**136,362 B（1.9%）**。④ **备份不阻塞服务**：备份中 20 次写入全成功（316 ms）、查询 0.0397s、"
    "/health 200。⑤ **恢复完整**：41,774 条序列、618 指标名两端一致，两批 marker 各 50 条，"
    "抽查 `i=\"7\"` 均为 7。⑥ **S3/MinIO 打通**（175 对象 / 6.9 MiB / 恢复 41,794 条），"
    "路径坑：`-dst=s3://<bucket>/<path>` 须与 `-customS3Endpoint` 分离，写成 "
    "`s3://http://ip:9000/bucket` 报 `InvalidBucketName`；另 `--network host` 会撞 8420 端口，"
    "须指定 `-httpListenAddr`。⑦ **9p 不支持 fallocate**（Windows+WSL 特有）：在 `D:\\` 挂载目录"
    "恢复报 `cannot fallocate 210 bytes`，改用 docker 命名卷后成功。⑧ **vmctl 迁移**："
    "1058 万样本 / 195.4 MB / **5.76 s**，指标名 619→646；三参数坑：须加 "
    "`-s --disable-progress-bar`（否则 `inappropriate ioctl for device`）、"
    "`--remote-read-step-interval` 取值是 `month/week/day/hour/minute` 非秒数、"
    "vmctl 对 `--vm-addr` 拼 `/health` 探测（集群须指 vmselect，指 vminsert 返 400）。"
    "⑨ **迁移幂等**：同窗口重跑样本数完全一致（10,580,035）。"
    "⑩ **删除是墓碑机制**（本课最重要发现）：`delete_series` 返 204、日志确认 "
    "`Deleted 20000 series`，但删 5 万条后磁盘**反增 2,348 KB**、`/series/count` 不降"
    "（142,394→142,396）、60 秒后仍高 148 KB；**不可逆无回收站**，本课误删 20,000 条因备份"
    "晚于删除**无法找回**（实测）——这是「没恢复过的备份等于没备份」的实锤。"
    "⑪ **时间戳单位陷阱**：import 用毫秒，传秒级 `1788355138` 被解析成 **1970-01-22**；"
    "验证写入须用 `/api/v1/export` 而非 query（后者有秒级延迟）。"
    "⑫ **RTO/RPO 实测**：RTO = **2,548 ms**（纯 vmrestore 1,126 ms），灾后 500 条全丢。"
    "**P1×2 已修**：Agent A 报 Mermaid 缺失（补备份全链路图）；"
    "Agent B 报 L24 危险命令无提示（补⚠️引述说明）。Agent A 另报「绝不」——经核验为**误报**"
    "（安全警示句式，有实测支撑）。**遗留未闭环×3**：快照长期保留对回收的定量影响、"
    "vm-native 跨租户迁移未跑通、删除后合并回收的确切时机 |\n"
)

anchor = f"| {DATE} | 课 11《vmagent 与 vmalert》 |"
if "课 12《备份恢复、迁移与选型决策》 | 主 agent 内联" in src:
    print("  [SKIP] 评审记录已存在")
else:
    idx = src.find(anchor)
    if idx == -1:
        print("  [FAIL] 未找到课 11 锚点"); sys.exit(1)
    end = src.find("\n", idx)
    src = src[:end + 1] + REC + src[end + 1:]
    print("  [OK] 评审记录已追加")

open(P, "w", encoding="utf-8").write(src)
print(f"\n写入完成：{P}")
print(f"  字符数 {len(orig)} -> {len(src)}  (+{len(src)-len(orig)})")
