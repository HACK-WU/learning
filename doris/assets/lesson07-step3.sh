#!/bin/bash
# 课 7 步骤 3：读 Profile 的三层结构
OUT=/tmp/loadlab
mkdir -p $OUT

runq() {
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$1" 2>&1 \
    | grep -vE "^Warning|Using a password"
}
getprof() {
  docker exec doris-learn curl -s -u root: "http://127.0.0.1:8030/api/profile?query_id=$1" \
    | sed -e 's/\\n/\n/g' -e 's/\\"/"/g' -e 's/^.*"profile":"//' -e 's/"}}$//'
}

echo "########## 跑目标查询并抓 Profile ##########"
runq "SET enable_profile = true;
      SELECT COUNT(*) AS c, ROUND(SUM(LENGTH(pad1)+LENGTH(pad2)+LENGTH(pad3)),2) AS t
      FROM perf_wide;"
runq "SHOW QUERY PROFILE '/';" > $OUT/list.txt
QID=$(grep 'LENGTH' $OUT/list.txt | grep -oE '[0-9a-f]{16}-[0-9a-f]{16}' | head -1)
echo "QueryID = $QID"
if [ -z "$QID" ]; then echo "!!! 没抓到 QueryID，检查 enable_profile"; exit 1; fi
getprof "$QID" > $OUT/prof.txt
echo "Profile 正文行数: $(wc -l < $OUT/prof.txt)"

echo ""
echo "########## 第 1 层：Execution Summary（计划 vs 执行）##########"
sed -n '/Execution Summary:/,/^ChangedSessionVariables/p' $OUT/prof.txt \
  | grep -E "Parse SQL Time|Plan Time|Schedule Time|Wait and Fetch|Fetch Result Time|Total:|Instances Num|Parallel Fragment" \
  | sed 's/^ */    /'

echo ""
echo "########## 第 2 层：Fragment / Pipeline 结构 ##########"
grep -E "^ *Fragment [0-9]:|Pipeline [0-9]\(instance_num|OPERATOR\(" $OUT/prof.txt | head -30 | sed 's/^ */    /'

echo ""
echo "########## 第 3 层：各算子的 ExecTime 排行榜 ##########"
grep -E "OPERATOR\(|ExecTime: avg" $OUT/prof.txt | paste - - 2>/dev/null \
  | sed 's/[A-Z_]*OPERATOR(nereids_id=[0-9]*. //' | head -14 | sed 's/^ */    /'

echo ""
echo "########## 等待链：谁在等谁 ##########"
grep -oE "WaitForDependency\[[A-Z_]+\]Time: avg [0-9.]+(ns|us|ms)" $OUT/prof.txt \
  | sort -t' ' -k3 -rn | head -8 | uniq | sed 's/^ */    /'

echo "STEP3_DONE"
