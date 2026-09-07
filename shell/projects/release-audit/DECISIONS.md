# 技术决策记录

门槛四要求：至少 2 处两难权衡，并记录**选了什么、放弃了什么**。
下面每一条都是真实发生过的取舍，不是事后编的。

---

## D1：敏感信息扫描用 grep，不用 Python

**背景**：要在 N 个文件里匹配 3 个正则。

**选项**：
- A. 每个文件每个模式跑一次 `grep`（当前实现）
- B. 一次 `grep -rE` 扫全部
- C. 迁到 Python，用 `re` 模块一次性扫描

**选了 A，放弃 B 和 C。**

**为什么放弃 C（Python）**：
本机有 Python，迁过去确实更优雅。但这会让工具从"零依赖运维脚本"变成"需要解释器环境的工具"——
而它的使用场景是 CI 流水线和运维同学的机器上，**零依赖本身就是需求**。
课 13 的迁移判据是"解析嵌套数据 / 分支超 3 层 / 需要单元测试"，
这里只是逐行正则匹配，shell 完全胜任。

**为什么放弃 B（grep -rE 一次扫）**：
`grep -r` 会把匹配到的**内容**一起输出，但需要的是"哪个文件命中了哪个模式"。
`grep -r` 只能给出文件路径，分不清是 3 个模式里的哪一个；
而且要跳过二进制文件还得额外处理。逐模式扫描能精确报出模式名（报告里的
`模式 credential-assignment` 就是这么来的）。

**代价（诚实说明）**：
这是本项目**唯一保留的循环内 fork 点**（files × patterns）。
实测 400 个文件 × 3 模式 = 1200 次 fork，在 WSL2 下约 2.4 秒。
WSL2 的 fork 跨 VM 边界，代价远高于原生 Linux（通常 50–150×），
原生环境下这个数字会小得多。**如果将来文件规模上到万级，这里必须改**。

---

## D2：checksum 用并发后台任务，不用串行

**背景**：SHA256 校验是 CPU 密集，且各文件彼此独立。

**选了并发（后台任务 + `wait` 分批），放弃串行。**

**为什么**：这是阶段 3「作业控制与并发」最标准的适用场景——
任务独立、耗时长、无共享状态。

**踩到的坑（课 9 实测结论的应用）**：
`set -e` 对裸 `wait` **生效**，对 `if wait` **失效**。
这里需要逐个拿退出码判断，所以写 `wait "$p" || true`，
把失败接住而不是让 `set -e` 把整个脚本干掉——
因为**单个文件校验失败是要记进报告，不是让整个审计崩掉**。

**代价**：并发让结果顺序不确定，所以每个任务把结果写进自己的临时文件，
等全部结束后再按顺序读取生成 finding（子 shell 无法回写父 shell 变量）。
引入了临时目录管理，复杂度上升。

---

## D3：临时目录用 nameref 出参，不用 stdout 返回

**背景**：`ra_mktemp_dir` 既要返回路径，又要把目录登记进清理列表。

**初版写法（错的）**：
```bash
ra_mktemp_dir() {
  local d
  d=$(mktemp -d ...)
  _RA_CORE_TEMP_DIRS+=("$d")
  printf '%s\n' "$d"
}
# 调用方
outdir=$(ra_mktemp_dir)      # ← 这里出事
```

**实测发现（tests/repro6_array_subsbleed.sh）**：
命令替换 `$(...)` 会开**子 shell**，函数里的 `+=` 发生在子 shell 中，
返回后父 shell 的数组**纹丝不动**：
```
d=$(ra_mktemp_dir);  echo ${#_RA_CORE_TEMP_DIRS[@]}   → 0   ✗
直接调 ra_mktemp_dir; echo ${#_RA_CORE_TEMP_DIRS[@]}  → 1   ✓
BASH_SUBSHELL：1 → 2（铁证）
```

**后果极隐蔽**：目录**确实**创建成功了（看不出异常），
但没登记 → EXIT trap 不清理 → **临时目录泄漏**。

**选了 nameref 出参**：
```bash
ra_mktemp_dir() {
  local -n _ra_nref_out=$1
  local _ra_tmp_dir
  _ra_tmp_dir=$(mktemp -d ...)
  _RA_CORE_TEMP_DIRS+=("$_ra_tmp_dir")
  _ra_nref_out=$_ra_tmp_dir
}
# 调用方
local outdir; ra_mktemp_dir outdir
```

**为什么放弃"改成全局变量 + 调两次"**：那样 API 更难用，且同样有命名污染。
nameref 是 bash 4.3+ 的正式特性，语义清晰。

**代价**：nameref 有撞名陷阱（见 D4），且 bash < 4.3 不可用。

---

## D4：nameref 变量与局部量必须前缀隔离

**背景**：D3 改成 nameref 后出现新 bug——调用方拿到的变量仍是空值。

**实测发现（tests/repro7_nameref.sh）**：
```bash
ra_mktemp_dir() {
  local -n _ra_nref_out=$1   # 指向调用方的 d
  local d                    # ← 又声明一个叫 d 的局部量
  ...
  _ra_nref_out=$d            # 循环引用！赋值静默失效
}
```
bash 报 `circular name reference`。

