# compose（Docker Docs · 共 30 条）

> 范围：/compose/ · 生成日期：2026-09-10
> 本表是「how-to / 概念」类；**字段级语法去 `compose-file.md`**，命令语法去 `cli.md`

## 介绍与模型

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲 Compose 解决什么问题、典型用法 | [Why use Compose?](https://docs.docker.com/compose/intro/features-uses/) | | 为什么、用途 | |
| 讲 Compose 应用模型（项目→服务→容器） | [How Compose works](https://docs.docker.com/compose/intro/compose-application-model/) | | 应用模型、原理 | [services 字段](https://docs.docker.com/reference/compose-file/services/) |
| 讲 Compose 演进史（v1→v2、YAML 版本） | [History and development](https://docs.docker.com/compose/intro/history/) | | 历史、v1、v2 | |
| 跟一遍 Compose 快速上手 | [Compose Quickstart](https://docs.docker.com/compose/gettingstarted/) | | 快速上手、教程 | |
| 讲为什么 compose 文件是"可信输入"（风险） | [Trust model](https://docs.docker.com/compose/trust-model/) | | 信任、安全 | |
| 查常见问题（v1 vs v2 等） | [FAQ](https://docs.docker.com/compose/support-and-feedback/faq/) | | FAQ、v1 vs v2 | |

## 安装

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| Linux 装 Compose 插件 | [Install plugin (Linux)](https://docs.docker.com/compose/install/linux/) | | 安装、插件 | |
| 查独立版（legacy）与卸载 | [Standalone (Legacy)](https://docs.docker.com/compose/install/standalone/) / [Uninstall](https://docs.docker.com/compose/install/uninstall/) | | legacy、卸载 | |
| 查发布说明 | [Release notes](https://docs.docker.com/compose/release-notes/) | | 发布说明 | |

## how-tos

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲多文件合并 / extends / include | [Merge](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/) / [extends](https://docs.docker.com/compose/how-tos/multiple-compose-files/extends/) / [include](https://docs.docker.com/compose/how-tos/multiple-compose-files/include/) | | 合并、复用、多文件 | [merge 字段参考](https://docs.docker.com/reference/compose-file/merge/) |
| 讲服务启动/停止顺序（depends_on + healthcheck） | [Control startup and shutdown order](https://docs.docker.com/compose/how-tos/startup-order/) | | 启动顺序、depends_on | [depends_on](https://docs.docker.com/reference/compose-file/services/#depends_on) |
| 讲 Compose 里的网络怎么建 | [Networking in Compose](https://docs.docker.com/compose/how-tos/networking/) | | 网络、服务发现 | [networks 字段](https://docs.docker.com/reference/compose-file/networks/) |
| 讲环境变量优先级（谁覆盖谁） | [Env vars precedence](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/) | | 环境变量、优先级 | |
| 讲 .env 与变量插值 | [Variable interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) | | .env、插值 | [interpolation 参考](https://docs.docker.com/reference/compose-file/interpolation/) |
| 讲 Compose 环境变量最佳实践 | [Env vars best practices](https://docs.docker.com/compose/how-tos/environment-variables/best-practices/) | | 最佳实践 | |
| 查 Compose 预定义环境变量 | [Pre-defined env vars](https://docs.docker.com/compose/how-tos/environment-variables/envvars/) | | 预定义变量 | |
| 讲怎么给容器设环境变量 | [Set env vars in container](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/) | | 环境变量 | |
| 讲 Compose 里管密钥（build/runtime） | [Manage secrets](https://docs.docker.com/compose/how-tos/use-secrets/) | | secret、密钥 | [secrets 字段](https://docs.docker.com/reference/compose-file/secrets/) |
| 讲 watch 模式（改代码自动同步） | [Use Compose Watch](https://docs.docker.com/compose/how-tos/file-watch/) | | watch、热更新 | [develop 字段](https://docs.docker.com/reference/compose-file/develop/) |
| 讲 profiles（按需启部分服务） | [Using profiles](https://docs.docker.com/compose/how-tos/profiles/) | | profile | [profiles 参考](https://docs.docker.com/reference/compose-file/profiles/) |
| 讲怎么指定项目名 | [Specify a project name](https://docs.docker.com/compose/how-tos/project-name/) | | 项目名、-p | [version-and-name](https://docs.docker.com/reference/compose-file/version-and-name/) |
| 讲生产环境用 Compose 的注意事项 | [Use Compose in production](https://docs.docker.com/compose/how-tos/production/) | | 生产、部署 | |
| 讲服务间共享镜像定义（依赖构建） | [Build dependent images](https://docs.docker.com/compose/how-tos/dependent-images/) | | 构建、依赖 | |
| 讲 init 容器（启动前跑任务） | [Init containers](https://docs.docker.com/compose/how-tos/init-containers/) | | init、前置任务 | |
| 讲生命周期钩子（pre_start/post_start/pre_stop） | [Lifecycle hooks](https://docs.docker.com/compose/how-tos/lifecycle/) | | 钩子、生命周期 | |
| 讲 Compose 应用打包成 OCI 制品 | [OCI artifact](https://docs.docker.com/compose/how-tos/oci-artifact/) | | OCI、分发 | |
| 查 GPU 支持 | [GPU support](https://docs.docker.com/compose/how-tos/gpu-support/) | | GPU | |
| 查 provider services（外部能力接入） | [Provider services](https://docs.docker.com/compose/how-tos/provider-services/) | | provider | |

## 周边

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲 Compose Bridge（转 K8s 清单） | [Bridge usage](https://docs.docker.com/compose/bridge/usage/) / [Customize](https://docs.docker.com/compose/bridge/customize/) | | k8s、转换 | |
| 查 Compose SDK（嵌进应用） | [Compose SDK](https://docs.docker.com/compose/compose-sdk/) | | SDK | |
