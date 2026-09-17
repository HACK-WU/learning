#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
机械化证据链核对（课 10 首创，课 11 沿用，课 12 再升级）

做三件事：
1. 抽出正文里所有 ```console 块，逐行归一化（去首尾空白、折叠内部连续空白、去掉运行期漂移值）
2. 与 ALL_OUTPUT.txt 做集合比对，把"未直接命中"的行逐类归因
3. 统计结构性数字（console 块数、证据文件行数、常见误区条数），与正文里的自述数字对账
"""
import os
import re
import sys
from collections import OrderedDict

LESSON = "/Users/wuyongping/Desktop/learning/go/stages/4-标准库与网络编程/lessons/lesson-12-数据访问与客户端.md"

# 证据文件位置：优先用**脚本自己所在目录**下的 ALL_OUTPUT.txt
# （仓库里的只读归档 go/playground/lesson-12/ 靠这一条才能脱离 /tmp 独立复核），
# 找不到才回落到原始的临时模块路径。
_HERE = os.path.dirname(os.path.abspath(__file__))
EVIDENCE = os.path.join(_HERE, "ALL_OUTPUT.txt")
if not os.path.exists(EVIDENCE):
    EVIDENCE = "/tmp/go-l12/ALL_OUTPUT.txt"

# ---------- 漂移归一化 ----------
# 每次运行都会变的值，必须先抹掉再比对（课 11 的红线：这个声明要成立，必须把
# "每次运行都会变"的类别显式列出）
DRIFT_PATTERNS = [
    # 端口号
    (re.compile(r"\b127\.0\.0\.1:\d{4,5}\b"), "127.0.0.1:<PORT>"),
    (re.compile(r"\blocalhost:\d{4,5}\b"), "localhost:<PORT>"),
    (re.compile(r'"port":"\d+"'), '"port":"<PORT>"'),
    # 耗时：毫秒
    (re.compile(r"\d+(?:\.\d+)?\s*ms\b"), "<MS>ms"),
    # 耗时：微秒纳秒秒
    (re.compile(r"\d+(?:\.\d+)?\s*µs\b"), "<US>µs"),
    (re.compile(r"\d+(?:\.\d+)?\s*ns\b"), "<NS>ns"),
    (re.compile(r"\d+(?:\.\d+)?s\b"), "<S>s"),
    # 累计内存
    (re.compile(r"\d+(?:\.\d+)?\s*MB\b"), "<MB>MB"),
    (re.compile(r"\d+(?:\.\d+)?\s*KB\b"), "<KB>KB"),
    (re.compile(r"\d+(?:\.\d+)?\s*GB\b"), "<GB>GB"),
    (re.compile(r"\d+(?:\.\d+)?\s*B\b"), "<B>B"),
    # 大数字（分配次数 / 对象数）
    (re.compile(r"\b\d{4,}\b"), "<NUM>"),
    # goroutine / 连接数类的瞬时值不强归一，保留（它们是确定性的）
]


def normalize(line: str) -> str:
    s = line.strip()
    # 折叠内部连续空白
    s = re.sub(r"\s+", " ", s)
    for pat, rep in DRIFT_PATTERNS:
        s = pat.sub(rep, s)
    return s.strip()


# 结构化占位符（不是"输出行"，是课文里的省略标记）——单列出来，不算未命中
PLACEHOLDER = re.compile(r"^[.．·…]{2,}$")


def extract_table_rows(segment: str):
    """从一段 markdown 里抽出编号表格的「误区」列（第 2 列）文本"""
    rows = []
    for m in re.finditer(r"^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|", segment, re.M):
        rows.append((int(m.group(1)), m.group(2).strip()))
    return rows


def extract_console_blocks(text: str):
    """返回 [(block_index, start_line, [lines...]), ...]"""
    blocks = []
    lines = text.split("\n")
    i = 0
    idx = 0
    while i < len(lines):
        if re.match(r"^\s*```console\s*$", lines[i]):
            start = i + 1  # 1-based 行号
            j = i + 1
            body = []
            while j < len(lines) and not re.match(r"^\s*```\s*$", lines[j]):
                body.append(lines[j])
                j += 1
            idx += 1
            blocks.append((idx, start, body))
            i = j + 1
        else:
            i += 1
    return blocks


