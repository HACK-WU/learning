# reference（Docker Docs · 共 18 条）

> 范围：`/reference/` 中的 Dockerfile、术语表、build-checks、dockerd、Engine API · 生成日期：2026-09-10
> 收录口径：只收**总览/概念级**页面。API 各版本子页（v1.40–v1.56，共 17 条）与 build-checks 单条规则页（21 条）不逐条入库，需要时按下方规律页进入

## Dockerfile 与术语

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 Dockerfile 每条指令（FROM/RUN/COPY/CMD/ENTRYPOINT/ENV/ARG…） | [Dockerfile 参考](https://docs.docker.com/reference/dockerfile/) | #run | Dockerfile、指令 | [Dockerfile 概述](https://docs.docker.com/build/concepts/dockerfile/) |
| 查 `RUN --mount` 用法（缓存/密钥挂载） | [Dockerfile · RUN --mount](https://docs.docker.com/reference/dockerfile/) | #run---mount | RUN、mount、secret、cache | [Build secrets](https://docs.docker.com/build/building/secrets/) |
| 查 `COPY --link` / `--from` 等细节 | [Dockerfile · COPY](https://docs.docker.com/reference/dockerfile/) | #copy | COPY、--from | [多阶段构建](https://docs.docker.com/build/building/multi-stage/) |
| 查 CMD 与 ENTRYPOINT 的组合规则 | [Dockerfile · ENTRYPOINT](https://docs.docker.com/reference/dockerfile/) | #entrypoint | CMD、ENTRYPOINT | |
| 查官方术语定义（写讲义时统一用词） | [Glossary](https://docs.docker.com/reference/glossary/) | | 术语、名词 | |

## build-checks（构建 lint 规则）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 build checks 能查出哪些问题（总览） | [Build checks 总览](https://docs.docker.com/reference/build-checks/) | | 检查、lint、规则 | [Build checks 指南](https://docs.docker.com/build/checks/) |
| 查"JSON 形式写 CMD/ENTRYPOINT"这条规则 | [JSONArgsRecommended](https://docs.docker.com/reference/build-checks/json-args-recommended/) | | JSON、推荐写法 | |
| 查"密钥别进 ARG/ENV"这条规则 | [SecretsUsedInArgOrEnv](https://docs.docker.com/reference/build-checks/secrets-used-in-arg-or-env/) | | 密钥泄露 | [Build secrets](https://docs.docker.com/build/building/secrets/) |
| 查"MAINTAINER 已废弃" | [MaintainerDeprecated](https://docs.docker.com/reference/build-checks/maintainer-deprecated/) | | 废弃 | |
| 查"指令大小写不一致"等风格类规则 | [ConsistentInstructionCasing](https://docs.docker.com/reference/build-checks/consistent-instruction-casing/) / [FromAsCasing](https://docs.docker.com/reference/build-checks/from-as-casing/) | | 风格 | |
| 查其余规则（COPY 被忽略、WORKDIR 相对路径等） | [build-checks 索引](https://docs.docker.com/reference/build-checks/) | | 规则清单 | |

## dockerd / CLI 总览

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查守护进程 dockerd 全部启动参数 | [dockerd](https://docs.docker.com/reference/cli/dockerd/) | | dockerd、守护进程、daemon.json | [启动守护进程](https://docs.docker.com/engine/daemon/start/) |
| 查 docker CLI 命令总览 | [docker CLI 总览](https://docs.docker.com/reference/cli/docker/) | | CLI、总览 | |

## Engine API

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 Engine API 总览 | [Engine API](https://docs.docker.com/reference/api/engine/) | | API、程序化访问 | |
| 查 API 版本演进与选版 | [Version history](https://docs.docker.com/reference/api/engine/version-history/) | | 版本、v1.xx | |
| 查 SDK 使用示例 | [SDK examples](https://docs.docker.com/reference/api/engine/sdk/examples/) | | SDK、编程 | |
| 查 Registry API / Hub API | [Registry API](https://docs.docker.com/reference/api/registry/latest/) / [Hub API](https://docs.docker.com/reference/api/hub/latest/) | | registry、API | |
| 查某个具体 API 版本（v1.40–v1.56） | `https://docs.docker.com/reference/api/engine/version/v1.<次版本>/` | | 具体版本 | [版本历史](https://docs.docker.com/reference/api/engine/version-history/) |
