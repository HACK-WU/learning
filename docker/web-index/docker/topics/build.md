# build（Docker Docs · 共 58 条）

> 范围：/build/ · 生成日期：2026-09-10
> 排除 `build/release-notes`；Bake（13 条）与 policies（9 条）属进阶，集中在本表末尾

## 概念与 Dockerfile

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 Docker Build 全景与组件 | [Docker Build Overview](https://docs.docker.com/build/concepts/overview/) | | build、总览、BuildKit | |
| 讲 Dockerfile 是什么、怎么写 | [Dockerfile overview](https://docs.docker.com/build/concepts/dockerfile/) | | Dockerfile、概念 | [Dockerfile 参考](https://docs.docker.com/reference/dockerfile/) |
| 讲构建上下文是什么、为什么影响 .dockerignore | [Build context](https://docs.docker.com/build/concepts/context/) | | 上下文、dockerignore | |
| 查 Dockerfile 编写最佳实践 | [Building best practices](https://docs.docker.com/build/building/best-practices/) | | 最佳实践、优化 | |
| 讲基础镜像怎么选 | [Base images](https://docs.docker.com/build/building/base-images/) | | 基础镜像、选型 | [瘦身](https://docs.docker.com/build/building/multi-stage/) |
| 讲多阶段构建 | [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/) | | 多阶段、瘦身 | |
| 讲构建期环境变量与 ARG | [Build variables](https://docs.docker.com/build/building/variables/) | | ARG、ENV、构建变量 | |
| 讲构建期密钥不进镜像层（`--secret`） | [Build secrets](https://docs.docker.com/build/building/secrets/) | | 密钥、secret、安全 | [RUN --mount=type=secret](https://docs.docker.com/reference/dockerfile/#run---mount) |
| 讲多平台构建（arm/amd 同时出镜像） | [Multi-platform builds](https://docs.docker.com/build/building/multi-platform/) | | 多架构、buildx、platform | |
| 讲用构建产物导出二进制 | [Export binaries](https://docs.docker.com/build/building/export/) | | 导出、二进制 | |
| 查构建里访问 GPU / 设备（CDI） | [Container Device Interface](https://docs.docker.com/build/building/cdi/) | | CDI、GPU | |

## 构建缓存（课 4 / 课 13 重点）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看缓存总览 | [Build cache](https://docs.docker.com/build/cache/) | | 缓存、cache | |
| 讲缓存什么时候失效、指令顺序的影响 | [Cache invalidation](https://docs.docker.com/build/cache/invalidation/) | | 失效、指令顺序 | [使用构建缓存（概念）](https://docs.docker.com/get-started/docker-concepts/building-images/using-the-build-cache/) |
| 讲怎么优化缓存命中率 | [Optimize cache usage](https://docs.docker.com/build/cache/optimize/) | | 优化、命中率 | |
| 讲缓存 GC 与容量回收 | [Garbage collection](https://docs.docker.com/build/cache/garbage-collection/) | | GC、回收 | [builder prune](https://docs.docker.com/reference/cli/docker/builder/prune/) |
| 讲 inline 缓存（塞进镜像） | [Inline cache](https://docs.docker.com/build/cache/backends/inline/) | | inline、缓存 | |
| 讲 registry 缓存后端 | [Registry cache](https://docs.docker.com/build/cache/backends/registry/) | | registry 缓存 | |
| 讲本地目录缓存后端 | [Local cache](https://docs.docker.com/build/cache/backends/local/) | | local 缓存 | |
| 讲 GitHub Actions 缓存后端 | [GHA cache](https://docs.docker.com/build/cache/backends/gha/) | | gha、CI 缓存 | |
| 查 S3 / Azure Blob 缓存后端 | [S3](https://docs.docker.com/build/cache/backends/s3/) / [azblob](https://docs.docker.com/build/cache/backends/azblob/) | | 对象存储缓存 | |

## BuildKit 与 builder

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲怎么配 BuildKit | [Configure BuildKit](https://docs.docker.com/build/buildkit/configure/) | | buildkit、配置 | |
| 查 buildkitd.toml 全部配置项 | [buildkitd.toml](https://docs.docker.com/build/buildkit/toml-configuration/) | | toml、配置 | |
| 讲自定义 Dockerfile 前端 / 语法指令 | [Custom Dockerfile syntax](https://docs.docker.com/build/buildkit/frontend/) | | 前端、syntax | |
| 看 builder 与驱动怎么管 | [Manage builders](https://docs.docker.com/build/builders/manage/) | | builder、驱动 | [buildx CLI](https://docs.docker.com/reference/cli/docker/buildx/) |
| 讲 docker 驱动（默认） | [Docker driver](https://docs.docker.com/build/builders/drivers/docker/) | | 驱动、默认 | |
| 讲 docker-container 驱动（要外部缓存时用） | [Docker container driver](https://docs.docker.com/build/builders/drivers/docker-container/) | | 驱动、containerd | |
| 查 kubernetes / remote / cloud 驱动 | [Kubernetes](https://docs.docker.com/build/builders/drivers/kubernetes/) / [Remote](https://docs.docker.com/build/builders/drivers/remote/) / [Cloud](https://docs.docker.com/build/builders/drivers/cloud/) | | 驱动 | |
| 讲 build 的 OpenTelemetry 追踪 | [OpenTelemetry support](https://docs.docker.com/build/debug/opentelemetry/) | | otel、追踪 | |

## 导出器与元数据（课 13 供应链）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲镜像/仓库导出器 | [Image and registry exporters](https://docs.docker.com/build/exporters/image-registry/) | | exporter、导出 | |
| 讲 local / tar 导出器 | [Local and tar exporters](https://docs.docker.com/build/exporters/local-tar/) | | 导出、tar | |
| 讲 OCI / docker 导出器 | [OCI and Docker exporters](https://docs.docker.com/build/exporters/oci-docker/) | | oci、导出 | |
| 讲镜像注解 annotations | [Annotations](https://docs.docker.com/build/metadata/annotations/) | | 注解、annotation | |
| 讲 SBOM 证明 | [SBOM attestations](https://docs.docker.com/build/metadata/attestations/sbom/) | | SBOM、供应链 | |
| 讲来源证明 provenance（SLSA） | [Provenance attestations](https://docs.docker.com/build/metadata/attestations/slsa-provenance/) / [SLSA definitions](https://docs.docker.com/build/metadata/attestations/slsa-definitions/) | | provenance、SLSA | |
| 查证明存在哪 | [Attestation storage](https://docs.docker.com/build/metadata/attestations/attestation-storage/) | | 存储 | |

## 构建检查（lint）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲 build checks 校验构建配置 | [Build checks](https://docs.docker.com/build/checks/) | | 检查、lint | [build-checks 参考](https://docs.docker.com/reference/build-checks/) |

## CI（GitHub Actions）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 CI 集成总览（GHA） | [GitHub Actions](https://docs.docker.com/build/ci/github-actions/) | | CI、GitHub Actions | |
| 讲 CI 里怎么配缓存 | [Cache management in GHA](https://docs.docker.com/build/ci/github-actions/cache/) | | 缓存、CI | |
| 讲 CI 里怎么配 builder | [Configure builder](https://docs.docker.com/build/ci/github-actions/configure-builder/) | | builder、CI | |
| 讲 CI 里跑 build checks | [Validating with GHA](https://docs.docker.com/build/ci/github-actions/checks/) | | 检查、CI | |
| 讲多平台镜像（QEMU / 多原生 builder） | [Multi-platform in GHA](https://docs.docker.com/build/ci/github-actions/multi-platform/) | | 多架构、QEMU | |
| 讲推送前先测试镜像 | [Test before push](https://docs.docker.com/build/ci/github-actions/test-before-push/) | | 测试、CI | |
| 讲 job 之间传镜像不落仓库 | [Share image between jobs](https://docs.docker.com/build/ci/github-actions/share-image-jobs/) | | 传镜像 | |
| 讲可复现构建（SOURCE_EPOCH） | [Reproducible builds](https://docs.docker.com/build/ci/github-actions/reproducible-builds/) | | 可复现 | |
| 讲自动打 tag / label | [Manage tags and labels](https://docs.docker.com/build/ci/github-actions/manage-tags-labels/) | | tag、label | |
| 讲 CI 里加 SBOM / provenance 证明 | [Attestations in GHA](https://docs.docker.com/build/ci/github-actions/attestations/) | | SBOM、证明 | |
| 查其余 GHA 配方（复制镜像/本地仓库/多仓库推送等） | [GHA 索引](https://docs.docker.com/build/ci/github-actions/) | | 配方 | |

## Bake（进阶）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲 Bake 是什么、怎么起步 | [Introduction to Bake](https://docs.docker.com/build/bake/introduction/) | | bake、多目标 | |
| 查 Bake 文件参考 | [Bake file reference](https://docs.docker.com/build/bake/reference/) | | 参考 | |
| 讲 target 定义与继承 | [Targets](https://docs.docker.com/build/bake/targets/) / [Inheritance](https://docs.docker.com/build/bake/inheritance/) | | target、继承 | |
| 讲 matrix 目标（一次多变体） | [Matrix targets](https://docs.docker.com/build/bake/matrices/) | | matrix | |
| 讲从 Compose 文件构建 | [Bake from Compose file](https://docs.docker.com/build/bake/compose-file/) | | compose、bake | |
| 查 Bake 变量与函数 | [Variables](https://docs.docker.com/build/bake/variables/) / [Functions](https://docs.docker.com/build/bake/funcs/) / [Stdlib](https://docs.docker.com/build/bake/stdlib/) | | 变量、函数 | |

## Build policies（进阶）

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 讲构建策略是什么 | [Intro to build policies](https://docs.docker.com/build/policies/intro/) | | 策略、policy | |
| 查怎么施加/迭代策略 | [Using build policies](https://docs.docker.com/build/policies/usage/) | | 使用 | |
| 查策略模板示例 | [Policy examples](https://docs.docker.com/build/policies/examples/) | | 示例 | |
| 查策略输入字段参考 | [Input reference](https://docs.docker.com/build/policies/inputs/) | | 参考 | |
| 校验 Git 仓库 / 基础镜像 | [Validate Git](https://docs.docker.com/build/policies/validate-git/) / [Validate images](https://docs.docker.com/build/policies/validate-images/) | | 校验 | |