def main():
    with open(LESSON, encoding="utf-8") as f:
        lesson_text = f.read()
    with open(EVIDENCE, encoding="utf-8") as f:
        evidence_text = f.read()

    blocks = extract_console_blocks(lesson_text)

    # 证据文件行集合（归一化后）
    ev_norm = set()
    for ln in evidence_text.split("\n"):
        n = normalize(ln)
        if n:
            ev_norm.add(n)

    total_lines = 0
    hit_lines = 0
    placeholder_lines = 0
    miss_lines = []
    for bi, start, body in blocks:
        for off, raw in enumerate(body):
            n = normalize(raw)
            if not n:
                continue
            if PLACEHOLDER.match(n):
                placeholder_lines += 1
                continue
            total_lines += 1
            if n in ev_norm:
                hit_lines += 1
            else:
                miss_lines.append((bi, start + off, raw.rstrip()))

    print("=" * 72)
    print("课 12 机械化证据链核对")
    print("=" * 72)
    print(f"正文 console 块数      : {len(blocks)}")
    print(f"正文 console 输出行数  : {total_lines}（非空、非占位）")
    print(f"  直接命中证据文件     : {hit_lines}")
    print(f"  未直接命中           : {len(miss_lines)}")
    print(f"结构化省略占位行（跳过）: {placeholder_lines}")
    print(f"证据文件总行数         : {len(evidence_text.splitlines())}")
    print(f"证据文件非空归一化行   : {len(ev_norm)}")
    print()
    if miss_lines:
        print("---- 未直接命中的行（需逐类归因）----")
        for bi, ln, raw in miss_lines:
            print(f"  块#{bi} 正文L{ln}: {raw}")
    else:
        print("✅ 未直接命中 0 行")
    print()

    # ---------- 结构性数字对账 ----------
    print("=" * 72)
    print("结构性数字对账")
    print("=" * 72)

    lines = lesson_text.split("\n")

    def slice_from(start_pat):
        for i, l in enumerate(lines):
            if l.startswith(start_pat):
                j = i + 1
                while j < len(lines) and not re.match(r"^#{2,3} ", lines[j]):
                    j += 1
                return "\n".join(lines[i:j])
        return ""

    kp_tables = {}
    for i, l in enumerate(lines):
        if l.startswith("#### ⑤ 常见误区"):
            j = i + 1
            while j < len(lines) and not re.match(r"^#{3,4} ", lines[j]):
                j += 1
            kp_tables[l] = extract_table_rows("\n".join(lines[i:j]))
    merged_seg = slice_from("## 🐞 常见误区")
    merged = extract_table_rows(merged_seg)

    for name, rows in kp_tables.items():
        print(f"{name:<34}: {len(rows)} 条")
    print(f"{'合并表 ## 🐞 常见误区':<34}: {len(merged)} 条")

    # 真正的去重核对：合并表里有多少条，其「误区」列文字也出现在三张分表里
    kp_texts = set()
    for rows in kp_tables.values():
        for _, txt in rows:
            kp_texts.add(re.sub(r"\s+", "", txt.strip("`* ")))
    dup = [
        (n, txt)
        for n, txt in merged
        if re.sub(r"\s+", "", txt.strip("`* ")) in kp_texts
    ]
    print(f"合并表中「误区」列文字与分表重合 : {len(dup)} 条"
          + (f" → {[n for n, _ in dup]}" if dup else ""))

    # 第四幕自述的 console 块数 / 证据行数
    for mm in re.finditer(r"(\d+)\s*个\s*`console`\s*块", lesson_text):
        print(f"正文自述 console 块数  : {mm.group(1)}  ← 实际 {len(blocks)}")
    for mm in re.finditer(r"（\*\*(\d+) 行\*\*", lesson_text):
        print(f"正文自述证据文件行数   : {mm.group(1)}  ← 实际 {len(evidence_text.splitlines())}")

    # 重复分隔线检测（允许中间夹一个空行）
    dups = []
    for k in range(len(lines) - 2):
        if lines[k].strip() == "---" and lines[k + 1].strip() == "" and lines[k + 2].strip() == "---":
            dups.append(k + 1)
    print(f"近似重复 --- 位置      : {dups if dups else '无'}")

    print()
    print("=" * 72)
    print("结论")
    print("=" * 72)
    if not miss_lines:
        print("✅ 正文引用的每一段输出都在证据文件里有对应记录（归一化后）")
    else:
        print(f"❌ 有 {len(miss_lines)} 行未命中，需逐类归因清零")
    return 0 if not miss_lines else 1


if __name__ == "__main__":
    sys.exit(main())
