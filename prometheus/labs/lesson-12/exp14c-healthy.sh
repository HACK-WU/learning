#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
mkdir -p $D/httpcfg

# promtool 的 http.config.file 格式（不是 prometheus 的 scrape config）
cat > $D/httpcfg/client.yml <<'YML'
http_client_config:
  # 无鉴权，仅指定目标相关设置
YML

echo "===== 尝试 1：仅 --http.config.file（看它连哪里） ====="
docker run --rm --network $NET -v $D/httpcfg:/h --entrypoint promtool prom/prometheus:v3.14.0 \
  check healthy --http.config.file=/h/client.yml 2>&1 | head -5

echo
echo "===== 结论：healthy/ready 需要远端地址，实际靠 http.config.file 里的配置 ====="
echo "实测：直接传 URL → 'unexpected <url>' 报错"
echo "      --help 只列出 --http.config.file，无 <server> 位置参数"
echo "      与 query instant <server> <expr> 不同 —— 后者明确接受 server 参数"
echo
echo "===== 对照：query instant 确实接受 server ====="
docker run --rm --network $NET --entrypoint promtool prom/prometheus:v3.14.0 \
  query instant http://l12-prom2:9090 'up' 2>&1 | head -5
