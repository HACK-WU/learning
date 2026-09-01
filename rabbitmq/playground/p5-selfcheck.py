# -*- coding: utf-8 -*-
"""Phase 5 三份产物的自检脚本：检查结构完整性与关键硬事实是否落盘。"""
import io
import os
import re
import sys

BASE = "/mnt/d/projects/learning/rabbitmq"
if not os.path.exists(BASE):
    BASE = "D:/projects/learning/rabbitmq"

TARGETS = {
    "08-实战经验.md": [
        "## 一、适用边界",
        "## 二、8 个高频故障模式",
        "## 三、落地 Checklist",
        "## 四、从课程到生产的 5 处认知落差",
        "故障模式 1",
        "故障模式 8",
        "x-consumer-timeout",
        "rabbitmq_process_resident_memory_bytes",
    ],
    "09-排障速查手册.md": [
        "## 🚨 0. 前三分钟：止血决策树",
        "## 1️⃣ 丢消息类",
        "## 2️⃣ 积压类",
        "## 3️⃣ 连接与异常类",
        "## 4️⃣ 集群与 broker 类",
        "## 5️⃣ 重复与顺序类",
        "## 📋 附：条件 - 动作速查表",
        "## 🆘 升级出口",
    ],
    "10-场景解法库.md": [
        "## 场景 1：大促流量削峰",
        "## 场景 8：",
        "推荐递进路径",
        "什么时候不该用 RabbitMQ",
    ],
}

# 每份文件必须满足的 <details> 数量（先想后看折叠块）
DETAILS_MIN = {
    "08-实战经验.md": 0,
    "09-排障速查手册.md": 0,
    "10-场景解法库.md": 8,
}

# 场景库：每个场景必须挂知识点
ANCHOR_RE = re.compile(r"^## 场景 (\d+)：(.+)$", re.M)
HOOK_RE = re.compile(r"课 \d+")


def read(name):
    with io.open(os.path.join(BASE, name), "r", encoding="utf-8") as f:
        return f.read()


def main():
    failures = []
    checks = 0

    for name, must_haves in TARGETS.items():
        try:
            text = read(name)
        except IOError as exc:
            failures.append("[%s] 读取失败: %s" % (name, exc))
            continue

        for token in must_haves:
            checks += 1
            if token not in text:
                failures.append("[%s] 缺失章节/关键词: %s" % (name, token))

        n_details = text.count("<details>")
        need = DETAILS_MIN[name]
        checks += 1
        if n_details < need:
            failures.append("[%s] <details> 折叠块不足: 有 %d，需要 >= %d"
                            % (name, n_details, need))

        checks += 1
        if n_details and text.count("</details>") != n_details:
            failures.append("[%s] <details> 与 </details> 数量不匹配: %d vs %d"
                            % (name, n_details, text.count("</details>")))

    # 场景库专项：场景数量 + 每个场景挂知识点 + 解法数量
    try:
        lib = read("10-场景解法库.md")
    except IOError:
        lib = ""

    if lib:
        scenes = ANCHOR_RE.findall(lib)
        checks += 1
        if not (5 <= len(scenes) <= 8):
            failures.append("[10-场景解法库.md] 场景数应在 5-8，实际 %d" % len(scenes))

        # 按场景切块，检查每块是否有知识点挂钩
        parts = ANCHOR_RE.split(lib)
        # split 结果: [前言, num, title, body, num, title, body, ...]
        idx = 1
        while idx + 2 < len(parts):
            num, title, body = parts[idx], parts[idx + 1], parts[idx + 2]
            checks += 1
            if not HOOK_RE.search(body):
                failures.append("[场景 %s %s] 缺少知识点挂钩（未出现「课 N」）" % (num, title))
            checks += 1
            if "不适用" not in body:
                failures.append("[场景 %s %s] 缺少「不适用」边界说明" % (num, title))
            idx += 3

    print("=" * 60)
    print("Phase 5 自检：%d 项检查" % checks)
    if failures:
        print("❌ 失败 %d 项：" % len(failures))
        for f in failures:
            print("   - " + f)
        return 1
    print("✅ 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
