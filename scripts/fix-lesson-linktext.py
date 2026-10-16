#!/usr/bin/env python3
"""规范化 Markdown 链接「显示文字」里残留的 `lesson-` 前缀。

背景：`rename-lessons.py` 按「完整文件名」做字面量替换，能改掉链接**路径**，
但改不掉**显示文字**——因为显示文字是手写的裸课号（如 `[lesson-01]`、
`[lesson-06 KV 存储与配置管理]`），并非文件名，不含扩展名，匹配不到。
本脚本专门收尾这部分。

用法：
    python3 scripts/fix-lesson-linktext.py            # 预演
    python3 scripts/fix-lesson-linktext.py --apply    # 执行

替换规则（仅作用于 `[` 与 `]` 之间的链接文字）：
    [lesson-01]                      -> [01]
    [lesson-06 KV 存储与配置管理]      -> [06 KV 存储与配置管理]
    [lesson-06-监控指标与告警]         -> [06-监控指标与告警]
    [lesson-0-3]                     -> [0-3]
    [lesson-13 playground README]     -> [13 playground README]

安全性：
  - 只改 `[...]` 方括号内的文字，不碰括号外的正文与链接目标（`(...)`）。
  - 支持 `[text](url)` 与 `[text][ref]` 两种写法。
  - 图片 `![alt](url)` 的 alt 同样处理（同属显示文字）。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# 链接文字里的 lesson- 前缀。三段拼接：
#   ① \d+(?:-\d+)?  —— 课号，兼容 zookeeper 的 `0-3` 多段编号
#   ② (?:\.[^\]\s]*)? —— 可能存在的扩展名（如 `[lesson-01.md]`）
#   ③ (?:[- ][^\]]*)?  —— 课号后的补充描述，`-课名` 或 ` 课名` 两种分隔
# 结尾必须是 `]`，保证不会跨出链接文字边界。
LT_RE = re.compile(r"\[lesson-(\d+(?:-\d+)?)((?:\.[^\]\s]*)?(?:[- ][^\]]*)?)\]")

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".mypy_cache"}


def walk_md() -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(REPO):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(".md"):
                out.append(Path(dirpath) / fn)
    return out


def fix_text(text: str) -> tuple[str, int]:
    """去掉链接文字里的 lesson- 前缀。返回 (新文本, 替换次数)。"""

    def _sub(m: re.Match[str]) -> str:
        # m.group(1) 是课号（如 01 或 0-3），m.group(2) 是可选后缀
        return "[" + m.group(1) + m.group(2) + "]"

    new, n = LT_RE.subn(_sub, text)
    return new, n


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--apply", action="store_true", help="真正执行（默认仅预演）")
    args = ap.parse_args()

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"=== {mode} ===")

    total = 0
    touched: list[tuple[Path, int, list[str]]] = []
    for md in walk_md():
        try:
            text = md.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        new, n = fix_text(text)
        if not n:
            continue
        before = re.findall(r"\[lesson-\d+[^\]]*\]", text)
        total += n
        touched.append((md, n, before[:3]))
        if args.apply:
            md.write_text(new, encoding="utf-8")

    print(f"命中文件：{len(touched)} 个，共替换 {total} 处\n")
    if not args.apply:
        for md, n, samples in touched:
            print(f"  {md.relative_to(REPO)}  ({n} 处)")
            for s in samples:
                print(f"      {s}")
        print("\n预演结束。确认无误后加 --apply 执行。")
        return 0

    print("已执行。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
