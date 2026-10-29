#!/usr/bin/env python3
"""校验 web-index 两份索引的准确性。"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(os.path.dirname(HERE), "web-index")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SIDES = {
    "docs-managed-deep-agents": ("python", os.path.join(HERE, "mda-py-urls.txt")),
    "docs-managed-deep-agents-js": ("javascript", os.path.join(HERE, "mda-ts-urls.txt")),
}
URL_RE = re.compile(r"https://docs\.langchain\.com/langsmith/(?:python|javascript)/managed-deep-agents[a-z0-9-]*")


def main():
    problems = []
    for slug, (lang, official_file) in SIDES.items():
        official = {u.strip().removesuffix(".md") for u in open(official_file) if u.strip()}
        print(f"\n===== {slug} (official {len(official)}) =====")
        tdir = os.path.join(BASE, slug, "topics")
        collected = set()
        for name in sorted(os.listdir(tdir)):
            if not name.endswith(".md"):
                continue
            text = open(os.path.join(tdir, name), encoding="utf-8").read()
            urls = {u for u in URL_RE.findall(text) if f"/{lang}/" in u}
            rows = [ln for ln in text.splitlines() if ln.startswith("| ") and "https://" in ln]
            claimed = re.search(r"（(\d+) 条", text.splitlines()[0])
            cn = int(claimed.group(1)) if claimed else None
            status = "OK" if cn == len(rows) else f"MISMATCH claimed={cn} rows={len(rows)}"
            print(f"  {name}: claimed {cn} / rows {len(rows)} / uniqURL {len(urls)} -> {status}")
            if cn != len(rows):
                problems.append(f"{slug}/{name}: claimed {cn} vs rows {len(rows)}")
            if len(urls) != len(rows):
                problems.append(f"{slug}/{name}: duplicate URLs ({len(rows)} rows / {len(urls)} urls)")
            collected |= urls
        print(f"  collected {len(collected)} / official {len(official)}")
        for u in sorted(official - collected):
            print(f"    MISSING {u}")
            problems.append(f"{slug}: missing {u}")
        for u in sorted(collected - official):
            print(f"    EXTRA {u}")
            problems.append(f"{slug}: extra {u}")
        idx = open(os.path.join(BASE, slug, "index.md"), encoding="utf-8").read()
        m = re.search(r"条目数：(\d+)", idx)
        print(f"  index.md claims {m.group(1) if m else 'none'}")
        if m and int(m.group(1)) != len(official):
            problems.append(f"{slug}/index.md: claims {m.group(1)} vs official {len(official)}")
    print("\n===== RESULT =====")
    if problems:
        print(f"{len(problems)} problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1
    print("ALL PASS: counts consistent, URLs match official list exactly, no dup, no gap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
