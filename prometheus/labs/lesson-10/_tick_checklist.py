import io
p = r"/mnt/d/projects/learning/prometheus/00-评审清单.md"
s = io.open(p, encoding="utf-8").read()
old = "- [ ] 阶段 4·课 10《基数治理》 — pedagogy + learner 双视角"
new = "- [x] 阶段 4·课 10《基数治理》 — pedagogy + learner 双视角（✅ 2026-09-07 完成，P0=0，详见下方评审记录表）"
if old in s:
    s = s.replace(old, new)
    io.open(p, "w", encoding="utf-8").write(s)
    print("checklist item ticked")
else:
    print("WARN: not found")
