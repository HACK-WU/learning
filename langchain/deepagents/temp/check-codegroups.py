#!/usr/bin/env python3
"""Deep Agents 教程双语言化 · code-group 围栏校验器。

用途：对改造后的 Markdown 文件做机械校验——
  1. `::: code-group` 与 `:::` 配对是否平衡（含嵌套计数）；
  2. 每个 code-group 内是否至少 2 个代码块、且 [Python] / [TypeScript] 标签齐全；
  3. 列出 code-group 之外的全部代码围栏（tag + 首行），供人工审查是否遗漏转换。

用法：
    python3 check-codegroups.py <file1.md> [file2.md ...]
    python3 check-codegroups.py --all   # 扫描 langchain/deepagents 下所有 md

退出码：0 通过；1 有错误。
"""

import re
import sys
from pathlib import Path

FENCE_OPEN = re.compile(r"^(`{3,}|~{3,})(.*)$")
GROUP_OPEN = re.compile(r"^:::\s*code-group\s*$")
GROUP_CLOSE = re.compile(r"^:::\s*$")
TAG = re.compile(r"\[([^\]]+)\]")

ROOT = Path("/root/learning/langchain/deepagents")
EXCLUDE_PARTS = {"web-index", "assets", "node_modules", "playground-ts"}


def check_file(path):
    errors = []
    lines = path.read_text(encoding="utf-8").splitlines()

    depth = 0
    group_start = 0
    group_tags = []

    in_fence = False
    fence_char = ""
    fence_indent = 0
    fence_tag = ""
    fence_start = 0
    fence_outside = []

    for i, line in enumerate(lines, 1):
        m = FENCE_OPEN.match(line)
        if not in_fence and m and not line.strip() == "":
            fence_char = m.group(1)[0]
            fence_indent = len(line) - len(line.lstrip())
            in_fence = True
            fence_tag = m.group(1) + m.group(2).strip()
            fence_start = i
            if depth == 0:
                fence_outside.append((i, fence_tag))
            else:
                tag_m = TAG.search(m.group(2))
                if tag_m:
                    group_tags.append(tag_m.group(1))
            continue
        if in_fence:
            stripped = line.lstrip()
            indent_ok = len(line) - len(stripped) <= fence_indent
            if indent_ok and re.fullmatch(re.escape(fence_char) + r"{3,}", stripped.strip()):
                in_fence = False
            continue

        if GROUP_OPEN.match(line):
            if depth == 0:
                group_start = i
                group_tags = []
            depth += 1
            continue
        if GROUP_CLOSE.match(line):
            if depth == 1:
                tags = list(group_tags)
                if len(tags) < 2:
                    errors.append(f"L{group_start}: code-group 内代码块少于 2 个（tags={tags}）")
                elif not any("Python" in t for t in tags):
                    errors.append(f"L{group_start}: code-group 缺少 [Python] 标签（tags={tags}）")
                elif not any("TypeScript" in t for t in tags):
                    errors.append(f"L{group_start}: code-group 缺少 [TypeScript] 标签（tags={tags}）")
                depth = 0
                group_tags = []
            elif depth > 1:
                depth -= 1
            else:
                errors.append(f"L{i}: 出现多余的 ::: 闭合")
            continue

    if in_fence:
        errors.append(f"L{fence_start}: 代码围栏未闭合（{fence_tag[:40]}）")
    if depth:
        errors.append(f"L{group_start}: code-group 未闭合")

    return errors, fence_outside


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    if sys.argv[1] == "--all":
        files = sorted(
            p
            for p in ROOT.rglob("*.md")
            if not any(part in EXCLUDE_PARTS for part in p.parts)
        )
    else:
        files = [Path(a) for a in sys.argv[1:]]

    total_err = 0
    for f in files:
        rel = f.relative_to(ROOT) if str(f).startswith(str(ROOT)) else f
        errors, outside = check_file(f)
        total_err += len(errors)
        print(f"\n=== {rel} ===")
        if errors:
            for e in errors:
                print(f"  [ERR] {e}")
        else:
            print("  [OK] code-group 配对与标签检查通过")
        if outside:
            print(f"  -- code-group 之外的围栏 {len(outside)} 处（人工审查是否需转换）--")
            for ln, tag in outside:
                print(f"     L{ln}: {tag[:60]}")
    print(f"\n总计错误：{total_err}")
    sys.exit(1 if total_err else 0)


if __name__ == "__main__":
    main()
