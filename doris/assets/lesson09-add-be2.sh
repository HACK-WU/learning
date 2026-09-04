#!/bin/bash
# 课 9：在同一个容器内拉起第二个 BE 进程
# 用法：bash lesson09-add-be2.sh
#
# 背景：课 9 讲扩缩容/均衡/副本，都需要多节点。学习环境原本只有 1 台 BE，
#       本脚本在同一个 Doris 容器里用不同端口再拉起一个 BE 进程，
#       把集群从 1 FE + 1 BE 变成 1 FE + 2 BE。
#
# ⚠️ 重要限制：两个 BE 的 host 都是 127.0.0.1（同一台物理机），
#    因此 Doris 的反亲和规则会拒绝在同一台机器上放同一个 tablet 的两个副本。
#    报错原文：Failed to find enough backend ... or maybe all be on same host
#    所以"多副本扛宕机"无法真实验证，但扩缩容/数据均衡/宕机自愈都能实测。

set -e

CONTAINER="doris-learn"

echo "=========================================="
echo " 课 9：拉起第二个 BE（伪多节点）"
echo "=========================================="

echo ""
echo "========== 步骤 1：检查容器运行状态 =========="
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
  echo "❌ 容器 $CONTAINER 没在运行"
  exit 1
fi
echo "✅ 容器 $CONTAINER 运行中"

echo ""
echo "========== 步骤 2：检查是否已经有 BE2 =========="
EXIST=$(docker exec -i $CONTAINER mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -c "19050" || true)
if [ "$EXIST" != "0" ]; then
  echo "⚠️ 端口 19050 已在 BE 列表中，可能 BE2 已注册过"
  docker exec -i $CONTAINER mysql -h 127.0.0.1 -P 9030 -uroot \
    -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
    | grep -E "BackendId|HeartbeatPort|Alive"
  echo ""
  echo "如果 Alive=false，继续往下走（本脚本会重新启动进程）"
fi

echo ""
echo "========== 步骤 3：准备 BE2 目录 =========="
echo "（如果已存在会保留，只做增量补齐）"
docker exec $CONTAINER bash -c "
mkdir -p /opt/be2/conf /opt/be2/log /opt/be2/storage
# lib 用软链指回原 BE 的 lib，避免复制 4GB 二进制
if [ ! -e /opt/be2/lib ]; then
  ln -sfn /opt/apache-doris/be/lib /opt/be2/lib
fi
if [ ! -d /opt/be2/bin ]; then
  cp -r /opt/apache-doris/be/bin /opt/be2/bin
fi
echo '目录就绪'
ls /opt/be2/
"

echo ""
echo "========== 步骤 4：写 BE2 配置（改端口 + 独立存储路径）=========="
docker exec $CONTAINER bash -c "
if [ ! -f /opt/be2/conf/be.conf ]; then
  cp /opt/apache-doris/be/conf/be.conf /opt/be2/conf/be.conf
fi
cd /opt/be2/conf
# 端口全部 +10000，避开原 BE
sed -i 's/^be_port = 9060/be_port = 19060/' be.conf
sed -i 's/^webserver_port = 8040/webserver_port = 18040/' be.conf
sed -i 's/^heartbeat_service_port = 9050/heartbeat_service_port = 19050/' be.conf
sed -i 's/^brpc_port = 8060/brpc_port = 18060/' be.conf
sed -i 's/^arrow_flight_sql_port = 8050/arrow_flight_sql_port = 18050/' be.conf
# 日志目录指向 be2 自己
sed -i 's#\\\${DORIS_HOME}/log/#/opt/be2/log/#' be.conf
# 存储路径独立（关键：不能和原 BE 共用，否则数据目录冲突）
grep -q '^storage_root_path' be.conf || echo 'storage_root_path = /opt/be2/storage' >> be.conf
echo '--- 关键配置确认 ---'
grep -E '^be_port|^webserver_port|^heartbeat_service_port|^brpc_port|^arrow_flight_sql_port|^storage_root_path' be.conf
"

