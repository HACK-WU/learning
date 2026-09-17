# 代码调研：Go 结课综合实战项目

> 调研日期：2026-09-16
> 调研来源：项目记忆 ✓ | 资产复用（专家/方案）△（当前会话无对应查询工具） | 代码搜索 ✓ | 语义检索 ✗
> 调研范围：课程资产、数据访问基线、既有结课项目体例、课程状态与导航

## 1. 课程资产与技术栈

- 来源：项目记忆 + 代码搜索。
- Go 课程档案确认本机基线为 `go1.27.1 darwin/arm64`，45 / 45 个知识点已完成，下一步就是 Phase 3。
- `go/playground/lesson-12/go.mod` 使用 `go 1.27` 和 `modernc.org/sqlite v1.58.0`；该驱动为纯 Go，适合验证 `CGO_ENABLED=0` 交付路径。
- 课 13–15 playground 已提供模块、测试、竞态、静态检查、benchmark、pprof、ldflags、健康/就绪、pprof 隔离和 Shutdown 的可复用实测口径。

## 2. 可参考的类似项目

- 来源：代码搜索。
- `docker/projects/订单服务生产化/README.md`：采用“跨阶段映射 / 非功能约束 / 真权衡 / 分步实施 / 验收清单 / 修改建议”的项目文档结构。
- `elasticsearch/elk/projects/日志平台生产化/README.md`：采用独立架构图、实现目录、端到端证据和生产坑对照；适合本项目保留证据归档和反例章节。
- Go 课程当前没有既有 `projects/` 项目，因此本项目不复制已有 Go 实现。

## 3. 数据存储

- 来源：代码搜索。
- 课 12 的 DAO 探针显式设置 `MaxOpenConns`、`MaxIdleConns`、连接生命周期和 `PingContext`，使用参数化 SQL、`QueryRowContext`、`Rows.Close`、事务 `defer Rollback`。
- 本项目沿用这些原则，并将订单状态更新封装在存储层，避免 handler 直接散落 SQL。

## 4. API、错误与可观测约定

- 来源：课程档案与课 11–15 产物检查。
- 对外采用标准库 `net/http`，公共端口仅暴露业务、健康/就绪、指标；管理端口单独挂 pprof。
- 请求错误使用 HTTP 状态码 + JSON 错误体；业务失败落订单状态，基础设施错误保留包装链。
- 日志使用结构化 `log/slog`；指标用标准库原子计数器输出 Prometheus 文本格式，避免把可选 SDK 变成项目必需依赖。

## 5. 测试与交付

- 来源：课 13–15 playground 和现有结课项目。
- 验证层次固定为单元/集成、`-race`、`gofmt`、`go vet`、构建、benchmark/profile、交叉构建、Docker 运行和文档证据。
- 实测数字写入项目 `ALL_OUTPUT.txt`；端口、耗时、基准值和镜像 digest 等漂移值不在正文中伪装成恒定值。
