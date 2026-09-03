#!/bin/bash
# 修正：课 9 被误勾选（因含「容量」关键词）
F='/mnt/d/projects/learning/victoriametrics/00-学习档案.md'
grep -n '课 9' "$F" | head -5
