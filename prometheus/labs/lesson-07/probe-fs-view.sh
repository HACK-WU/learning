#!/usr/bin/env bash
echo "=== bash 视角：目录是否存在 ==="
cd /d/projects/learning/prometheus || exit 1
ls -d labs 2>&1
echo "--- labs 内容 ---"
ls -1 labs 2>&1 | head -n 20
echo
echo "--- lesson-07 内容 ---"
ls -1 labs/lesson-07 2>&1 | head -n 40
echo
echo "=== 尝试写入测试 ==="
echo "test" > labs/lesson-07/_write_test.txt 2>&1 && echo "  写入成功" || echo "  写入失败"
ls -la labs/lesson-07/_write_test.txt 2>&1
rm -f labs/lesson-07/_write_test.txt 2>/dev/null
echo
echo "=== 当前工作目录 ==="
pwd
echo
echo "=== 用 python 再查一次（从 bash 内调用） ==="
python -c "
import os
b = r'D:/projects/learning/prometheus/labs/lesson-07'
print('exists:', os.path.exists(b))
print('cwd   :', os.getcwd())
"
