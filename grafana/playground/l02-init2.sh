#!/usr/bin/env bash
# 课 2 知识点 2.1 实验（第二段）：环境变量改密 / 持久化 / health 与插件的时序差
set -u
NET="grafana-net"

echo "########## 实验 A：GF_SECURITY_ADMIN_PASSWORD 是否生效 ##########"
docker rm -f gf-l02c >/dev/null 2>&1
docker run -d --name gf-l02c --network $NET -p 3013:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD='lab-pass-2026' \
  grafana/grafana:13.2.1 >/dev/null
for i in $(seq 1 60); do
  curl -s "http://localhost:3013/api/health" 2>/dev/null | grep -q '"database": "ok"' && break
  sleep 1
done
echo "  已就绪（t+${i}s 量级）"
echo -n "  A1 用『旧默认口令 admin/admin』登录 -> "
curl -s -X POST "http://localhost:3013/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"admin"}' -w ' [HTTP %{http_code}]\n'
echo -n "  A2 用『环境变量指定口令』登录   -> "
curl -s -X POST "http://localhost:3013/login" -H 'Content-Type: application/json' \
  -d '{"user":"admin","password":"lab-pass-2026"}' -w ' [HTTP %{http_code}]\n'

echo
echo "########## 实验 B：health 就绪 vs 插件装完，谁先谁后 ##########"
echo "  在 gf-l02b 上重放（它此前已就绪）："
echo -n "    health 返回: "
curl -s "http://localhost:3012/api/health" | tr -d '\n ' ; echo
echo -n "    已装插件数: "
docker exec gf-l02b ls -1 /var/lib/grafana/plugins 2>/dev/null | wc -l
echo "    插件安装日志时间线："
docker logs gf-l02b 2>&1 | grep -E 'Plugin successfully installed|Starting Grafana' \
  | sed -E 's/.*t=([0-9T:.Z-]+).*(Starting Grafana|Plugin successfully installed).*(pluginId=([a-z-]+))?.*/    \1  \2 \4/' | head -8

echo
echo "########## 实验 C：不挂卷的持久化后果 ##########"
curl -s -c /tmp/l02c_ck.txt -X POST "http://localhost:3013/login" \
  -H 'Content-Type: application/json' -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null
echo -n "  C1 建一个数据源 -> "
DS=$(curl -s -b /tmp/l02c_ck.txt -X POST "http://localhost:3013/api/datasources" \
  -H 'Content-Type: application/json' \
  -d '{"name":"PersistTest","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy","isDefault":false}')
echo "$DS" | head -c 200; echo
echo -n "  C2 容器内数据源数: "
curl -s -b /tmp/l02c_ck.txt "http://localhost:3013/api/datasources" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d), [x['name'] for x in d])" 2>/dev/null

echo "  C3 停掉容器、用同一镜像再起一个『全新』容器（模拟换机器/重建容器）"
docker rm -f gf-l02c >/dev/null 2>&1
docker run -d --name gf-l02c --network $NET -p 3013:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD='lab-pass-2026' \
  grafana/grafana:13.2.1 >/dev/null
for i in $(seq 1 60); do
  curl -s "http://localhost:3013/api/health" 2>/dev/null | grep -q '"database": "ok"' && break
  sleep 1
done
curl -s -c /tmp/l02c_ck2.txt -X POST "http://localhost:3013/login" \
  -H 'Content-Type: application/json' -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null
echo -n "     新容器里数据源数: "
curl -s -b /tmp/l02c_ck2.txt "http://localhost:3013/api/datasources" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d), [x['name'] for x in d])" 2>/dev/null
echo "     （上一步的 PersistTest 若消失，即证明『不挂卷＝配置随容器销毁』）"

echo
echo "########## 实验 D：挂卷后是否真的持久 ##########"
docker rm -f gf-l02d >/dev/null 2>&1
docker volume rm gf-l02d-vol >/dev/null 2>&1
docker volume create gf-l02d-vol >/dev/null
docker run -d --name gf-l02d --network $NET -p 3014:3000 \
  -v gf-l02d-vol:/var/lib/grafana \
  -e GF_SECURITY_ADMIN_PASSWORD='lab-pass-2026' \
  grafana/grafana:13.2.1 >/dev/null
for i in $(seq 1 60); do
  curl -s "http://localhost:3014/api/health" 2>/dev/null | grep -q '"database": "ok"' && break
  sleep 1
done
curl -s -c /tmp/l02d_ck.txt -X POST "http://localhost:3014/login" \
  -H 'Content-Type: application/json' -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null
curl -s -b /tmp/l02d_ck.txt -X POST "http://localhost:3014/api/datasources" \
  -H 'Content-Type: application/json' \
  -d '{"name":"VolTest","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy"}' >/dev/null
echo -n "  D1 建数据源后查询: "
curl -s -b /tmp/l02d_ck.txt "http://localhost:3014/api/datasources" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d), [x['name'] for x in d])" 2>/dev/null
echo "  D2 删容器、用同一卷重建"
docker rm -f gf-l02d >/dev/null 2>&1
docker run -d --name gf-l02d --network $NET -p 3014:3000 \
  -v gf-l02d-vol:/var/lib/grafana \
  -e GF_SECURITY_ADMIN_PASSWORD='lab-pass-2026' \
  grafana/grafana:13.2.1 >/dev/null
for i in $(seq 1 60); do
  curl -s "http://localhost:3014/api/health" 2>/dev/null | grep -q '"database": "ok"' && break
  sleep 1
done
curl -s -c /tmp/l02d_ck2.txt -X POST "http://localhost:3014/login" \
  -H 'Content-Type: application/json' -d '{"user":"admin","password":"lab-pass-2026"}' >/dev/null
echo -n "     重建后数据源: "
curl -s -b /tmp/l02d_ck2.txt "http://localhost:3014/api/datasources" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d), [x['name'] for x in d])" 2>/dev/null
