# release-audit 项目说明

发布产物审计工具。输入一个发布目录，输出分级审计报告，并用退出码告诉调用方能不能发。

## 快速开始

```bash
# 基本用法：审计一个发布目录
release-audit /path/to/release

# 带清单文件（检查必需文件是否齐全）
release-audit /path/to/release /path/to/MANIFEST

# 只输出报告，不看日志
release-audit -q /path/to/release

# 看调试日志
release-audit -v /path/to/release

# 跳过某些检查
release-audit --skip secret --skip perm /path/to/release

# 指定并发度（默认 = CPU 核数）
release-audit -j 4 /path/to/release
```

## 退出码

| 码 | 含义 | 调用方该怎么做 |
|---|---|---|
| 0 | 全部通过 | 放心发布 |
| 1 | 有 WARN | 可以发，但建议看一眼警告 |
| 2 | 有 BLOCK | **必须阻断**，不要发布 |
| 64 | 用法错误 | 参数传错了，检查命令行 |
| 66 | 输入不存在/不可读 | 路径不对或没权限 |
| 70 | 内部错误 | 工具自身出问题了 |

`0 / 1 / 2` 三档是刻意分开的：混成一个 `1` 的话，调用方就只能靠 grep 日志文本来判断能不能发——那是把结构化信息降级成字符串匹配。

## 报告与日志分离

- **报告写 stdout**：`release-audit dir > report.txt` 拿到干净报告
- **日志写 stderr**：`2>audit.log` 单独留档

## 检查项

| 检查 | 阻断级问题 | 警告级问题 |
|---|---|---|
| `struct` | 目录里没有任何文件 | 存在 >100MB 的单文件 |
| `required` | 清单里声明的文件缺失 | 是符号链接、不是常规文件 |
| `perm` | world-writable | 私钥权限过宽、`.sh` 缺可执行位 |
| `secret` | 疑似硬编码凭证 | — |
| `version` | 目录名/VERSION/清单 三方版本不一致 | VERSION 内容不像版本号 |
| `checksum` | SHA256 不匹配、文件不存在 | 无法计算 |

## 清单文件格式

```
# 这是注释
version=2.1.0          ← 元数据行（key=value）
bin/app                ← 必需文件（相对路径）
bin/start.sh
conf/app.conf
```

注释（`#`）与元数据（`key=value`）都不会被当成文件名。

## 运行测试

```bash
bash tests/run_tests.sh          # 全部
bash tests/run_tests.sh core     # 只跑 core 相关
```

## 目录结构

```
release-audit             主程序（参数解析 + 编排）
lib/core.sh               严格模式、日志分级、退出码、trap 清理
lib/report.sh             finding 收集、统计、报告渲染
lib/checks.sh             六项具体检查
tests/run_tests.sh        手写测试运行器
tests/make_fixture.sh     测试数据构造（clean/warn/block/tampered）
tests/test_core.sh        核心库用例
tests/test_checks.sh      集成用例（含注入防护、并发）
tests/verify_complexity.sh 复杂度门槛核查
DECISIONS.md              技术决策记录（为什么这么写）
```

## 环境要求

bash 4.4+，以及 `find` / `awk` / `sha256sum` / `mktemp` / `stat`（均为常规系统自带）。
**无 bats、无 shellcheck、无 jq 依赖**——按课程约定未安装这些工具，测试用等价的手写运行器。
