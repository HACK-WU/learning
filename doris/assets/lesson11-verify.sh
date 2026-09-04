#!/bin/bash
# 课 11 交付校验：检查正文与脚本的一致性、必备段落、实测数据是否齐全
PASS=0; FAIL=0
L=/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/lessons/lesson-11-日常运维SchemaChange备份与升级.md
A=/mnt/d/projects/learning/doris/assets
S=/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/assets

ck() { # ck "描述" "条件命令(返回0为通过)"
  if eval "$2" >/dev/null 2>&1; then echo "  [OK]   $1"; PASS=$((PASS+1));
  else echo "  [FAIL] $1"; FAIL=$((FAIL+1)); fi
}

echo "===== A. 文件存在性 ====="
ck "正文文件存在"               "test -f '$L'"
ck "SVG schemachange 存在"      "test -f '$S/lesson-11-schemachange.svg'"
ck "SVG summary 存在"           "test -f '$S/lesson-11-summary.svg'"
ck "setup 脚本存在"             "test -f '$A/lesson11-setup.sh'"
ck "step1 脚本存在"             "test -f '$A/lesson11-step1.sh'"
ck "step2 脚本存在"             "test -f '$A/lesson11-step2.sh'"
ck "step3 脚本存在"             "test -f '$A/lesson11-step3.sh'"
ck "cleanup 脚本存在"           "test -f '$A/lesson11-cleanup.sh'"

echo ""
echo "===== B. 必备段落 ====="
for s in "第一幕" "第二幕" "第三幕" "第四幕" "第五幕"; do
  ck "含 $s"                    "grep -q '$s' '$L'"
done
for s in "常见误区" "一图总结" "下一批接力提示词" "课程导航" "实验边界"; do
  ck "含 $s 段"                 "grep -q '$s' '$L'"
done
ck "含三个知识点标题"           "grep -q '知识点 1：Schema Change' '$L' && grep -q '知识点 2：备份与恢复' '$L' && grep -q '知识点 3：监控告警与集群升级' '$L'"
ck "含小测"                     "grep -qE '小测|自测|选择题' '$L'"
ck "含速览段"                   "grep -qE '速览|一页速览|本课速览' '$L'"

echo ""
echo "===== C. 边界标注（硬约束） ====="
ck "含已实测标记"               "grep -q '🟢' '$L'"
ck "含部分实测标记"             "grep -q '🟡' '$L'"
ck "含边界说明表"               "grep -q '实验边界' '$L'"
ck "提到了单机限制"             "grep -qE '单机|伪多节点' '$L'"

echo ""
echo "===== D. 实测数据一致性（正文 vs 脚本产出） ====="
ck "含 light 耗时范围 271-304"  "grep -q '271' '$L' && grep -q '304' '$L'"
ck "含 heavy ALTER 返回 108-143" "grep -q '108' '$L' && grep -q '143' '$L'"
ck "含 heavy FINISHED 1-3 秒"   "grep -qE '1[-–]3 秒' '$L'"
ck "含备份 17-18 秒"            "grep -qE '17[-–]18 秒' '$L'"
ck "含恢复 21 秒"               "grep -q '21 秒' '$L'"
ck "含数据指纹 1249998750000"   "grep -q '1249998750000' '$L'"
ck "含事故后 700000"            "grep -q '700000' '$L'"

echo ""
echo "===== E. 报错原文（硬约束：绝不能 grep 掉） ====="
ck "含 Unknown column 报错"     "grep -q 'Unknown column' '$L'"
ck "含 replication num 报错"    "grep -q 'replication num should be less than' '$L'"
ck "含 one backup or restore"   "grep -q 'Can only run one backup or restore job' '$L'"
ck "含 Shorten type length"     "grep -q 'Shorten type length is prohibited' '$L'"
ck "含 wider type 报错"         "grep -q 'Can not change from wider type' '$L'"
ck "含 Reorder stmt 报错"       "grep -q 'Reorder stmt should contains all columns' '$L'"
ck "含 partitioned table 报错"  "grep -q 'Only support change partitioned table' '$L'"
ck "含 not under SCHEMA_CHANGE" "grep -q 'not under SCHEMA_CHANGE' '$L'"
ck "含 default value 报错"      "grep -q 'Can not change default value' '$L'"
ck "含 key column 顺序报错"     "grep -q 'Cannot add key column' '$L'"
ck "含 missing backup_timestamp" "grep -q 'Missing backup_timestamp property' '$L'"
ck "含 DROP SNAPSHOT 不存在"     "grep -q 'no viable alternative at input' '$L'"
ck "含 IF NOT EXISTS 报错"      "grep -qE 'mismatched input .IF.' '$L'"

echo ""
echo "===== F. 脚本可运行性（正文命令与脚本一致） ====="
ck "正文提 setup 脚本"          "grep -q 'lesson11-setup.sh' '$L'"
ck "正文提 step1 脚本"          "grep -q 'lesson11-step1.sh' '$L'"
ck "正文提 step2 脚本"          "grep -q 'lesson11-step2.sh' '$L'"
ck "正文提 step3 脚本"          "grep -q 'lesson11-step3.sh' '$L'"
ck "正文提 cleanup 脚本"        "grep -q 'lesson11-cleanup.sh' '$L'"
ck "脚本里没有（同上）省略"     "! grep -qE '同上|列定义同上' '$A/lesson11-setup.sh' '$A/lesson11-step1.sh' '$A/lesson11-step2.sh' '$A/lesson11-step3.sh'"
ck "docker exec 都带 -i"        "! grep -nE 'docker exec [^-]*mysql' '$A/lesson11-'*.sh"
# 注：接力提示词段落里会引用"禁止（同上）"这条规范本身，需排除后再检查
ck "正文命令区无省略写法"     "sed '/下一批接力提示词/,\$d' '$L' | grep -qvE '列定义同上|（同上）|\\(同上\\)'"
ck "正文无占位省略号 DDL"      "! grep -qE '\\.\\.\\. [0-9]+ 列 \\.\\.\\.' '$L'"

echo ""
echo "===== G. 图与引用 ====="
ck "正文引用 schemachange SVG"  "grep -q 'lesson-11-schemachange.svg' '$L'"
ck "正文引用 summary SVG"       "grep -q 'lesson-11-summary.svg' '$L'"
ck "SVG schemachange 合法"      "head -1 '$S/lesson-11-schemachange.svg' | grep -q '<svg'"
ck "SVG summary 合法"           "head -1 '$S/lesson-11-summary.svg' | grep -q '<svg'"

echo ""
echo "===== H. 正文质量 ====="
LINES=$(wc -l < "$L")
ck "正文行数 >= 900 ($LINES)"   "test $LINES -ge 900"
ck "含 COUNT(*) 陷阱提醒"       "grep -q 'COUNT' '$L' && grep -q '元数据' '$L'"
ck "含数值浮动说明"             "grep -qE '看趋势|看倍数|每次都不同|浮动' '$L'"
ck "含 light_schema_change 默认值说明" "grep -q 'light_schema_change' '$L'"

echo ""
echo "=============================="
echo "  PASS = $PASS   FAIL = $FAIL"
echo "=============================="
if [ $FAIL -eq 0 ]; then echo "VERIFY_OK"; else echo "VERIFY_FAIL"; exit 1; fi