echo ""
echo "========== 步骤 5：生成 CLASSPATH 文件 =========="
echo "⚠️ 关键踩坑：不能用 *.jar 通配符，JVM 不识别，会 SIGSEGV。"
echo "   必须先拼好完整 classpath 存成文件，启动时读取。"
docker exec $CONTAINER bash -c '
CP="/opt/be2/conf/::"
CP="$CP:/opt/be2/lib/java_extensions/preload-extensions/preload-extensions-jar-with-dependencies.jar"
CP="$CP:/opt/be2/lib/java_extensions/java-udf/java-udf-jar-with-dependencies.jar"
CP="$CP:/opt/be2/lib/hadoop_hdfs/hadoop-deps.jar"
for j in /opt/be2/lib/hadoop_hdfs/lib/*.jar; do CP="$CP:$j"; done
echo "$CP" > /opt/be2/conf/classpath.txt
echo "classpath 已生成，长度 = $(wc -c < /opt/be2/conf/classpath.txt) 字节"
'

echo ""
echo "========== 步骤 6：生成启动脚本 launch.sh =========="
cat > /tmp/be2launch.sh <<'OUTER'
#!/bin/bash
export DORIS_HOME=/opt/be2
export JAVA_HOME=/usr/lib/jvm/java
export PATH=/usr/lib/jvm/java/bin:$PATH
# ⚠️ 关键：LD_LIBRARY_PATH 必须含 JVM 的 lib/server，否则 libjvm.so 找不到
export LD_LIBRARY_PATH=/opt/be2/lib/hadoop_hdfs/native:/usr/lib/jvm/java/lib/server:/usr/lib/jvm/java/lib:
export LOG_DIR=/opt/be2/log/
export PID_DIR=/opt/be2/bin
export PPROF_TMPDIR=/opt/be2/log/
export ODBCSYSINI=/opt/be2/conf
export SKIP_CHECK_ULIMIT=true
export TZ=UTC
export LANG=C.UTF-8
export AWS_EC2_METADATA_DISABLED=true

CP=$(cat /opt/be2/conf/classpath.txt)
export CLASSPATH="$CP"
export DORIS_CLASSPATH="-Djava.class.path=$CP"

export JAVA_OPTS="-Dfile.encoding=UTF-8 -Djol.skipHotspotSAAttach=true -Xmx1024m -DlogPath=/opt/be2/log/jni.log -Djavax.security.auth.useSubjectCredsOnly=false -Djava.security.krb5.debug=true -Dsun.java.command=DorisBE -XX:-CriticalJNINatives -XX:+IgnoreUnrecognizedVMOptions -Darrow.enable_null_check_for_get=false"
export JAVA_OPTS_FOR_JDK_17="$JAVA_OPTS"
export LIBHDFS_OPTS="$JAVA_OPTS"

export JEMALLOC_CONF="percpu_arena:percpu,background_thread:true,metadata_thp:auto,muzzy_decay_ms:5000,dirty_decay_ms:5000,oversize_threshold:0,prof:true,prof_active:false,lg_prof_interval:-1,lg_extent_max_active_fit:8,prof_prefix:/opt/be2/log/jemalloc_heap_profile_"
export MALLOC_CONF="$JEMALLOC_CONF"

cd /opt/be2
nohup /opt/be2/lib/doris_be >> /opt/be2/log/be.out 2>&1 &
echo "launched pid=$!"
OUTER

docker cp /tmp/be2launch.sh $CONTAINER:/opt/be2/launch.sh
docker exec $CONTAINER bash -c "chmod +x /opt/be2/launch.sh; echo 'launch.sh 已就位'"

echo ""
echo "========== 步骤 7：启动 BE2 =========="
echo "⚠️ 注意：不能直接用 start_be.sh —— 它的 pidfile 检查会误判原 BE 进程"
echo "   （报 'Backend is already running as process 2063'），必须直接拉二进制"
docker exec -d $CONTAINER bash /opt/be2/launch.sh
echo "等待 35 秒让 BE2 启动..."
sleep 35

echo ""
echo "--- BE 进程列表（应看到两个 doris_be）---"
docker exec $CONTAINER bash -c "ps aux | grep '[d]oris_be' | awk '{print \$2, \$11}'"

echo ""
echo "--- BE2 健康检查 ---"
docker exec $CONTAINER bash -c "curl -s -m 5 http://127.0.0.1:18040/api/health; echo"

echo ""
echo "========== 步骤 8：把 BE2 注册进集群 =========="
docker exec -i $CONTAINER mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "ALTER SYSTEM ADD BACKEND '127.0.0.1:19050';" 2>&1 \
  | grep -vE "^Warning|Using a password" || echo "（若报 Same backend already exists 说明已注册过，正常）"

echo ""
echo "等待 20 秒让心跳生效..."
sleep 20

echo ""
echo "========== 步骤 9：确认双节点 =========="
docker exec -i $CONTAINER mysql -h 127.0.0.1 -P 9030 -uroot \
  -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" \
  | grep -E "BackendId|Host|HeartbeatPort|Alive|TabletNum|ErrMsg"

echo ""
echo "=========================================="
echo " 完成。现在集群是 1 FE + 2 BE。"
echo ""
echo " ⚠️ 但两台 BE 的 host 都是 127.0.0.1（同一台物理机），"
echo "    反亲和规则会拒绝在同一台机器上放同一 tablet 的两个副本。"
echo "    报错：Failed to find enough backend ... or maybe all be on same host"
echo ""
echo " 能实测：扩缩容、数据均衡、宕机自愈（bash lesson09-step4.sh / step5.sh）"
echo " 不能实测：多副本扛宕机（只能原理推演 + 单副本宕机反证）"
echo "=========================================="
