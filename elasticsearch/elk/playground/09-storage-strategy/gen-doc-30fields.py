#!/usr/bin/env python3
# 课 10 知识点 10.3：生成「字段爆炸」演示用的文档（30 个自定义字段）
import json

doc = {"@timestamp": "2026-09-07T22:40:00Z", "message": "field explosion demo"}
for i in range(30):
    doc[f"custom.field_{i}"] = f"value-{i}"

with open("doc-30fields.json", "w") as f:
    json.dump(doc, f, ensure_ascii=False)
print("生成 doc-30fields.json，字段数 =", len(doc))
