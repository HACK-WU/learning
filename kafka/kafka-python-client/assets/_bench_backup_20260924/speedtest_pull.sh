#!/bin/bash
# 测真实镜像下载速率：拉一个未缓存的小镜像计时
# 目的：判断 1.5GB 的 Confluent SR 镜像是否现实可拉
set -u
docker rmi alpine:3.18 >/dev/null 2>&1
echo "拉取 alpine:3.18（约 3MB）测速..."
start=$(date +%s)
docker pull alpine:3.18 >/dev/null 2>&1
rc=$?
end=$(date +%s)
dur=$(( end - start ))
echo "退出码: $rc  耗时: ${dur} 秒"
if [ "$dur" -gt 0 ]; then
    rate=$(( 3 / dur ))
    echo "速率约: ${rate} MB/s（粗略）"
    echo "按此速率，1.5GB 的 SR 镜像需要: $(( 1500 / (rate > 0 ? rate : 1) / 60 )) 分钟"
fi
