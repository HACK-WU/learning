# 实现目录说明

本目录是结课项目的可运行部分。默认使用 `postgres:17`，Compose 项目名为
`pg-capstone`，对外端口为主库 `15432`、从库 `15434`。如果这两个端口冲突，复制
`.env.example` 为 `.env` 后修改 `PRIMARY_PORT` / `STANDBY_PORT`。

## 推荐顺序

```bash
bash scripts/up.sh
bash scripts/verify.sh
bash scripts/concurrency.sh
bash scripts/backup.sh
bash scripts/restore-logical.sh
bash scripts/pitr.sh
docker compose -p pg-capstone -f docker-compose.yml exec -T primary \
  psql -X -U postgres -d order_service -f /dev/stdin < sql/order-report.sql
docker compose -p pg-capstone -f docker-compose.yml exec -T primary \
  psql -X -U postgres -d order_service -f /dev/stdin < sql/monitor.sql
```

`runtime/` 是脚本生成的本地备份与运行数据，不是教学源码；不要提交。项目根目录
的 `.gitignore` 已为它保留路径规则。
