#!/usr/bin/env bash
# 课 7《持久化与死信》环境脚本：统一 docker / Python 调用方式与连接参数
# 与课 3~6 保持一致：容器 rabbitmq-learn，用户 learn/learn123，AMQP 5672，管理端口 15672
export PYTHONIOENCODING=utf-8

# docker 在 Git Bash 下的真实路径（PowerShell 的 PATH 里没有）
DOCKER="$(command -v docker 2>/dev/null || echo /usr/bin/docker)"

# 容器与凭据
RMQ_CT="${RMQ_CT:-rabbitmq-learn}"
RMQ_USER="${RMQ_USER:-learn}"
RMQ_PASS="${RMQ_PASS:-learn123}"

# 宿主机侧连接参数（Python 脚本用）
export RMQ_HOST="${RMQ_HOST:-127.0.0.1}"
export RMQ_PORT="${RMQ_PORT:-5672}"
export RMQ_USER RMQ_PASS
export RMQ_API="http://127.0.0.1:15672/api"

# 常用别名
rq()   { "$DOCKER" exec "$RMQ_CT" rabbitmqctl "$@"; }
radm() { "$DOCKER" exec -e RABBITMQADMIN_USERNAME="$RMQ_USER" \
                        -e RABBITMQADMIN_PASSWORD="$RMQ_PASS" \
                        "$RMQ_CT" rabbitmqadmin "$@"; }

# 用于 HTTP API（容器内 rabbitmqadmin/CLI 自带 curl 不可用，统一走宿主机 curl）
api()  { curl -s -u "$RMQ_USER:$RMQ_PASS" "$@"; }

echo "[l7-env] 容器=$RMQ_CT 用户=$RMQ_USER AMQP=$RMQ_HOST:$RMQ_PORT API=$RMQ_API"
