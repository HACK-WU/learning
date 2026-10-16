#!/usr/bin/env python3
"""批量把 topic-teach 教程的 `lesson-NN-*` 命名改成规范的 `NN-*` 形态。

背景：topic-teach 规则要求课文件名 = `{NN}-{课名}.md`（两位数序号 + 中文课名，
**不带 `lesson-` 前缀**），SVG / 脚本等随课产物同理。早期课程大量使用
`lesson-NN-*` 前缀，本脚本做一次性批量纠正。

用法：
    python3 scripts/rename-lessons.py            # 预演（默认，不改任何文件）
    python3 scripts/rename-lessons.py --apply    # 真正执行

安全性设计（务必先读再改）：
  1. **只重命名「文件名」以 `lesson-` 开头的文件**，绝不重命名目录。
     形如 `prometheus/labs/lesson-03/`、`go/playground/lesson-12/` 的目录是
     实验工作区，名字保持不动（有正文链接指向它们）。
  2. 引用替换按「已知被重命名的完整 basename」做**字面量替换**，不解析路径：
       映射表里的键就是文件全名（如 `05-备份、恢复与灾备演练.md`），
       它同时覆盖「带路径引用」与「同目录裸文件名引用」两种写法。因此：
       - `.../lessons/lesson-09-xxx.md`     → 命中全名 → 替换 ✅
       - `[课 5](05-备份、恢复与灾备演练.md)`（同目录裸名）→ 命中 → 替换 ✅
       - `../../../labs/lesson-09/DATA.md`  → 无任何映射键命中 → 不动 ✅
       - 正文里的 `lesson-23`（无后缀纯提及）→ 无键命中 → 不动，交人工审阅 ✅
     不用正则切「路径 token」的原因：文件名里含全角标点（`、` `（）` `：`）时，
     按标点切词会把 basename 截断（`lesson-05-备份` / `恢复与灾备演练.md`），
     导致漏替换。字面量替换无此问题。
  3. 替换**按键长度降序**执行，避免 `01-x.md` 被更短的键重复处理，也避免前缀混淆。
  4. 遇到目标文件已存在（冲突）时**跳过并报警**，不覆盖任何文件。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# 要重命名的文件：basename 以 `lesson-<数字>-` 或 `lesson-<数字>.` 开头
FILE_RE = re.compile(r"^lesson-(\d+)-(.*)$")

# 参与引用替换的文本文件后缀
TEXT_EXTS = {
    ".md", ".svg", ".py", ".sh", ".sql", ".js", ".json",
    ".yml", ".yaml", ".txt", ".ts", ".go", ".toml",
}

# 跳过这些目录（版本控制 / 依赖 / 构建产物）
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".mypy_cache"}


def walk_files() -> list[Path]:
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(REPO):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            out.append(Path(dirpath) / fn)
    return out


def build_rename_map() -> tuple[dict[str, str], dict[Path, Path], list[str]]:
    """构建「旧 basename → 新 basename」映射与「旧路径 → 新路径」映射。"""
    basename_map: dict[str, str] = {}
    path_map: dict[Path, Path] = {}
    warnings: list[str] = []

    for path in walk_files():
        m = FILE_RE.match(path.name)
        if not m:
            continue
        new_name = f"{m.group(1)}-{m.group(2)}"
        new_path = path.with_name(new_name)

        if new_path.exists():
            warnings.append(f"冲突跳过（目标已存在）：{path.relative_to(REPO)} -> {new_name}")
            continue
        if new_name in basename_map:
            warnings.append(f"同名冲突：{new_name}（{path.relative_to(REPO)}）")
            continue

        basename_map[path.name] = new_name
        path_map[path] = new_path

    return basename_map, path_map, warnings


def replace_refs(text: str, basename_map: dict[str, str]) -> tuple[str, int]:
    """替换文本里对被重命名文件的引用（字面量全文替换）。

    键是「文件全名」，因此带路径引用与同目录裸文件名引用都能命中；
    不含映射键的文本（如目录段 `labs/lesson-09/`、纯提及 `lesson-23`）自然不动。
    按键长度降序执行，避免短键破坏长键的上下文。
    """
    count = 0
    for old in sorted(basename_map, key=len, reverse=True):
        if old in text:
            n = text.count(old)
            count += n
            text = text.replace(old, basename_map[old])
    return text, count


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="真正执行（默认仅预演）")
    args = ap.parse_args()

    basename_map, path_map, warnings = build_rename_map()
    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"=== {mode} ===")
    print(f"待重命名文件：{len(path_map)}")
    for w in warnings:
        print(f"  ⚠️  {w}")

    # ---- 引用替换 ----
    ref_total = 0
    touched: list[Path] = []
    for path in walk_files():
        if path.suffix.lower() not in TEXT_EXTS:
            continue
        # 已经排定重命名的文件，按新路径内容处理（内容不变，仅路径变）
        try:
            original = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        new_text, n = replace_refs(original, basename_map)
        if n:
            ref_total += n
            touched.append(path)
            if args.apply:
                path.write_text(new_text, encoding="utf-8")

    print(f"含引用的文件：{len(touched)} 个，共替换 {ref_total} 处")
    if not args.apply:
        print("\n--- 受影响文件（前 25）---")
        for p in touched[:25]:
            print(f"  {p.relative_to(REPO)}")
        if len(touched) > 25:
            print(f"  … 另有 {len(touched) - 25} 个")
        print("\n--- 重命名示例（前 15）---")
        for old, new in list(path_map.items())[:15]:
            print(f"  {old.relative_to(REPO)}\n    -> {new.name}")

    if not args.apply:
        print("\n预演结束。确认无误后加 --apply 执行。")
        return 0

    # ---- 执行重命名（自底向上，避免父目录先消失）----
    moved = 0
    for old, new in sorted(path_map.items(), key=lambda kv: len(str(kv[0])), reverse=True):
        if not old.exists():
            print(f"  ⚠️  源文件已不存在，跳过：{old.relative_to(REPO)}")
            continue
        old.rename(new)
        moved += 1
    print(f"\n已重命名 {moved} 个文件。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