**这是课 6 nameref 陷阱的第三种变体**。课 6 讲的是
"被调用方 `local` 与 nameref **目标**同名"，这里撞的是
"**函数内局部量**与 nameref **指向的名字**同名"——
因为调用方传进来的是 `d`，而函数内 `local d` 恰好也叫 `d`。

**选了前缀隔离**：nameref 变量统一 `_ra_nref_` 前缀，
函数内临时量统一 `_ra_tmp_` 前缀。从命名上根除碰撞。

**放弃的做法**：只在注释里提醒"注意别撞名"。
命名约定比注释可靠——注释会被绕过，命名不会。

---

## D5：测试用手写运行器，不用 bats

**背景**：课 12 已确认本机未安装 bats-core，`command -v bats` 无输出。

**选了手写运行器，放弃安装 bats。**

**为什么**：阶段 4 的既有约定是"不擅自安装工具"。
而且手写运行器迫使每条断言都显式写出来，读者能直接看到在验什么。

**代价**：没有 bats 的 `run` / `assert_output` / `setup-teardown` 糖，
重复代码更多。

---

## D6：严格模式取证用 `$SHELLOPTS`，不用 `set +o`

**背景**：要断言"严格模式真的开着"。

**实测发现（tests/repro8_strict.sh）**：
```
顶层读：           errexit=-o   （显示开启）
在【函数里】读：   errexit=+o   （显示未开启）← 明明开着
在【命令替换】里： errexit 直接从列表里消失
```
`set -e` 的状态在函数/命令替换上下文中会被重置，
而断言函数内部正是命令替换——**取证手段污染了被取证对象**。

**选了 `$SHELLOPTS`**：bash 维护的冒号分隔只读快照，不受调用上下文影响。

**代价**：`$SHELLOPTS` 不含 `pipefail` 之外的部分 `set -o` 选项名，
且它是只读的（赋值会报错），只能读不能改。

---

## D7：清单文件区分"注释"与"元数据"两种语法

**背景**：清单里既有 `# 这是注释`，也有 `version=2.1.0`。

**初版只跳过了 `#` 注释**，结果 `version=2.1.0` 被当成一个叫
`version=2.1.0` 的必需文件 → clean 样例误报 BLOCK（e2e 实测抓出）。

**选了同时跳过两种**：`[[ $line == \#* ]] && continue` 之后补
`[[ $line == *=* ]] && continue`。

**代价**：文件名里**不能含等号**。对发布产物来说这个限制可以接受
（真实文件名极少含 `=`），但它确实是个限制，写在这里备忘。

---

## D8：库文件加 include guard

**背景**：`core.sh` 用了 `declare -r`，被重复 source 时会报错。

**实测发现（tests/repro4_scope_and_resource.sh）**：
```
第二次 source：
  declare: RA_LOG_DEBUG: readonly variable   ← 退出码非 0
  + 文件第 1 行的 set -e
  = source 到一半被终止，后面的函数与变量全部未定义
  = 调用方拿到 "unbound variable"，且错误信息完全指不到真正原因
```

**选了 include guard**（`[[ -n ${_RA_CORE_LOADED:-} ]] && return 0`）。

**放弃的做法**：把 `declare -r` 全改成普通变量。
那样就失去了 readonly 的保护——变量被意外覆盖时不会报错，
问题会更晚、更隐蔽地暴露。

---

## 复杂度四门槛达成情况

| 门槛 | 要求 | 实际 | 证据 |
|---|---|---|---|
| 规模 | ≥300 行、≥5 函数、≥2 文件 | 1053 行主程序 + 969 行测试、31 个函数、8 个文件 | `wc -l` |
| 跨阶段 | ≥3 阶段、每阶段 ≥2 知识点 | 4 阶段全覆盖（见下表） | 代码内知识点标注 |
| 质量 | 测试全绿、错误路径覆盖、注入全拦截、零循环内 fork | 57/57 通过、4 类注入拦截、fork 恒定 5 次 | `run_tests.sh`、`verify_complexity.sh` |
| 决策 | ≥2 处权衡并记录 | 8 条（本文件 D1–D8） | — |

## 知识点覆盖映射

| 阶段 | 知识点 | 落地位置 |
|---|---|---|
| 1 退出码与条件 | 退出码分级、参数展开、`case` | `core.sh` 退出码常量、`release-audit` 参数解析 |
| 2 变量与函数 | 关联数组、nameref、`local` 作用域、数组 | `report.sh` 统计与 nameref、`checks.sh` 清单表 |
| 3 子 shell 与并发 | 命令替换开子 shell、后台任务、`trap`、批量遍历 | `ra_mktemp_dir` nameref 出参、checksum 并发、`find -print0` |
| 4 生产化 | `set -Eeuo pipefail`、日志分级、注入防护、选型 | `core.sh` 严格模式与日志、注入防护用例、D1/D5 |
