# compose-file（Docker Docs · 共 19 条）

> 范围：`/reference/compose-file/` · 生成日期：2026-09-10
> 站点该分支共 17 页，全收。课 9 的主查分区：写 compose 文件时按"顶层段"跳转

## 顶层段

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查 services 段全部字段（image/build/ports/volumes/healthcheck…） | [services](https://docs.docker.com/reference/compose-file/services/) | #depends_on | services、服务、字段 | [服务启动顺序](https://docs.docker.com/compose/how-tos/startup-order/) |
| 查 depends_on 的短语法与长语法 | [services · depends_on](https://docs.docker.com/reference/compose-file/services/) | #depends_on | 依赖、启动顺序 | |
| 查 healthcheck 写法 | [services · healthcheck](https://docs.docker.com/reference/compose-file/services/) | #healthcheck | 健康检查 | [启动顺序](https://docs.docker.com/compose/how-tos/startup-order/) |
| 查 networks 顶层段 | [networks](https://docs.docker.com/reference/compose-file/networks/) | | 网络、自定义网络 | [Compose 网络](https://docs.docker.com/compose/how-tos/networking/) |
| 查 volumes 顶层段 | [volumes](https://docs.docker.com/reference/compose-file/volumes/) | | 卷、具名卷 | [Volumes](https://docs.docker.com/engine/storage/volumes/) |
| 查 configs 顶层段 | [configs](https://docs.docker.com/reference/compose-file/configs/) | | 配置 | |
| 查 secrets 顶层段 | [secrets](https://docs.docker.com/reference/compose-file/secrets/) | | 密钥 | [Compose 管密钥](https://docs.docker.com/compose/how-tos/use-secrets/) |
| 查 build 段（镜像怎么在 compose 里构建） | [build](https://docs.docker.com/reference/compose-file/build/) | | 构建、build | [Build 手册](https://docs.docker.com/build/) |
| 查 deploy 段 | [deploy](https://docs.docker.com/reference/compose-file/deploy/) | | 部署、副本 | |
| 查 develop 段（watch 相关） | [develop](https://docs.docker.com/reference/compose-file/develop/) | | watch、开发 | [Compose Watch](https://docs.docker.com/compose/how-tos/file-watch/) |

## 语法与复用

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲变量插值 `${VAR:-default}` 怎么写 | [interpolation](https://docs.docker.com/reference/compose-file/interpolation/) | | 插值、变量、.env | [环境变量优先级](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/) |
| 讲多文件合并规则 | [merge](https://docs.docker.com/reference/compose-file/merge/) | | 合并、多文件 | [merge how-to](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/) |
| 讲 include 顶层元素 | [include](https://docs.docker.com/reference/compose-file/include/) | | include、复用 | |
| 讲 extension（`x-` 自定义字段）与 anchors | [extension](https://docs.docker.com/reference/compose-file/extension/) | | 扩展、x-、锚点 | |
| 讲 fragments（YAML 片段复用） | [fragments](https://docs.docker.com/reference/compose-file/fragments/) | | 片段、复用 | |
| 讲 models（AI 模型服务声明） | [models](https://docs.docker.com/reference/compose-file/models/) | | model | |
| 讲 version 与 name 顶层元素 | [version-and-name](https://docs.docker.com/reference/compose-file/version-and-name/) | | 版本、项目名 | [指定项目名](https://docs.docker.com/compose/how-tos/project-name/) |
| 讲 profiles（按需启用服务） | [profiles](https://docs.docker.com/reference/compose-file/profiles/) | | profile | [profiles how-to](https://docs.docker.com/compose/how-tos/profiles/) |
| 查旧版 compose 文件格式（v2/v3 迁移） | [legacy-versions](https://docs.docker.com/reference/compose-file/legacy-versions/) | | 旧版本、v2、v3 | [Compose 历史](https://docs.docker.com/compose/intro/history/) |
