#!/usr/bin/env bash
# 卫生检查：列出 grafana/ 下全部文件，供三分类判定
set -u
cd /mnt/d/projects/learning/grafana || exit 1

echo "=== 1. 全部文件清单 ==="
find . -type f -not -path './.git/*' | sed 's#^\./##' | sort

echo
echo "=== 2. 目录总体积 ==="
du -sh . 2>/dev/null

echo
echo "=== 3. 典型过程残留扫描（依赖目录 / 缓存 / 日志 / 编译产物）==="
HITS=$(find . \( -name 'node_modules' -o -name '__pycache__' -o -name '.venv' \
     -o -name '*.pyc' -o -name '*.log' -o -name 'dist' -o -name 'build' \
     -o -name '*.tmp' \) -print 2>/dev/null)
if [ -z "$HITS" ]; then
  echo "  无命中 ✅"
else
  echo "$HITS"
fi

echo
echo "=== 4. 按类型统计 ==="
echo "  Markdown 文档: $(find . -name '*.md' -type f | wc -l) 个"
echo "  SVG 图表:      $(find . -name '*.svg' -type f | wc -l) 个"
echo "  Shell 脚本:    $(find . -name '*.sh' -type f | wc -l) 个"
echo "  Python 脚本:   $(find . -name '*.py' -type f | wc -l) 个"
echo "  YAML 配置:     $(find . -name '*.yml' -o -name '*.yaml' | wc -l) 个"

echo
echo "=== 5. 关键教学产物是否被 .gitignore 误伤（check-ignore 应无输出）==="
for f in 00-学习档案.md 00-评审清单.md 01-学习路径总览.md 02-课程目录.md \
         assets/learning-path-overview.svg \
         "stages/1-看得见/overview.md" \
         "stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md" \
         playground/l01-forms.py playground/prometheus.yml; do
  R=$(git -C /mnt/d/projects/learning check-ignore -v "grafana/$f" 2>/dev/null)
  if [ -n "$R" ]; then echo "  ❌ 被忽略: $f  <- $R"; else echo "  ✅ 未被忽略: $f"; fi
done
