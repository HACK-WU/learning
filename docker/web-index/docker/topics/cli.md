# cli（Docker Docs · 共 40 条）

> 范围：`/reference/cli/docker/{container,image,volume,network,system,builder,buildx,compose}/` · 生成日期：2026-09-10
> **收录口径**：课程出现过的命令全收，其余按组给"总览入口 + 高频子命令"。完整子命令清单站点共 360 条（含 mcp/model/scout/dhi/desktop/sbx 等与课程无关分支，已排除）
> 单条命令的参数细节**本机 `docker <命令> --help` 更快**；本表用于"这条命令在官网哪一页 / 有没有这个子命令"

## 容器 container

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `docker run` 全部参数 | [docker container run](https://docs.docker.com/reference/cli/docker/container/run/) | #pull | run、参数 | [Running containers](https://docs.docker.com/engine/containers/run/) |
| 查 `docker ps` 输出与过滤 | [docker container ls](https://docs.docker.com/reference/cli/docker/container/ls/) | | ps、列表 | [过滤写法](https://docs.docker.com/engine/cli/filter/) |
| 查启停（`start`/`stop`/`restart`/`kill`） | [start](https://docs.docker.com/reference/cli/docker/container/start/) / [stop](https://docs.docker.com/reference/cli/docker/container/stop/) / [restart](https://docs.docker.com/reference/cli/docker/container/restart/) / [kill](https://docs.docker.com/reference/cli/docker/container/kill/) | | 启停 | |
| 讲 `exec` 与 `attach` 的区别 | [exec](https://docs.docker.com/reference/cli/docker/container/exec/) / [attach](https://docs.docker.com/reference/cli/docker/container/attach/) | | exec、attach、进容器 | |
| 查 `docker logs` 参数（--tail/--since/-f） | [docker container logs](https://docs.docker.com/reference/cli/docker/container/logs/) | | 日志 | [日志驱动](https://docs.docker.com/engine/logging/configure/) |
| 查 `docker inspect` 能取哪些字段 | [docker container inspect](https://docs.docker.com/reference/cli/docker/container/inspect/) | | inspect、元数据、退出码 | [格式化输出](https://docs.docker.com/engine/cli/formatting/) |
| 查 `docker stats` | [docker container stats](https://docs.docker.com/reference/cli/docker/container/stats/) | | 资源、监控 | [Runtime metrics](https://docs.docker.com/engine/containers/runmetrics/) |
| 查 `docker cp`（拷文件） | [docker container cp](https://docs.docker.com/reference/cli/docker/container/cp/) | | 拷文件 | |
| 查 `docker rm` / `prune`（删容器） | [rm](https://docs.docker.com/reference/cli/docker/container/rm/) / [prune](https://docs.docker.com/reference/cli/docker/container/prune/) | | 删除、清理 | [Prune 指南](https://docs.docker.com/engine/manage-resources/pruning/) |
| 查 `docker diff`（看文件系统改动） | [docker container diff](https://docs.docker.com/reference/cli/docker/container/diff/) | | diff、改动 | |
| 查 `docker top` / `port` / `update` / `wait` / `rename` | [top](https://docs.docker.com/reference/cli/docker/container/top/) / [port](https://docs.docker.com/reference/cli/docker/container/port/) / [update](https://docs.docker.com/reference/cli/docker/container/update/) / [wait](https://docs.docker.com/reference/cli/docker/container/wait/) / [rename](https://docs.docker.com/reference/cli/docker/container/rename/) | | 杂项 | |
| 查 commit / export / create / pause | [commit](https://docs.docker.com/reference/cli/docker/container/commit/) / [export](https://docs.docker.com/reference/cli/docker/container/export/) / [create](https://docs.docker.com/reference/cli/docker/container/create/) / [pause](https://docs.docker.com/reference/cli/docker/container/pause/) | | 杂项 | |

## 镜像 image

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `docker images` 与过滤 | [docker image ls](https://docs.docker.com/reference/cli/docker/image/ls/) | | 列表、虚悬镜像 | |
| 查 `docker pull`（含按 digest 拉） | [docker image pull](https://docs.docker.com/reference/cli/docker/image/pull/) | | 拉取、digest | [什么是 registry](https://docs.docker.com/get-started/docker-concepts/the-basics/what-is-a-registry/) |
| 查 `docker build` | [docker image build](https://docs.docker.com/reference/cli/docker/image/build/) | | 构建 | [buildx build](https://docs.docker.com/reference/cli/docker/buildx/build/) |
| 查 `docker history`（看分层与各层体积） | [docker image history](https://docs.docker.com/reference/cli/docker/image/history/) | | 分层、体积 | [镜像分层](https://docs.docker.com/get-started/docker-concepts/building-images/understanding-image-layers/) |
| 查 `docker tag` / `push` | [tag](https://docs.docker.com/reference/cli/docker/image/tag/) / [push](https://docs.docker.com/reference/cli/docker/image/push/) | | 打标签、推送 | [推送到 Hub](https://docs.docker.com/docker-hub/repos/manage/hub-images/push/) |
| 查 `docker save` / `load`（离线迁移） | [save](https://docs.docker.com/reference/cli/docker/image/save/) / [load](https://docs.docker.com/reference/cli/docker/image/load/) | | 导出、导入、离线 | |
| 查 `docker rmi` / `prune`（清镜像） | [rm](https://docs.docker.com/reference/cli/docker/image/rm/) / [prune](https://docs.docker.com/reference/cli/docker/image/prune/) | | 删除、虚悬 | |
| 查 `docker image inspect` | [docker image inspect](https://docs.docker.com/reference/cli/docker/image/inspect/) | | 元数据、digest | |

## 卷 volume / 网络 network

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查卷的 create/ls/inspect/rm/prune | [create](https://docs.docker.com/reference/cli/docker/volume/create/) / [ls](https://docs.docker.com/reference/cli/docker/volume/ls/) / [inspect](https://docs.docker.com/reference/cli/docker/volume/inspect/) / [rm](https://docs.docker.com/reference/cli/docker/volume/rm/) / [prune](https://docs.docker.com/reference/cli/docker/volume/prune/) | | 卷、持久化 | [Volumes](https://docs.docker.com/engine/storage/volumes/) |
| 查网络的 create/ls/inspect/connect/disconnect/rm | [create](https://docs.docker.com/reference/cli/docker/network/create/) / [ls](https://docs.docker.com/reference/cli/docker/network/ls/) / [inspect](https://docs.docker.com/reference/cli/docker/network/inspect/) / [connect](https://docs.docker.com/reference/cli/docker/network/connect/) / [disconnect](https://docs.docker.com/reference/cli/docker/network/disconnect/) / [rm](https://docs.docker.com/reference/cli/docker/network/rm/) | | 网络 | [网络总览](https://docs.docker.com/engine/network/) |

## 系统 system / builder

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `docker system df`（磁盘占用） | [docker system df](https://docs.docker.com/reference/cli/docker/system/df/) | | 磁盘、占用 | [Prune 指南](https://docs.docker.com/engine/manage-resources/pruning/) |
| 查 `docker system prune`（清理） | [docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/) | | 清理、prune | |
| 查 `docker info`（引擎全貌） | [docker system info](https://docs.docker.com/reference/cli/docker/system/info/) | | info、引擎信息 | |
| 查 `docker events`（事件流） | [docker system events](https://docs.docker.com/reference/cli/docker/system/events/) | | 事件、排障 | |
| 查构建缓存清理 `builder prune` | [docker builder prune](https://docs.docker.com/reference/cli/docker/builder/prune/) | | 构建缓存、清理 | [缓存 GC](https://docs.docker.com/build/cache/garbage-collection/) |
| 查 `docker builder build` | [docker builder build](https://docs.docker.com/reference/cli/docker/builder/build/) | | 构建 | |

## buildx（多平台 / 高级构建）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `buildx build`（含 --cache-to/--cache-from/--secret） | [docker buildx build](https://docs.docker.com/reference/cli/docker/buildx/build/) | | 构建、缓存、多平台 | [多平台构建](https://docs.docker.com/build/building/multi-platform/) |
| 查 `buildx create`（换 driver 用） | [docker buildx create](https://docs.docker.com/reference/cli/docker/buildx/create/) | | driver、builder | [docker-container 驱动](https://docs.docker.com/build/builders/drivers/docker-container/) |
| 查 `buildx bake` | [docker buildx bake](https://docs.docker.com/reference/cli/docker/buildx/bake/) | | bake | [Bake 介绍](https://docs.docker.com/build/bake/introduction/) |
| 查 buildx 其余子命令（ls/inspect/rm/use/prune/history/imagetools） | [buildx 总览](https://docs.docker.com/reference/cli/docker/buildx/) | | buildx | |

## compose（v2）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 `docker compose up` | [docker compose up](https://docs.docker.com/reference/cli/docker/compose/up/) | | 启动、up | [Quickstart](https://docs.docker.com/compose/gettingstarted/) |
| 查 `docker compose down`（含 -v 删卷风险） | [docker compose down](https://docs.docker.com/reference/cli/docker/compose/down/) | | 停止、删除、删卷 | |
| 查 `docker compose ps` / `logs` / `exec` | [ps](https://docs.docker.com/reference/cli/docker/compose/ps/) / [logs](https://docs.docker.com/reference/cli/docker/compose/logs/) / [exec](https://docs.docker.com/reference/cli/docker/compose/exec/) | | 状态、日志 | |
| 查 `docker compose config`（校验与展开） | [docker compose config](https://docs.docker.com/reference/cli/docker/compose/config/) | | 校验、展开 | |
| 查 `docker compose build` | [docker compose build](https://docs.docker.com/reference/cli/docker/compose/build/) | | 构建 | |
| 查启停重启（stop/start/restart） | [stop](https://docs.docker.com/reference/cli/docker/compose/stop/) / [start](https://docs.docker.com/reference/cli/docker/compose/start/) / [restart](https://docs.docker.com/reference/cli/docker/compose/restart/) | | 启停 | |
| 查 watch（热更新） | [docker compose watch](https://docs.docker.com/reference/cli/docker/compose/watch/) | | watch、热更新 | [Compose Watch](https://docs.docker.com/compose/how-tos/file-watch/) |
| 查 compose 全部子命令 | [compose 总览](https://docs.docker.com/reference/cli/docker/compose/) | | compose | |
