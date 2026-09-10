# docker-hub（Docker Docs · 共 32 条）

> 范围：/docker-hub/ · 生成日期：2026-09-10
> 课 3（仓库/标签/digest）与课 13（推送/交付）的主查分区；组织与权限治理相关见 `security/`

## 快速上手与镜像库

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 跟一遍 Docker Hub 快速上手 | [Docker Hub quickstart](https://docs.docker.com/docker-hub/quickstart/) | | 快速上手、注册 | |
| 讲怎么搜镜像、看懂搜索结果 | [Docker Hub search](https://docs.docker.com/docker-hub/image-library/search/) | | 搜索、找镜像 | |
| 讲可信内容（Official Images / DVP） | [Trusted content](https://docs.docker.com/docker-hub/image-library/trusted-content/) | | 官方镜像、可信 | [Docker Official Images](https://docs.docker.com/docker-hub/repos/manage/trusted-content/official-images/) |
| 讲什么是 Docker Official Images | [Official Images](https://docs.docker.com/docker-hub/repos/manage/trusted-content/official-images/) | | 官方镜像 | |
| 查 DVP / DSOS 计划 | [DVP](https://docs.docker.com/docker-hub/repos/manage/trusted-content/dvp-program/) / [DSOS](https://docs.docker.com/docker-hub/repos/manage/trusted-content/dsos-program/) | | 认证、发行者 | |
| 查镜像目录（catalogs） | [Catalogs](https://docs.docker.com/docker-hub/image-library/catalogs/) | | 目录 | |
| 讲怎么搭 Docker Hub 本地镜像源 | [Mirror the library](https://docs.docker.com/docker-hub/image-library/mirror/) | | 镜像源、mirror | |

## 仓库管理

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲怎么建仓库 | [Create a repository](https://docs.docker.com/docker-hub/repos/create/) | | 建仓库 | |
| 讲怎么删仓库 | [Delete a repository](https://docs.docker.com/docker-hub/repos/delete/) | | 删仓库 | |
| 讲归档 / 取消归档 | [Archive or unarchive](https://docs.docker.com/docker-hub/repos/archive/) | | 归档 | |
| 讲仓库访问权限怎么管 | [Access management](https://docs.docker.com/docker-hub/repos/manage/access/) | | 权限、团队 | |
| 讲怎么写仓库描述、提升可发现性 | [Repository information](https://docs.docker.com/docker-hub/repos/manage/information/) | | 描述、README | |

## 镜像与标签（课 3 / 课 13）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲怎么推送镜像到仓库 | [Push images](https://docs.docker.com/docker-hub/repos/manage/hub-images/push/) | | push、推送 | [docker push](https://docs.docker.com/reference/cli/docker/image/push/) |
| 讲 tag 的管理与最佳实践（别用 latest） | [Tags](https://docs.docker.com/docker-hub/repos/manage/hub-images/tags/) | | tag、标签、latest | [docker tag](https://docs.docker.com/reference/cli/docker/image/tag/) |
| 讲不可变标签（immutable tags） | [Immutable tags](https://docs.docker.com/docker-hub/repos/manage/hub-images/immutable-tags/) | | 不可变、immutable | |
| 讲镜像删除与镜像管理 | [Image management](https://docs.docker.com/docker-hub/repos/manage/hub-images/manage/) | | 删除、tag | |
| 讲镜像在仓库间搬移 / 批量迁移 | [Move images](https://docs.docker.com/docker-hub/repos/manage/hub-images/move/) / [Bulk migrate](https://docs.docker.com/docker-hub/repos/manage/hub-images/bulk-migrate/) | | 迁移、搬移 | |
| 讲 OCI 制品也能存 Hub | [OCI artifacts](https://docs.docker.com/docker-hub/repos/manage/hub-images/oci-artifacts/) | | OCI、制品 | |

## 自动构建（autobuild）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲怎么配自动构建（GitHub/Bitbucket） | [Set up automated builds](https://docs.docker.com/docker-hub/repos/manage/builds/setup/) | | autobuild、CI | |
| 讲从 autobuild 迁到 CI/CD | [Migrate from Autobuilds](https://docs.docker.com/docker-hub/repos/manage/builds/migrate/) | | 迁移、autobuild | [GHA 构建](https://docs.docker.com/build/ci/github-actions/) |
| 查 autobuild 高级选项与自动测试 | [Advanced options](https://docs.docker.com/docker-hub/repos/manage/builds/advanced/) / [Automated testing](https://docs.docker.com/docker-hub/repos/manage/builds/automated-testing/) | | 自动构建 | |
| 查关联源码仓库与管理构建 | [Link source](https://docs.docker.com/docker-hub/repos/manage/builds/link-source/) / [Manage builds](https://docs.docker.com/docker-hub/repos/manage/builds/manage-builds/) | | 源码、管理 | |
| autobuild 排障 | [Troubleshoot autobuilds](https://docs.docker.com/docker-hub/repos/manage/builds/troubleshoot/) | | 排障 | |

## 用量、限额与安全

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲拉取限额（rate limit）怎么算 | [Pull usage and limits](https://docs.docker.com/docker-hub/usage/pulls/) | | 限流、rate limit、429 | |
| 讲怎么用 Hub 更省（优化用量） | [Best practices for usage](https://docs.docker.com/docker-hub/usage/manage/) | | 配额、优化 | |
| 查漏洞扫描与镜像安全洞察 | [Image security insights](https://docs.docker.com/docker-hub/repos/manage/vulnerability-scanning/) | | 漏洞、扫描 | |
| 查使用统计 / insights | [Insights and analytics](https://docs.docker.com/docker-hub/repos/manage/trusted-content/insights-analytics/) | | 统计 | |
| 查 webhook | [Webhooks](https://docs.docker.com/docker-hub/repos/manage/webhooks/) | | webhook | |
| 查组织仓库导出 CSV | [Export repos to CSV](https://docs.docker.com/docker-hub/repos/manage/export/) | | 导出 | |
| 查账号设置 | [Settings](https://docs.docker.com/docker-hub/settings/) | | 设置 | |
| Docker Hub 排障 | [Troubleshoot Docker Hub](https://docs.docker.com/docker-hub/troubleshoot/) | | 排障 | |
| 查 Hub MCP server（给 LLM 用） | [Docker Hub MCP server](https://docs.docker.com/docker-hub/mcp-server/) | | MCP | |
