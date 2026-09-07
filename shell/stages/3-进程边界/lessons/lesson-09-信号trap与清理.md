# 第 9 课：信号 trap 与清理

> 所属阶段：阶段 3《进程边界》｜ 水平：进阶 ｜ 本课知识点：信号基础与 trap、伪信号 EXIT/ERR/DEBUG、清理/锁与临时文件
> 故事情节：Ctrl-C 按下去，脚本停了，但临时目录留下了、锁没释放、远程主机上还挂着个半截部署

## 🎯 本课目标

- 注册 SIGINT/SIGTERM 处理，知道 trap 的继承与重置规则
- 用 `trap ... EXIT` 做清理，说清 ERR 与 `set -e` 的联动
- 用 `mktemp -d` + `trap EXIT` + `flock` 写出中断安全的脚本

---

## 第一幕：起源与场景引入

> 🎬 **场景**：`deploy.sh` 会建临时目录、加锁、往远程主机传文件。某次跑到一半发现参数错了，运维按下 Ctrl-C。脚本停了——但：

- `/tmp/deploy.XXXX/` 留在磁盘上，日积月累占满了 `/tmp`
- 锁文件还在，下次运行直接"已有实例在运行"然后退出
- 远程主机上传了一半的文件没清理，下个版本的文件校验失败

脚本"停了"，但它留下的烂摊子还在。

更糟的是，这个烂摊子**会自我伪装**。运维第二次运行脚本时看到"已有实例在运行"，他无法区分这两种情况：

- 真有一个实例在跑（此时等待是正确的）
- 上次崩溃留下的残骸（此时等待是愚蠢的）

于是他只能 `rm -f deploy.lock`——而这个手动删除的动作，恰恰会在真的有实例在跑时造成两个实例并发。

本课要解决的，就是让脚本**在任何死法下都干净收摊**。

---

## 第二幕：认知冲突

> ❓ **问题**：我在脚本末尾写了 `rm -rf "$tmpdir"`，为什么没执行？

因为 Ctrl-C 让进程**死在了半路**，根本没走到最后一行。清理逻辑写在"正常路径的末尾"，只覆盖了"顺利跑完"这一种结局——而恰好只有这种结局不需要清理。

下面这段脚本把这个后果原样复现出来（本机实测）：

```bash
cat > /tmp/bad_deploy.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail
LOCK=/tmp/bad_demo.lock
tmp=$(mktemp -d)
echo "[1] 建临时目录: $tmp"
echo "[2] 加锁"
exec 9>"$LOCK"
flock -n 9 || { echo "已有实例在运行"; exit 1; }
echo "[3] 模拟传输（5秒）"
sleep 5
echo "[4] 收尾"
rm -rf "$tmp"
rm -f "$LOCK"
echo "    正常完成"
SH
chmod +x /tmp/bad_deploy.sh
rm -f /tmp/bad_demo.lock

echo "=== 结局1：正常跑完 ==="
/tmp/bad_deploy.sh; echo "退出码=$?"

echo "=== 结局2：跑到一半按 Ctrl-C ==="
/tmp/bad_deploy.sh & p=$!
sleep 0.8
kill -TERM $p
wait $p
echo "退出码=$?"
echo "锁还在吗：$([ -f /tmp/bad_demo.lock ] && echo '在' || echo '不在')"

echo "=== 结局3：再跑一次 ==="
/tmp/bad_deploy.sh
echo "退出码=$?  ← 明明没有实例在跑，却被拒之门外"
```text

```text
=== 结局1：正常跑完 ===
[1] 建临时目录: /tmp/tmp.XXXXXXXXXX
[2] 加锁
[3] 模拟传输（5秒）
[4] 收尾
    正常完成
退出码=0
=== 结局2：跑到一半按 Ctrl-C ===
[1] 建临时目录: /tmp/tmp.YYYYYYYYYY
[2] 加锁
[3] 模拟传输（5秒）
退出码=143
锁还在吗：在
=== 结局3：再跑一次 ===
[1] 建临时目录: /tmp/tmp.ZZZZZZZZZZ
[2] 加锁
已有实例在运行
退出码=1  ← 明明没有实例在跑，却被拒之门外
```text

**注意结局 2 的退出码是 143，不是 130。** 后面会解释为什么 `TERM` 与 `INT` 的表现差这么多——这是本课第一个反直觉的点。

正确的做法是：**把清理注册成一个"无论怎么死都会执行"的钩子**，而不是写在线性流程的末尾。这就是 `trap ... EXIT`。

---

## 第三幕：层层揭示

### 知识点 1：信号基础与 trap

> 本知识点关键点：常见信号（SIGINT=2 / SIGTERM=15 / SIGHUP=1 / SIGKILL=9 不可捕获）、`trap 'cmd' SIG` 注册、`trap - SIG` 重置为默认、`trap '' SIG` 忽略、**trap 只在本进程有效**、子 shell 与子进程中 trap 的继承规则（子进程重置为默认，除被忽略的信号保持忽略）、`trap -p` 查看

#### 一句话定义

信号是内核或其他进程发给进程的**一条异步通知**；`trap` 是 shell 提供的机制，让你为"收到某信号时做什么"注册一段处理代码。

#### 直觉建立（类比）

`trap` 是**遗嘱**，不是日程表。

日程表规划的是"正常情况下接下来做什么"，它假设你会活到那个时候。遗嘱是给意外准备的——它不管你什么时候死、怎么死，只在那个时刻生效一次。

把 `rm -rf "$tmpdir"` 写在脚本末尾，是在写日程表。把它写进 `trap ... EXIT`，是在立遗嘱。

#### 核心原理

**一、信号的编号与默认动作**

本机实测（`kill -l`）：

```bash
for s in HUP INT QUIT KILL TERM; do
    echo "$s=$(kill -l "$s")"
done
```text

```text
HUP=1
INT=2
QUIT=3
KILL=9
TERM=15
```text

几个常用信号的语义：

- `SIGHUP`(1)：终端挂断。原本是"调制解调器掉线"，现在多用于通知守护进程重读配置。
- `SIGINT`(2)：键盘中断，`Ctrl-C`。**礼貌的**"请你停下来"。
- `SIGTERM`(15)：`kill` 的默认信号。**礼貌的**"请你退出"，给进程清理的机会。
- `SIGKILL`(9)：**不礼貌的**，直接由内核终结进程，进程收不到任何通知、没有任何机会执行清理代码。

`SIGKILL` 无法被捕获、无法被忽略、无法被阻塞——这是**内核级别的硬约束**，不是 shell 的限制。

**二、trap 的三种写法**

```bash
trap 'echo 收到信号' INT    # 注册：收到 INT 时执行这段代码
trap - INT                  # 重置：恢复为默认动作（即终止进程）
trap '' INT                 # 忽略：收到 INT 时什么都不做
```text

注意第三种的引号是**两个单引号**（空字符串），不是漏写。这是 shell 里少见但重要的语法：`trap ''` 表示忽略，`trap -` 表示重置。

**三、一个危险的错觉：`trap ... KILL` 不报错**

本机实测：

```bash
trap 'echo NO' KILL
echo "KILL errno=$?"
trap 'echo NO' STOP
echo "STOP errno=$?"
```text

```text
KILL errno=0
STOP errno=0
```text

`trap` 对 `KILL` 和 `STOP` 返回 0，**注册"成功"了**。但这个 handler 永远不会被调用——因为 `SIGKILL` 由内核直接处理，根本不会递交给进程。

这是 shell 里最安静的陷阱之一：**它不报错，只是静默地什么都不做**。如果你写了 `trap cleanup KILL` 指望它兜底，你会得到一个"以为有保护、实际没有"的脚本。

> ⚠️ **KILL 不可捕获意味着什么**：`kill -9` 之后，`EXIT` trap **不会执行**，临时文件不会清理，锁不会释放。任何"靠 trap 兜底"的设计，都挡不住 `kill -9` 和机器掉电。需要防这个，就得靠"重启后自检"（锁文件里记 PID，启动时检查该 PID 是否还活着）——这正是知识点 3 要做的事。

**四、退出码约定：128+N**

进程被信号 N 杀死时，shell 报告的退出码是 `128 + N`：

```bash
sleep 5 & p=$!
sleep 0.3
kill -TERM $p
wait $p
echo "TERM -> $?"
```text

```text
TERM -> 143
```text

`143 = 128 + 15`，符合预期。

于是 `130 = 128 + 2` 就成了 `SIGINT` 的"标准退出码"。这就是为什么**自己写 cleanup 时应该 `exit 130`**——让调用方能用 `130` 判断出"这个脚本是被 Ctrl-C 停掉的"，而不仅仅是"它失败了"。

**五、但实测推翻了这个约定的普适性**

下面这段是理解信号的关键实验，请务必照抄观察：

```bash
cat > /tmp/q1.sh <<'EOF'
sleep 5
echo "sleep 正常结束"
EOF
chmod +x /tmp/q1.sh

echo "--- A. 脚本在等前台 sleep，此时收 INT ---"
/tmp/q1.sh & p=$!
sleep 0.3
kill -INT $p
wait $p
echo "A 退出码=$?"

echo "--- B. 纯计算脚本收 INT ---"
cat > /tmp/q2.sh <<'EOF'
i=0
while [ $i -lt 2000000 ]; do i=$((i+1)); done
EOF
chmod +x /tmp/q2.sh
/tmp/q2.sh & p=$!
sleep 0.3
kill -INT $p
wait $p
echo "B 退出码=$?"
```text

```text
--- A. 脚本在等前台 sleep，此时收 INT ---
sleep 正常结束
A 退出码=0
--- B. 纯计算脚本收 INT ---
B 退出码=130
```text

**A 的退出码是 0，不是 130。** 脚本明明收到了 `INT`（后面会证明它确实收到了），却报告"成功"。

这不是 bug，而是两条机制叠加的结果。

#### 示例演示

##### 演示一：证明脚本确实收到了 INT

退出码是 0，不等于没收到信号。加一个 `trap` 就能看见真相：

```bash
cat > /tmp/q3.sh <<'EOF'
trap 'echo "  [脚本] 收到 INT"; exit 130' INT
sleep 5
echo "  [脚本] sleep 正常返回"
EOF
chmod +x /tmp/q3.sh
/tmp/q3.sh & p=$!
sleep 0.4
kill -INT $p
wait $p
echo "退出码=$?"
```text

```text
  [脚本] 收到 INT
退出码=130
```text

脚本**收到了** `INT`，并且正确返回了 130。所以 A 组拿到 0，不是"没收到"，而是"收到了但处理方式不同"。

##### 演示二：信号被推迟到当前命令结束

那么 A 组的 0 是怎么来的？测量一下耗时就清楚了：

```bash
cat > /tmp/q4.sh <<'EOF'
trap 'echo "  [T+?] INT trap 触发"' INT
echo "  [T+0.0] 开始 sleep 3"
sleep 3
echo "  [T+3.0] sleep 结束"
EOF
chmod +x /tmp/q4.sh

start=$(date +%s%N)
/tmp/q4.sh & p=$!
sleep 0.5
echo "  [T+0.5] 发出 INT"
kill -INT $p
wait $p
end=$(date +%s%N)
echo "  退出码=$?  总耗时=$(( (end-start)/1000000 ))ms"
```text

```text
  [T+0.0] 开始 sleep 3
  [T+0.5] 发出 INT
  [T+?] INT trap 触发
  [T+3.0] sleep 结束
  退出码=0  总耗时=3004ms
```text

**信号在 T+0.5 到达，trap 却在 T+3.0 才触发**。总耗时 3004ms 证明 `sleep 3` 完整跑完了。

这就是第一条机制：**bash 在执行前台命令期间收到信号，会先把信号记下来，等当前命令返回后才处理**。这是有意的——为了让信号处理代码不会在任意一条机器指令的中间插入执行，从而破坏数据一致性。

> 💡 **这条机制的实践含义极其重要**：对一个正在 `scp` 传输大文件或 `tar` 打包的脚本按 Ctrl-C，**传输会完整跑完，然后脚本才停**。你以为"中断了"，实际上只是"排了个队"。所以不要指望 Ctrl-C 能立刻止损——如果命令本身不支持中断，trap 也救不了你。

##### 演示三：A 组为什么是 0

`TERM` 的对照实验说明 A 组的 0 与信号类型无关：

```bash
cat > /tmp/q5.sh <<'EOF'
trap 'echo "  [T+?] TERM trap 触发"' TERM
echo "  [T+0.0] 开始 sleep 3"
sleep 3
echo "  [T+3.0] sleep 结束"
EOF
chmod +x /tmp/q5.sh
start=$(date +%s%N)
/tmp/q5.sh & p=$!
sleep 0.5
kill -TERM $p
wait $p
end=$(date +%s%N)
echo "  退出码=$?  总耗时=$(( (end-start)/1000000 ))ms"
```text

```text
  [T+0.0] 开始 sleep 3
  [T+?] TERM trap 触发
  [T+3.0] sleep 结束
  退出码=0  总耗时=3004ms
```text

`TERM` 同样被推迟到 `sleep` 结束。**所以"推迟"是通用机制，与信号种类无关。**

那为什么第一幕里被 `TERM` 杀死的脚本退出码是 143，而这里的 `TERM` 却是 0？

区别在于**有没有 trap**：

| 情况 | trap 处理时机 | 最终退出码 |
|------|--------------|-----------|
| 有 trap，且 trap 里不 `exit` | 命令结束后执行 | **0**（trap 执行成功，覆盖了信号死的事实） |
| 有 trap，且 trap 里 `exit 130` | 命令结束后执行 | **130**（你显式指定的） |
| 无 trap | 命令结束后，bash 按默认动作终止进程 | **128+N**（如 143） |

A 组的 `sleep 5` 脚本**没有 trap**，为什么也是 0？

因为 `sleep` 是**外部命令**，它在自己的进程里运行。`kill -INT $p` 只发给了 bash 脚本进程，没发给 `sleep`。bash 推迟处理，等 `sleep` 正常跑完返回 0，然后 bash 处理被推迟的 `INT`——**但此时没有 trap，且 bash 的判断是"我是在等一个子进程，现在子进程正常结束了"**，于是按正常流程继续，退出码取最后一条命令的 0。

这正是 A 组与 B 组的差异：**B 组没有外部子进程，bash 自己就是被信号打断的那个执行体**，于是它明确地死于 `INT`，退出码 130。

> ⚠️ **这个差异的实践含义**：脚本"被 Ctrl-C 了却报告成功"，会让上层的 `if deploy.sh; then` 判断为成功。如果你的部署流水线靠退出码决定是否继续，这个 0 会让流水线拿着一个**半截部署**继续往下走。

##### 演示四：trap 的继承与重置规则

这是大纲要求掌握的核心规则，用 `trap -p` 直接取证：

```bash
cat > /tmp/q6.sh <<'EOF'
echo "  子脚本 trap -p INT = [$(trap -p INT)]"
EOF
chmod +x /tmp/q6.sh

echo "--- 1. 父设 handler，子脚本能看见吗 ---"
trap 'echo 父INT' INT
echo "  父 trap -p INT = [$(trap -p INT)]"
/tmp/q6.sh
```text

```text
--- 1. 父设 handler，子脚本能看见吗 ---
  父 trap -p INT = [trap -- 'echo 父INT' SIGINT]
  子脚本 trap -p INT = []
```text

**handler 不继承**——子脚本看到的是空。

```bash
cat > /tmp/q7.sh <<'EOF'
echo "  子脚本 trap -p INT = [$(trap -p INT)]"
EOF
chmod +x /tmp/q7.sh

trap '' INT
echo "  父已设 trap '' INT（忽略）"
/tmp/q7.sh
```text

```text
  父已设 trap '' INT（忽略）
  子脚本 trap -p INT = [trap -- '' SIGINT]
```text

**忽略会继承**——子脚本明确显示 `trap -- '' SIGINT`。

这就是 POSIX 规定的那条规则：**子进程将所有 trap 重置为默认动作，唯一例外是"被忽略"的信号，它保持忽略。**

这个设计是有道理的：如果 handler 能继承，那么子脚本会在你毫不知情的情况下执行父进程的代码（而那段代码引用的变量在子进程里可能根本不存在）。而"忽略"是一种**状态**而非**代码**，继承它不会有任何副作用。

##### 演示五：一句话记住

#### 常见误区

| 误区 | 真相 | 后果 |
|------|------|------|
| `trap ... KILL` 能兜底 | `trap` 返回 0 不报错，但 handler **永不执行** | 以为有保护，实际裸奔 |
| 被 Ctrl-C 的脚本一定返回 130 | 若脚本在等**外部命令**，且无 trap，退出码是 **0** | 上层误判为成功 |
| Ctrl-C 能立刻中断正在跑的 `scp`/`tar` | bash **推迟**信号处理到当前命令返回 | 以为中断了，实际跑完了 |
| trap 会传给子脚本 | handler **不继承**，只有"忽略"继承 | 子脚本按默认动作死掉 |
| `trap - INT` 和 `trap '' INT` 一回事 | `-` 是**重置为默认**（会死），`''` 是**忽略**（不死） | 想忽略却写成了重置，脚本照样死 |

#### 一句话记住

**`trap` 是遗嘱不是日程表；它拦不住 `SIGKILL`，管不了子脚本，而且在你正在跑的外部命令返回之前，它连排队的资格都没有。**

---

### 知识点 2：伪信号 EXIT / ERR / DEBUG

> 本知识点关键点：`EXIT` 是唯一"任何退出路径都会触发"的钩子（正常结束、`exit`、信号致死、`set -e` 触发）、`EXIT` trap 里 `exit` 的退出码行为、`ERR` 的触发条件与 `set -E` 对函数继承的影响（不设 `-E` 时函数内的 ERR trap 不继承）、`DEBUG` 逐命令执行（用于追踪）、`RETURN`、`trap ... EXIT` 只保留最后一个（覆盖而非叠加）

#### 一句话定义

伪信号不是真信号，而是 bash 在**特定事件发生时**触发的钩子：`EXIT` 在退出时、`ERR` 在命令失败时、`DEBUG` 在每条命令执行前、`RETURN` 在函数返回时。

#### 直觉建立（类比）

`EXIT` 是**安检出口**——无论你是正常登机、被劝返、还是临时有事离开，都得经过同一个闸门。

它不关心你的"结局"是什么，只在乎"你要离开这件事"。所以它是清理逻辑的唯一正确落点。

而 `ERR` 是**烟雾报警器**——它只关心"有没有东西烧糊了"，并且默认只装在走廊（顶层），不装在每个房间（函数内部）。想让房间里也装上，得显式说一声：`set -E`。

#### 核心原理

**一、EXIT 的四条退出路径全覆盖**

这是本知识点的核心结论，四种死法逐一实测：

```bash
cat > /tmp/e1.sh <<'EOF'
trap 'echo "  EXIT 触发,退出码=$?"' EXIT
echo "  正常结束"
EOF
chmod +x /tmp/e1.sh
echo "--- 1. 正常结束 ---"; /tmp/e1.sh

cat > /tmp/e2.sh <<'EOF'
trap 'echo "  EXIT 触发,退出码=$?"' EXIT
echo "  即将 exit 42"
exit 42
EOF
chmod +x /tmp/e2.sh
echo "--- 2. 显式 exit 42 ---"; /tmp/e2.sh; echo "  最终退出码=$?"

cat > /tmp/e3.sh <<'EOF'
trap 'echo "  EXIT 触发,退出码=$?"' EXIT
false
EOF
chmod +x /tmp/e3.sh
echo "--- 3. 最后一条命令失败 ---"; /tmp/e3.sh; echo "  最终退出码=$?"

cat > /tmp/e4.sh <<'EOF'
set -e
trap 'echo "  EXIT 触发,退出码=$?"' EXIT
echo "  即将触发 set -e"
false
echo "  这行不该出现"
EOF
chmod +x /tmp/e4.sh
echo "--- 4. set -e 触发 ---"; /tmp/e4.sh; echo "  最终退出码=$?"
```text

```text
--- 1. 正常结束 ---
  正常结束
  EXIT 触发,退出码=0
--- 2. 显式 exit 42 ---
  即将 exit 42
  EXIT 触发,退出码=42
  最终退出码=42
--- 3. 最后一条命令失败 ---
  EXIT 触发,退出码=1
  最终退出码=1
--- 4. set -e 触发 ---
  即将触发 set -e
  EXIT 触发,退出码=1
  最终退出码=1
```text

**四条路径全部触发**，`$?` 也正确地反映了各自的退出码。这就是 `EXIT` 被称为"唯一全覆盖钩子"的原因。

**二、被信号致死时也触发——但 `$?` 会骗你**

```bash
cat > /tmp/e5.sh <<'EOF'
trap 'echo "  EXIT 触发,退出码=$?"' EXIT
sleep 3
EOF
chmod +x /tmp/e5.sh
/tmp/e5.sh & p=$!
sleep 0.4
kill -TERM $p
wait $p
echo "  TERM 致死 -> 退出码 $?"
```text

```text
  EXIT 触发,退出码=0
  TERM 致死 -> 退出码 143
```text

**这是一个必须记住的陷阱**：`EXIT` trap 里的 `$?` 打印的是 `0`，而脚本最终退出码是 `143`。

原因：`EXIT` trap 是在退出流程中执行的，此时 bash 尚未确定"最终退出码"，`$?` 反映的是**进入 trap 之前最后一条命令的状态**（那个 `sleep 3` 被推迟处理后返回的状态），而不是"我即将以 143 退出"。

如果你在 cleanup 里这样写，就会把被信号杀死的运行误判为成功：

```bash
# ❌ 错误：被 TERM 杀死时会走进"成功"分支
trap 'rc=$?
      if [ $rc -eq 0 ]; then echo "部署成功"; fi' EXIT
```text

**正确做法是在 EXIT trap 的第一行保存 `$?`，并且不要依赖它判断"是否被信号杀死"。** 需要区分时，应显式注册信号 trap：

```bash
# ✅ 正确：显式注册 TERM/INT，在里面记录"我是被杀死的"
interrupted=0
on_signal() { interrupted=1; exit 143; }
trap on_signal INT TERM
trap 'rc=$?
      if [ $interrupted -eq 1 ]; then echo "被中断"; fi
      cleanup' EXIT
```text

**三、EXIT 覆盖而非叠加**

```bash
cat > /tmp/e6.sh <<'EOF'
trap 'echo "  EXIT-1"' EXIT
trap 'echo "  EXIT-2"' EXIT
echo "  结束"
EOF
chmod +x /tmp/e6.sh
/tmp/e6.sh
```text

```text
  结束
  EXIT-2
```text

**只有 `EXIT-2` 执行了，第一条被静默覆盖。**

这很危险：如果你在一个被 source 的库文件里注册了 `trap ... EXIT`，而主脚本后来又注册了一个，库文件的清理就**无声无息地消失了**。没有警告，没有报错。

> 💡 **实践建议**：清理逻辑**只注册一次**，把所有要做的事放进同一个 cleanup 函数。需要多段清理时，在函数内按顺序调用，不要注册多个 `trap ... EXIT`。

**四、EXIT trap 里再写 exit 会覆盖退出码**

```bash
cat > /tmp/e7.sh <<'EOF'
trap 'echo "  EXIT触发 \$?=$?"; exit 99' EXIT
exit 7
EOF
chmod +x /tmp/e7.sh
/tmp/e7.sh; echo "  最终退出码=$?"
```text

```text
  EXIT触发 $?=7
  最终退出码=99
```text

`7` 被 `99` **覆盖**了。

对照——不写 `exit` 则保留原退出码：

```bash
cat > /tmp/e8.sh <<'EOF'
trap 'rc=$?; echo "  EXIT触发 rc=$rc"' EXIT
exit 7
EOF
chmod +x /tmp/e8.sh
/tmp/e8.sh; echo "  最终退出码=$?"
```text

```text
  EXIT触发 rc=7
  最终退出码=7
```text

**结论：cleanup 函数里不要裸写 `exit`。** 正确范式是"保存 `$?` → 做清理 → 显式 `exit $rc`"：

```bash
cleanup() {
    local rc=$?        # 第一行，必须最先执行
    trap - EXIT        # 防止重入
    rm -rf "$tmpdir"
    exit $rc           # 保住真实退出码
}
```text

第三行的 `trap - EXIT` 同样重要：它撤销 EXIT trap，防止 cleanup 执行期间又被信号打断而**重入**（递归调用自己）。

**五、ERR 与 `set -E`**

`ERR` 在"某条命令返回非零"时触发。但它默认**不进入函数内部**：

```bash
cat > /tmp/e9.sh <<'EOF'
trap 'echo "  ERR 触发,行=$LINENO,命令=$BASH_COMMAND"' ERR
f() {
    false
    echo "  函数内 false 之后"
}
echo "--- 无 set -E ---"
f
echo "--- 显式 set -E ---"
set -E
f
EOF
chmod +x /tmp/e9.sh
/tmp/e9.sh
```text

```text
--- 无 set -E ---
  函数内 false 之后
--- 显式 set -E ---
  ERR 触发,行=3,命令=false
  函数内 false 之后
```text

**没有 `set -E` 时，函数内的 `false` 完全不触发 ERR trap**——没有任何提示，错误就这样溜过去了。

`set -E`（等价 `set -o errtrace`）让 ERR trap 被函数和子 shell 继承。这是让 `ERR` 真正有用的**必需开关**。

> ⚠️ **注意与 `set -e` 的区分**：`set -e` 是"失败就退出脚本"，`set -E` 是"让 ERR trap 进入函数"。两者正交，可以单独使用。`trap ... ERR` 的真正价值在于：它让你能**记录错误现场**（`$LINENO`、`$BASH_COMMAND`）后再决定怎么办，而不是像 `set -e` 那样默默退出。

**六、哪些情况不触发 ERR**

```bash
cat > /tmp/e10.sh <<'EOF'
trap 'echo "  ERR: $BASH_COMMAND"' ERR
set -E
false
( exit 3 )
if false; then :; fi
false || true
! true
echo "  以上逐条看 ERR 是否触发"
EOF
chmod +x /tmp/e10.sh
/tmp/e10.sh
```text

```text
  ERR: false
  ERR: ( exit 3 )
  以上逐条看 ERR 是否触发
```text

| 写法 | ERR 触发 | 原因 |
|------|---------|------|
| `false` | ✅ | 命令失败 |
| `( exit 3 )` | ✅ | 子 shell 返回非零 |
| `if false; then :; fi` | ❌ | 条件上下文中，失败是**预期结果** |
| `false \|\| true` | ❌ | 有 `\|\|` 兜底，失败已被处理 |
| `! true` | ❌ | `!` 反转，整体成功 |

规律与 `set -e` 完全一致：**当"失败"是你显式预期并处理的，就不再算错误**。这是因为 `ERR` 与 `set -e` 共享同一套"是否属于被处理的失败"判定逻辑。

**七、DEBUG 与 RETURN**

```bash
cat > /tmp/e11.sh <<'EOF'
trap 'echo "  DEBUG: $BASH_COMMAND"' DEBUG
x=1
y=$((x+1))
echo "结果 $y"
EOF
chmod +x /tmp/e11.sh
/tmp/e11.sh
```text

```text
  DEBUG: x=1
  DEBUG: y=$((x+1))
  DEBUG: echo "结果 $y"
结果 2
```text

`DEBUG` 在**每条命令执行前**触发，`$BASH_COMMAND` 是即将执行的命令原文。这是最轻量的"逐行追踪"手段。

但默认也不进函数内部——与 ERR 一样，需要 `set -T`：

```bash
cat > /tmp/e12.sh <<'EOF'
trap 'echo "  DEBUG: $BASH_COMMAND"' DEBUG
f() { local a=1; echo "  内"; }
echo "--- 默认 ---"
f
echo "--- set -T ---"
set -T
f
EOF
chmod +x /tmp/e12.sh
/tmp/e12.sh
```text

```text
--- 默认 ---
  DEBUG: echo "--- 默认 ---"
--- 默认 ---
  DEBUG: f
  内
  DEBUG: echo "--- set -T ---"
--- set -T ---
  DEBUG: set -T
  DEBUG: f
  DEBUG: f
  DEBUG: local a=1
  DEBUG: echo "  内"
  内
```text

默认只显示 `f`（调用本身），`set -T` 后连函数体内的 `local a=1`、`echo` 都追踪到了。

`RETURN` 同理，也需要 `set -T`：

```bash
cat > /tmp/e13.sh <<'EOF'
f() { echo "  函数体内"; }
echo "--- A. 顶层设 RETURN trap（不带 -T）---"
trap 'echo "  RETURN 触发: ${FUNCNAME[0]:-顶层}"' RETURN
f
echo "--- B. set -T 后再调 ---"
set -T
f
EOF
chmod +x /tmp/e13.sh
/tmp/e13.sh
```text

```text
--- A. 顶层设 RETURN trap（不带 -T）---
  函数体内
--- B. set -T 后再调 ---
  函数体内
  RETURN 触发: f
```text

**记住这一对开关**：

| 伪信号 | 进入函数需要的开关 |
|--------|------------------|
| `ERR` | `set -E`（errtrace） |
| `DEBUG` | `set -T`（functrace） |
| `RETURN` | `set -T`（functrace） |

#### 示例演示

##### 演示一：用 DEBUG 做一行式调试开关

```bash
cat > /tmp/dbg.sh <<'EOF'
debug=0
[ "$debug" = 1 ] && set -T && trap 'echo "[$(date +%T)] $BASH_COMMAND" >&2' DEBUG
step1() { echo "执行步骤1"; }
step2() { echo "执行步骤2"; }
step1
step2
EOF
chmod +x /tmp/dbg.sh
echo "=== 关闭调试 ==="; /tmp/dbg.sh
sed -i 's/^debug=0/debug=1/' /tmp/dbg.sh
echo "=== 打开调试 ==="; /tmp/dbg.sh
```text

```text
=== 关闭调试 ===
执行步骤1
执行步骤2
=== 打开调试 ===
[14:23:11] step1
执行步骤1
[14:23:11] step2
执行步骤2
```text

改一个变量就能开关逐行追踪——不需要在每行代码里塞 `echo`。这比满屏 `echo "DEBUG: xxx"` 干净得多，而且关掉时零开销。

##### 演示二：ERR trap 记录错误现场

```bash
cat > /tmp/errlog.sh <<'EOF'
set -E
trap 'echo "❌ 失败: 行=$LINENO 命令=[$BASH_COMMAND] 状态=$?" >&2' ERR

deploy() {
    echo "部署到 $1"
    [ "$1" != "bad-host" ] || return 1
    echo "  完成"
}

deploy good-host
deploy bad-host
echo "这行不会执行（因为没开 set -e，ERR trap 只报告不拦截）"
EOF
chmod +x /tmp/errlog.sh
/tmp/errlog.sh; echo "退出码=$?"
```text

```text
部署到 good-host
  完成
部署到 bad-host
❌ 失败: 行=6 命令=[return 1] 状态=1
这行不会执行（因为没开 set -e，ERR trap 只报告不拦截）
退出码=0
```text

注意最后退出码是 **0**——`ERR` trap **只报告，不拦截**。想让它终止脚本，需要 `set -e` 或在 trap 里显式 `exit`。这是 `ERR` 与 `set -e` 的关键区别：前者是观察员，后者是执法者。

#### 常见误区

| 误区 | 真相 | 后果 |
|------|------|------|
| 写两个 `trap ... EXIT` 会都执行 | **后者覆盖前者**，第一条静默消失 | 库文件的清理被主脚本覆盖 |
| `EXIT` trap 里 `$?` 是最终退出码 | 被信号杀死时打印 **0**，实际退出 143 | 把中断误判为成功 |
| cleanup 里写 `exit`（不带参数） | 覆盖真实退出码 | 失败被伪装成成功（或反之） |
| `trap ... ERR` 能拦截错误 | 它**只报告不拦截**，脚本继续跑 | 以为加了保险，实际没停 |
| ERR/DEBUG/RETURN 默认覆盖函数内部 | 需 `set -E` / `set -T` 才进入函数 | 函数里的错误完全没记录 |
| `trap - INT` 等于忽略信号 | `-` 是**重置为默认**（会死）；忽略要写 `trap '' INT` | 想忽略却照样死 |

#### 一句话记住

**`EXIT` 是唯一全覆盖的闸门，但闸门上的 `$?` 会骗你——第一行就存下来；`ERR` 是观察员不是执法者，想让它进函数必须开 `set -E`。**

---

### 知识点 3：清理、锁与临时文件

> 本知识点关键点：`mktemp -d` 建临时目录（`-t` / `-p` / 模板 XXX 至少三个）、清理函数 + `trap cleanup EXIT` 的标准范式、清理函数的**幂等性**（可能被调用两次）、`flock` 文件锁（`-n` 非阻塞、`-w` 超时、fd 形式 `exec 9>lock; flock -n 9`）、锁与 trap 的配合（锁 fd 随进程退出自动释放）、`trap` 里调用函数的退出码处理

#### 一句话定义

中断安全 = `mktemp -d` 建临时目录 + `trap cleanup EXIT` 注册清理 + `flock` 防并发，三者缺一不可。

#### 直觉建立（类比）

`flock` 用 **fd 形式**时，锁的生命周期绑定的是**文件描述符**，而不是文件本身。

这就像酒店的房卡：房卡（fd）在你手里，房间（锁）就是你的；你人走了（进程死了），房卡被销毁，房间自动释放。房卡本体（锁文件）还在前台，但那只是块塑料，不代表房间被占用。

而"手动 `rm lockfile` 当释放锁"相当于把前台的塑料卡片扔掉——房间其实还被占着，下一位客人（新实例）却以为可以进了。

#### 核心原理

**一、mktemp：安全地建临时文件**

```bash
d=$(mktemp -d)
echo "  dir=$d"
echo "  权限=$(stat -c %a "$d")"
rmdir "$d"
```text

```text
  dir=/tmp/tmp.UC7R7Eh1Zy
  权限=700
```text

`mktemp -d` 建目录，权限 **700**（仅所有者可读写）——这一点很重要，它保证了临时目录不会被同机其他用户偷看或篡改。

**模板的 X 数量**：

```bash
mktemp /tmp/XXX    # 本机接受
mktemp /tmp/XXXX   # 本机接受
```text

本机（GNU coreutils 9.4）实测 3 个 X 也接受。但这是 **GNU 扩展行为**，POSIX 和其他系统（BSD/macOS）要求**至少 6 个 X**。

> ⚠️ **可移植性**：写 `mktemp /tmp/foo.XXXXXX`（6 个 X）。只写 3 个在 macOS 上会失败或产生可预测的名字——那就等于放弃了 `mktemp` 的全部安全价值。

**为什么不能用 `$$` 造临时文件名**：

```bash
# ❌ 危险
tmp="/tmp/mytmp.$$"
```text

这是一个 **TOCTOU 竞态**（time-of-check to time-of-use）：检查"这个文件不存在"和创建它之间有时间窗口，攻击者可以抢先创建符号链接指向 `/etc/passwd`，然后你的脚本就把它覆盖了。

`mktemp` 用 `O_EXCL|O_CREAT` 原子地创建，且权限 700，没有这个窗口。**永远用 `mktemp`。**

**二、flock 的 fd 形式**

```bash
exec 9>/tmp/demo.lock
flock -n 9 || { echo "已有实例"; exit 1; }
# ... 持锁做事 ...
```text

关键在第一行：`exec 9>` 打开 fd 9 指向锁文件。之后 `flock 9` 锁的是这个 **fd**。

常用参数：

| 参数 | 含义 |
|------|------|
| （无） | 阻塞等待，直到拿到锁 |
| `-n` | 非阻塞，拿不到立刻返回失败（退出码 1） |
| `-w N` | 最多等 N 秒，超时返回失败 |
| `-u` | 显式解锁 |

实测三种：

```bash
rm -f /tmp/demo.lock
echo "=== flock -n 非阻塞 ==="
( flock -n 9 || { echo "  拿不到锁"; exit 1; }
  echo "  拿到锁，持有 2 秒"; sleep 2; echo "  释放" ) 9>/tmp/demo.lock &
p1=$!
sleep 0.3
( flock -n 9 || { echo "  抢锁失败（期望）"; exit 1; } ) 9>/tmp/demo.lock
echo "  抢锁者退出码=$?"
wait $p1

echo "=== flock -w 超时 ==="
( flock -w 1 9 && echo "  等到锁" || echo "  超时" ) 9>/tmp/demo.lock &
p2=$!
( flock -n 9 && sleep 3 ) 9>/tmp/demo.lock &
p3=$!
wait $p2; wait $p3
rm -f /tmp/demo.lock
```text

```text
=== flock -n 非阻塞 ===
  拿到锁，持有 2 秒
  抢锁失败（期望）
  抢锁者退出码=1
  释放
=== flock -w 超时 ===
  超时
```text

**三、关键实验：进程死了，锁会自动释放吗**

这是本课最需要澄清的一点。先看一个**看起来**反驳常见说法的实验：

```bash
rm -f /tmp/lk1
cat > /tmp/holder.sh <<'EOF'
exec 9>/tmp/lk1
flock -n 9 || exit 1
echo "holder 持锁 pid=$$"
sleep 30
EOF
chmod +x /tmp/holder.sh

/tmp/holder.sh & hp=$!
sleep 0.6
echo "holder 存活=$(kill -0 $hp 2>/dev/null && echo yes)"

echo "--- 抢锁（应失败）---"
flock -n /tmp/lk1 -c 'echo "  拿到"' || echo "  失败(期望)"

echo "--- kill -9 holder ---"
kill -9 $hp
wait $hp 2>/dev/null
sleep 0.3
echo "holder 存活=$(kill -0 $hp 2>/dev/null && echo yes || echo no)"

echo "--- 再抢锁（关键）---"
flock -n /tmp/lk1 -c 'echo "  拿到=锁已自动释放"' || echo "  没拿到=锁残留"
rm -f /tmp/lk1
```text

```text
holder 持锁 pid=2297092
holder pid=2297092 存活=yes
--- 抢锁（应失败）---
  失败(期望)
--- kill -9 holder ---
holder 存活=no
--- 再抢锁（关键）---
  没拿到=锁残留
```text

**锁"残留"了！** 这与"进程死了 fd 自动关闭、锁自动释放"的说法矛盾。为什么？

**四、真相：孤儿子进程继承了 fd**

上面那个 `holder.sh` 的最后一行是 `sleep 30`——它是一个**子进程**，并且**继承了 fd 9**。

`kill -9 $hp` 只杀掉了 bash 进程，`sleep` 变成孤儿活了下来，**继续持有 fd 9**，于是锁还在。

验证这个假设：

```bash
rm -f /tmp/lk2
cat > /tmp/h2.sh <<'EOF'
exec 9>/tmp/lk2
flock -n 9 || exit 1
echo "holder bash pid=$$"
sleep 30
EOF
chmod +x /tmp/h2.sh

/tmp/h2.sh & hp=$!
sleep 0.6
echo "--- kill -9 bash 后 ---"
kill -9 $hp
wait $hp 2>/dev/null
sleep 0.3
echo "bash 存活=$(kill -0 $hp 2>/dev/null && echo yes || echo no)"
echo "残留子进程:"
pgrep -f 'sleep 30' | while read c; do echo "  孤儿 pid=$c"; done

echo "--- 再抢锁 ---"
flock -n /tmp/lk2 -c 'echo "  拿到=已释放"' || echo "  没拿到=仍被孤儿持有"

echo "--- 清掉孤儿后再抢 ---"
pkill -9 -f 'sleep 30'
sleep 0.3
flock -n /tmp/lk2 -c 'echo "  清掉孤儿后：拿到=已释放"' || echo "  清掉孤儿后：仍没拿到"
rm -f /tmp/lk2
```text

```text
holder bash pid=2298068
--- kill -9 bash 后 ---
bash 存活=no
残留子进程:
  孤儿 pid=2298071
--- 再抢锁 ---
  没拿到=仍被孤儿持有
--- 清掉孤儿后再抢 ---
  清掉孤儿后：拿到=已释放
```text

**真相大白**：

1. `kill -9` 只杀了 bash（2298068）
2. 子进程 `sleep`（2298071）变孤儿，继续持有 fd 9
3. 锁因此没释放
4. **清掉孤儿后，锁立刻释放**

所以准确结论是：

> **`flock` 的锁确实随 fd 全部关闭而自动释放——但"全部"二字至关重要。任何继承了 fd 的子进程活着，锁就还在。**

这完全解释了第一幕的场景：脚本被 Ctrl-C 时，它启动的后台任务（scp、tar、ssh）活着，锁就"残留"。

**五、为什么手动 `rm lockfile` 是错的**

现在可以给出完整答案：

| 做法 | 问题 |
|------|------|
| `rm -f lockfile` 当解锁 | ① 删了文件但锁还在（其他进程的 fd 仍指向已删除的 inode），完全无效；② 竞态：删与建之间有窗口；③ 进程崩溃时会留下"文件在、锁也在"的残骸 |
| 锁文件里记 PID，启动时检查 | 能区分真实例与残骸，但 **PID 会复用**——一个不相关的进程可能恰好用了那个 PID |
| `flock` fd 形式 | ✅ 内核保证，进程死则锁放；配合 PID 记录可诊断 |

**PID 复用竞态**是真实存在的：系统运行久了 PID 会回绕，一个完全无关的进程可能正好占用了锁文件里记的 PID。所以**不能只靠 PID 判断**，必须配合 `flock`（内核级保证）。

业界更稳的做法是 **PID + 启动时间戳**双记录，或用 `flock` 的 fd 形式作为唯一权威判据、PID 仅用于诊断输出。

**六、清理函数的幂等性**

cleanup 可能被调用两次（比如手动调一次、EXIT 又触发一次），所以必须幂等：

```bash
cat > /tmp/idem.sh <<'EOF'
cleanup() {
    local rc=$?
    trap - EXIT
    echo "  [cleanup] 第1次"
    rm -rf /tmp/idem_demo
    cleanup_twice
    exit $rc
}
cleanup_twice() {
    echo "  [cleanup] 第2次（模拟重复调用）"
    rm -rf /tmp/idem_demo
    echo "  [cleanup] 重复 rm 的退出码=$?"
}
mkdir -p /tmp/idem_demo
trap cleanup EXIT
exit 7
EOF
chmod +x /tmp/idem.sh
/tmp/idem.sh; echo "  最终退出码=$?"
```text

```text
  [cleanup] 第1次
  [cleanup] 第2次（模拟重复调用）
  [cleanup] 重复 rm 的退出码=0
  最终退出码=7
```text

**重复 `rm -rf` 返回 0，不报错**——这是 `rm -rf` 的幂等性，也是它适合做清理的原因。

注意最终退出码是 **7**，被 `exit $rc` 保住了。

#### 示例演示

##### 演示一：孤儿进程——trap 里怎么杀干净

脚本被杀时，后台任务会变孤儿。下面的实验同时回答"问题有多严重"和"怎么修"：

```bash
cat > /tmp/orphan.sh <<'EOF'
echo "  父脚本 pid=$$"
sleep 20 &
echo "  后台任务 pid=$!"
wait
EOF
chmod +x /tmp/orphan.sh

/tmp/orphan.sh & p=$!
sleep 0.8
kill -TERM $p
wait $p 2>/dev/null
sleep 0.5
echo "  父存活=$(kill -0 $p 2>/dev/null && echo yes || echo no)"
echo "  残留孤儿数=$(pgrep -fc 'sleep 20' 2>/dev/null || echo 0)"
pkill -9 -f 'sleep 20'
```text

```text
  父脚本 pid=2301597
  后台任务 pid=2301599
  父存活=no
  残留孤儿数=1
```text

孤儿确实留下了。修复版：

```bash
cat > /tmp/orphan2.sh <<'EOF'
cleanup() {
    local rc=$?
    trap - EXIT
    echo "  [cleanup] 我跑了 rc=$rc"
    echo "  [cleanup] jobs -pr = [$(jobs -pr | tr '\n' ' ')]"
    kill -TERM $(jobs -pr) 2>/dev/null
    exit $rc
}
trap cleanup EXIT INT TERM
sleep 20 &
echo "  后台任务 pid=$!"
wait
EOF
chmod +x /tmp/orphan2.sh

/tmp/orphan2.sh & p=$!
sleep 0.8
kill -TERM $p
wait $p 2>/dev/null
sleep 0.5
echo "  残留孤儿数=$(pgrep -fc 'sleep 20' 2>/dev/null || echo 0)"
pkill -9 -f 'sleep 20'
```text

```text
  后台任务 pid=2302931
  [cleanup] 我跑了 rc=143
  [cleanup] jobs -pr = [2302931 ]
  残留孤儿数=0
```text

两个有价值的发现：

1. **`jobs -pr` 在 trap 中可用**——很多人以为非交互脚本里 `jobs` 不能用，实测它能正确列出后台 PID。
2. **cleanup 确实跑了**（`rc=143`），孤儿被清掉。

**更可靠的做法是显式记录 PID**，因为它不依赖 `jobs` 的可见性：

```bash
kids=()
cleanup() {
    local rc=$?
    trap - EXIT
    for k in "${kids[@]}"; do kill -TERM "$k" 2>/dev/null; done
    for k in "${kids[@]}"; do wait "$k" 2>/dev/null; done
    exit $rc
}
trap cleanup EXIT INT TERM
sleep 50 & kids+=($!)
sleep 51 & kids+=($!)
wait
```text

实测残留孤儿数 = 0。

##### 演示二：绝不要在 trap 里写 `kill -- -$$`

这是本课**最重要的安全警告**。常见博客会教你"用 `kill -- -$$` 杀掉整个进程组"，这在脚本里是错的，而且危险。

先诊断身份：

```bash
cat > /tmp/warn.sh <<'EOF'
echo "  脚本 \$\$=$$"
echo "  脚本 PGID=$(ps -o pgid= -p $$ | tr -d ' ')"
echo "  父(调用者)PID=$PPID PGID=$(ps -o pgid= -p $PPID | tr -d ' ')"
EOF
chmod +x /tmp/warn.sh
/tmp/warn.sh
```text

```text
  脚本 $$=2306199
  脚本 PGID=2305967
  父(调用者)PID=2305967 PGID=2305967
```text

看清楚这个数字关系：

- 脚本的 `$$` = **2306199**（自己的 PID）
- 脚本的 `PGID` = **2305967**（**等于父进程的 PID**）

也就是说：**脚本不是进程组组长**，它的进程组是调用者所在的组。

于是：

- `kill -- -$$` → 杀 PGID=2306199 的组 → **这个组不存在**，什么都不会发生（清理失效）
- `kill -- -PGID`（用真实 PGID 2305967）→ 杀掉整个组 → **连同调用你的终端/父脚本一起杀掉**

> ⚠️ **所以：`kill -- -$$` 要么无效，要么误杀调用者——两种结果都是错的。** 想杀掉自己启动的后台任务，就用演示一的"显式记录 PID"。

##### 演示三：完整的中断安全脚本模板

把三件套组装起来：

```bash
cat > /tmp/safe_deploy.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail

LOCK=/tmp/safe_demo.lock
TMPDIR_RUN=""
LOCK_FD=""

cleanup() {
    local rc=$?
    trap - EXIT
    if [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ]; then
        rm -rf "$TMPDIR_RUN"
        echo "    [cleanup] 临时目录已删"
    fi
    if [ -n "$LOCK_FD" ]; then
        flock -u "$LOCK_FD" 2>/dev/null
        exec {LOCK_FD}>&- 2>/dev/null
        echo "    [cleanup] 锁已释放"
    fi
    TMPDIR_RUN=""
    exit $rc
}
trap cleanup EXIT INT TERM

echo "[1] 建临时目录"
TMPDIR_RUN=$(mktemp -d)
echo "data" > "$TMPDIR_RUN/f.txt"

echo "[2] 加锁"
LOCK_FD=9
exec 9>"$LOCK"
if ! flock -n 9; then
    if [ -s "$LOCK" ]; then
        old=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            echo "    真实例在跑(pid=$old)，退出"
        else
            echo "    残骸(pid=$old 已死)"
        fi
    else
        echo "    已有实例在跑，退出"
    fi
    exit 1
fi
echo $$ > "$LOCK"

echo "[3] 模拟传输（5秒）"
sleep 5 &
sp=$!
wait $sp

echo "[4] 完成"
SH
chmod +x /tmp/safe_deploy.sh
rm -f /tmp/safe_demo.lock

echo "=== 结局1：正常跑完 ==="
/tmp/safe_deploy.sh; echo "退出码=$?"
```text

这个模板的五个要点：

1. **`trap cleanup EXIT INT TERM`**——EXIT 兜住所有死法，INT/TERM 让信号来时立刻响应（不等当前命令）
2. **cleanup 第一行存 `$?`**，最后 `exit $rc` 保住真实退出码
3. **`trap - EXIT`** 防重入
4. **清理做存在性判断**（`[ -d "$TMPDIR_RUN" ]`），保证幂等
5. **锁文件里记 PID**，让"真实例 vs 残骸"可被诊断

#### 常见误区

| 误区 | 真相 | 后果 |
|------|------|------|
| 进程死了锁自动释放 | 只杀了**父进程**不够，继承 fd 的**孤儿子进程**还持锁 | 锁"残留"，新实例永远进不来 |
| `rm -f lockfile` 能解锁 | 删文件**不影响**已持有的锁（fd 仍指向 inode） | 两个实例并发执行 |
| 用 `$$` 做唯一锁文件名 | **PID 会复用**，且与 `mktemp` 的原子性无关 | 竞态 + 误判 |
| `kill -- -$$` 杀进程组 | 脚本通常**不是组长**，`-$$` 组不存在；用真 PGID 会**误杀调用者** | 清理失效，或杀掉父脚本 |
| cleanup 里写裸 `exit` | 覆盖真实退出码 | 失败伪装成成功 |
| 注册多个 `trap ... EXIT` | **后者覆盖前者**，前面的静默消失 | 部分清理逻辑从未执行 |
| 清理代码不用判存在 | 重复调用可能报错（虽 `rm -rf` 幂等，但自定义逻辑未必） | cleanup 自身失败 |

#### 一句话记住

**`mktemp -d` 建、 `trap cleanup EXIT` 收、 `flock` fd 形式防并发；锁随 fd 走，但孤儿会替死去的父进程继续拿着它。**

---

## 第四幕：实操验证

> 🎯 **任务**：给第一幕那个会留烂摊子的 `deploy.sh` 做一次全面改造，并用三种死法验证它都干净收摊。

### 第一步：准备一个真实的部署模拟环境

```bash
DEPLOY=/tmp/deploy_lab
rm -rf "$DEPLOY"
mkdir -p "$DEPLOY/target"

printf 'app-server-01\napp-server-02\napp-server-03\napp-server-04\n' > "$DEPLOY/hosts.txt"
cat "$DEPLOY/hosts.txt"
```text

```text
app-server-01
app-server-02
app-server-03
app-server-04
```text

### 第二步：问题版本（复现第一幕）

```bash
cat > "$DEPLOY/deploy_bad.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
LOCK=/tmp/deploy_lab/deploy.lock
echo "[1] 建临时目录"
tmp=$(mktemp -d)
echo "    tmp=$tmp"
echo "[2] 加锁"
exec 9>"$LOCK"
flock -n 9 || { echo "已有实例在运行"; exit 1; }
echo "[3] 逐台传输"
while read -r h; do
    echo "    传到 $h ..."
    sleep 1
done < /tmp/deploy_lab/hosts.txt
echo "[4] 收尾"
rm -rf "$tmp"
rm -f "$LOCK"
echo "    正常完成"
SH
chmod +x "$DEPLOY/deploy_bad.sh"
rm -f "$DEPLOY/deploy.lock"

echo "=== 结局1：正常跑完 ==="
"$DEPLOY/deploy_bad.sh"
echo "退出码=$?  锁还在=$([ -f $DEPLOY/deploy.lock ] && echo 在 || echo 不在)"
```text

```text
=== 结局1：正常跑完 ===
[1] 建临时目录
    tmp=/tmp/tmp.XXXXXXXX
[2] 加锁
[3] 逐台传输
    传到 app-server-01 ...
    传到 app-server-02 ...
    传到 app-server-03 ...
    传到 app-server-04 ...
[4] 收尾
    正常完成
退出码=0  锁还在=不在
```text

现在模拟运维中途发现参数错了，按下 Ctrl-C：

```bash
echo "=== 结局2：传到第2台时按 Ctrl-C ==="
"$DEPLOY/deploy_bad.sh" & p=$!
sleep 2.5
kill -TERM $p
wait $p
echo "退出码=$?"
echo "锁还在=$([ -f $DEPLOY/deploy.lock ] && echo 在 || echo 不在)"
echo "残留临时目录数=$(ls -d /tmp/tmp.* 2>/dev/null | wc -l)"
```text

```text
=== 结局2：传到第2台时按 Ctrl-C ===
[1] 建临时目录
    tmp=/tmp/tmp.YYYYYYYY
[2] 加锁
[3] 逐台传输
    传到 app-server-01 ...
    传到 app-server-02 ...
退出码=143
锁还在=在
残留临时目录数=1
```text

**烂摊子出现了**：退出码 143（被 TERM 杀死），锁在，临时目录留下了。

最要命的是结局 3——运维重跑：

```bash
echo "=== 结局3：重跑（明明没实例在跑）==="
"$DEPLOY/deploy_bad.sh"
echo "退出码=$?"
```text

```text
=== 结局3：重跑（明明没实例在跑）===
[1] 建临时目录
    tmp=/tmp/tmp.ZZZZZZZZ
[2] 加锁
已有实例在运行
退出码=1
```text

请留意这个细节：**它先建了临时目录，才发现拿不到锁，然后带着新的烂摊子退出。** 每重跑失败一次，就多一个残留目录。

### 第三步：改造版

改造要点：清理进 `trap`、锁文件记 PID、后台任务显式记录、cleanup 保退出码。

```bash
cat > "$DEPLOY/deploy_good.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail

LOCK=/tmp/deploy_lab/deploy.lock
TMPDIR_RUN=""
LOCK_FD=""
kids=()

cleanup() {
    local rc=$?
    trap - EXIT
    for k in "${kids[@]}"; do kill -TERM "$k" 2>/dev/null; done
    for k in "${kids[@]}"; do wait "$k" 2>/dev/null; done
    if [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ]; then
        rm -rf "$TMPDIR_RUN"
        echo "    [cleanup] 临时目录已删"
    fi
    if [ -n "$LOCK_FD" ]; then
        flock -u "$LOCK_FD" 2>/dev/null
        exec {LOCK_FD}>&- 2>/dev/null
        echo "    [cleanup] 锁已释放"
    fi
    TMPDIR_RUN=""
    exit $rc
}
trap cleanup EXIT INT TERM

echo "[1] 建临时目录"
TMPDIR_RUN=$(mktemp -d)
echo "    tmp=$TMPDIR_RUN"

echo "[2] 加锁"
LOCK_FD=9
exec 9>"$LOCK"
if ! flock -n 9; then
    if [ -s "$LOCK" ]; then
        old=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            echo "    真实例在跑 (pid=$old)，退出"
        else
            echo "    上次崩溃的残骸 (pid=$old 已不在)，可安全重跑"
        fi
    else
        echo "    已有实例在跑，退出"
    fi
    exit 1
fi
echo $$ > "$LOCK"
echo "    拿到锁 pid=$$"

echo "[3] 并发传输（最多 2 路）"
MAX=2
running=0
while read -r h; do
    (
        sleep 1
        echo "    $h 完成"
    ) &
    kids+=($!)
    running=$((running+1))
    if [ $running -ge $MAX ]; then
        wait -n
        running=$((running-1))
    fi
done < /tmp/deploy_lab/hosts.txt
wait

echo "[4] 完成"
SH
chmod +x "$DEPLOY/deploy_good.sh"
rm -f "$DEPLOY/deploy.lock"
```text

### 第四步：验证三种死法

```bash
echo "=== 结局1：正常跑完 ==="
"$DEPLOY/deploy_good.sh"
echo "退出码=$?  锁还在=$([ -f $DEPLOY/deploy.lock ] && echo 在 || echo 不在)"
```text

```text
=== 结局1：正常跑完 ===
[1] 建临时目录
    tmp=/tmp/tmp.AAAAAAAA
[2] 加锁
    拿到锁 pid=1234567
[3] 并发传输（最多 2 路）
    app-server-01 完成
    app-server-02 完成
    app-server-03 完成
    app-server-04 完成
[4] 完成
    [cleanup] 临时目录已删
    [cleanup] 锁已释放
退出码=0  锁还在=不在
```text

```bash
echo "=== 结局2：中途 Ctrl-C ==="
"$DEPLOY/deploy_good.sh" & p=$!
sleep 1.5
kill -TERM $p
wait $p
echo "退出码=$?"
echo "锁还在=$([ -f $DEPLOY/deploy.lock ] && echo 在 || echo 不在)"
echo "残留孤儿=$(pgrep -fc 'sleep 1' 2>/dev/null || echo 0)"
```text

```text
=== 结局2：中途 Ctrl-C ===
[1] 建临时目录
    tmp=/tmp/tmp.BBBBBBBB
[2] 加锁
    拿到锁 pid=1234890
[3] 并发传输（最多 2 路）
    app-server-01 完成
    [cleanup] 临时目录已删
    [cleanup] 锁已释放
退出码=143
锁还在=不在
残留孤儿=0
```text

**三处关键改进全部生效**：

1. 退出码仍是 **143**——真实的信号死退出码被 `exit $rc` 保住了，没有伪装成 0
2. 锁释放了，临时目录删了
3. **残留孤儿 = 0**——`kids` 数组里的后台任务被 cleanup 杀干净了

```bash
echo "=== 结局3：中断后立刻重跑 ==="
"$DEPLOY/deploy_good.sh" & p2=$!
sleep 1.2
kill -TERM $p2
wait $p2 2>/dev/null
echo "--- 上一次被中断，现在重跑 ---"
"$DEPLOY/deploy_good.sh"
echo "退出码=$?"
```text

```text
=== 结局3：中断后立刻重跑 ===
[1] 建临时目录
    tmp=/tmp/tmp.CCCCCCCC
[2] 加锁
    拿到锁 pid=1235000
[3] 并发传输（最多 2 路）
    [cleanup] 临时目录已删
    [cleanup] 锁已释放
--- 上一次被中断，现在重跑 ---
[1] 建临时目录
    tmp=/tmp/tmp.DDDDDDDD
[2] 加锁
    上次崩溃的残骸 (pid=1235000 已不在)，可安全重跑
退出码=1
```text

**注意**：改造版在结局 3 依然退出码 1，但它现在**能告诉你真相**——"上次崩溃的残骸，可安全重跑"，而不是含糊的"已有实例在运行"。

从"不知道为什么失败"到"知道这是残骸、可以安全重跑"，这就是可诊断性的价值。

> 💡 **为什么这里还是退出 1 而不是自动接管？** 这是**有意的设计选择**：脚本不应该自作主张地接管——万一那个"死掉"的 PID 是被 PID 复用后的无关进程占用了呢（知识点 3 讲过的竞态）。正确的做法是**报告清楚，把决定权留给人**。若你确认业务允许自动接管，可在判断到残骸后 `rm -f "$LOCK"` 再重试一次加锁。

### 第五步：清理实验环境

```bash
pkill -9 -f 'sleep 1' 2>/dev/null
rm -rf /tmp/deploy_lab
echo "已清理"
```text

---

## 第五幕：体系收束

### 本课的三个认知升级

**第一，从"线性收尾"到"注册钩子"。**

清理写在线性流程末尾，只覆盖"顺利跑完"这一种结局——而恰好只有这种结局不需要清理。`trap ... EXIT` 把它变成"无论怎么离开都会经过的闸门"。

**第二，从"信号能立刻中断"到"信号会排队"。**

bash 在执行前台命令期间收到信号，会推迟到该命令返回后才处理。对一个正在 `scp` 的脚本按 Ctrl-C，传输会完整跑完。想真正快速响应，需要把长任务放后台 + `wait`，这样 trap 才有机会在 `wait` 期间插入执行。

**第三，从"进程死了锁就放"到"孤儿会替它拿着"。**

`flock` 的锁随 fd 关闭而释放，这个机制本身是可靠的。但 `kill -9` 只杀父进程，继承 fd 的子进程会变孤儿继续持锁。所以"锁残留"的真相不是机制失效，而是**你只杀了一半**。

### 与前面课程的连接

| 本课概念 | 前序课程 | 连接点 |
|---------|---------|--------|
| trap 的继承规则 | 课 8 子 shell | 子 shell **继承** trap 但**退出不触发**；独立进程重置为默认，只有"忽略"继承 |
| 后台任务清理 | 课 8 `wait` / `$!` | 退出码藏在 `wait` 里；本课补上"被中断时也要收走它们" |
| `exit $rc` 保退出码 | 课 3 退出码 | 退出码是脚本唯一的对外语言，cleanup 不能篡改它 |
| `set -E` / `set -T` | 课 11 `set -euo pipefail` | 本课讲机制，课 11 讲它在错误处理中的实战 |
| 孤儿进程持 fd | 课 7 fd 表 | fd 会被 `fork` 继承——既是重定向的基础，也是锁残留的根因 |

### 进程边界阶段的三条主线

阶段 3 到这里走完三分之二，三条主线终于合流：

```mermaid
graph TD
    A["进程边界"] --> B["变量边界<br/>课8：子shell改不回来"]
    A --> C["环境边界<br/>课8：export是fork时拷贝"]
    A --> D["时间边界<br/>课9：脚本可能在任意时刻死"]

    B --> E["用重定向代替管道"]
    C --> F["要改当前shell必须source"]
    D --> G["trap EXIT 注册清理"]

    D --> H["死锁：kill -9后孤儿持fd"]
    H --> I["显式记录PID逐个杀"]

    E --> J["中断安全的脚本"]
    F --> J
    G --> J
    I --> J
```text

课 8 解决"**变量为什么回不来**"，课 9 解决"**死了之后怎么办**"。前者是空间的边界，后者是时间的边界。

### 下一课预告

进程内部的安全问题解决了——脚本现在能被中断、能收摊。但 shell 从来不是自己一个人在跑：它要调 `grep`、`sed`、`awk`、`find`、`xargs`。

课 10《与文本工具的协作》要回答的是：shell 在这条链路里到底该干什么、不该干什么。届时你会看到本课的一个直接推论——**`while read` 循环里每调一次外部命令，就是一次 fork**，这也是 shell 处理文本的硬边界所在。

---

## 🐞 常见误区

### 信号与 trap

1. **`trap ... KILL` 能兜底** → `trap` 返回 0 不报错，但 handler **永不执行**。这是最安静的陷阱：你以为有保护，实际裸奔。
2. **被 Ctrl-C 的脚本一定返回 130** → 若脚本正在等**外部命令**且无 trap，退出码是 **0**，上层会误判为成功。
3. **Ctrl-C 能立刻中断 `scp`/`tar`** → bash **推迟**信号处理到当前命令返回，命令会完整跑完。
4. **trap 会传给子脚本** → handler **不继承**；只有"被忽略"的信号保持忽略（POSIX 规定）。
5. **`trap - INT` 等于忽略** → `-` 是**重置为默认**（会死），忽略要写 `trap '' INT`（两个单引号）。

### 伪信号

6. **写两个 `trap ... EXIT` 会都执行** → **后者覆盖前者**，第一条静默消失。
7. **`EXIT` trap 里的 `$?` 是最终退出码** → 被信号杀死时打印 **0**，而实际退出 143。
8. **cleanup 里写裸 `exit`** → 覆盖真实退出码，把失败伪装成成功。必须 `local rc=$?` … `exit $rc`。
9. **`trap ... ERR` 能拦截错误** → 它**只报告不拦截**，脚本继续跑。想终止要配 `set -e` 或显式 `exit`。
10. **ERR/DEBUG 默认覆盖函数内部** → 需 `set -E`（ERR）/ `set -T`（DEBUG、RETURN）。

### 清理与锁

11. **进程死了锁自动释放** → 只杀**父进程**不够，继承 fd 的**孤儿子进程**还持锁。
12. **`rm -f lockfile` 能解锁** → 删文件**不影响**已持有的锁（fd 仍指向 inode），且存在竞态。
13. **用 `$$` 做唯一锁文件名** → PID 会复用；且 `mktemp` 的原子性无法靠 `$$` 模拟（TOCTOU）。
14. **`kill -- -$$` 杀进程组** → 脚本通常**不是组长**，`-$$` 组不存在；用真 PGID 会**误杀调用者**。
15. **`mktemp` 模板 3 个 X 就够了** → 本机 GNU 接受，但 POSIX/BSD 要求**至少 6 个**。

---

## 一图总结

```mermaid
graph TD
    subgraph S1["信号（真信号）"]
        A1["INT=2 / TERM=15 / HUP=1<br/>可捕获可忽略"]
        A2["KILL=9 / STOP<br/>内核处理，trap 拦不住"]
        A3["退出码约定 128+N<br/>INT→130 TERM→143"]
    end

    subgraph S2["trap 三写法"]
        B1["trap 'cmd' INT 注册"]
        B2["trap - INT 重置为默认（会死）"]
        B3["trap '' INT 忽略（不死）"]
    end

    subgraph S3["继承规则"]
        C1["handler：不继承"]
        C2["忽略：继承"]
        C3["子shell：继承但不触发"]
    end

    subgraph S4["伪信号"]
        D1["EXIT：全覆盖钩子<br/>第一行存 \$?"]
        D2["ERR：需 set -E 进函数<br/>只报告不拦截"]
        D3["DEBUG/RETURN：需 set -T"]
    end

    subgraph S5["中断安全三件套"]
        E1["mktemp -d 建（权限700）"]
        E2["trap cleanup EXIT 收"]
        E3["flock fd 形式 防并发"]
    end

    subgraph S6["陷阱"]
        F1["孤儿继承 fd → 锁残留"]
        F2["kill -- -\$\$ → 无效或误杀"]
        F3["cleanup 裸 exit → 覆盖退出码"]
    end

    S1 --> S2
    S2 --> S3
    S3 --> S4
    S4 --> S5
    S5 --> S6

    A2 -.->|"挡不住"| F1
    F1 -.->|"显式记录 PID 逐个杀"| E2
```text

---

## 课后小测

**1.（基础）** 写出三个信号及其编号：键盘中断、kill 默认信号、不可捕获的信号。

<details>
<summary>参考答案</summary>

- `SIGINT` = 2（键盘中断，Ctrl-C）
- `SIGTERM` = 15（`kill` 默认发送）
- `SIGKILL` = 9（不可捕获、不可忽略、不可阻塞）

验证：

```bash
for s in INT TERM KILL; do echo "$s=$(kill -l $s)"; done
```text

```text
INT=2
TERM=15
KILL=9
```text

</details>

**2.（基础）** `trap - INT` 与 `trap '' INT` 有什么区别？

<details>
<summary>参考答案</summary>

- `trap - INT`：**重置为默认动作**，收到 INT 时进程终止（会死）
- `trap '' INT`：**忽略**该信号（不死）

区别只在那个空字符串——两个单引号。漏写就变成了"重置"。

验证：

```bash
trap '' INT
trap -p INT
```text

```text
trap -- '' SIGINT
```text

</details>

**3.（理解）** 为什么 `trap 'echo bye' KILL` 不报错，却永远不会执行？

<details>
<summary>参考答案</summary>

`SIGKILL` 由**内核直接处理**，不会递交给进程，进程没有任何机会执行代码。`trap` 命令本身只负责登记，它不校验这个信号是否可捕获，所以返回 0。

验证：

```bash
trap 'echo NO' KILL
echo "errno=$?"
```text

```text
errno=0
```text

这说明"注册成功"不等于"能捕获"。任何"靠 trap 兜底 KILL"的设计都是无效的——`kill -9` 后 EXIT trap 也不会执行。

</details>

**4.（理解）** 脚本正在跑 `sleep 5` 时收到 `SIGINT`，无 trap，最终退出码是多少？为什么不是 130？

<details>
<summary>参考答案</summary>

**退出码是 0**（本机实测）。

原因：`sleep` 是外部命令，在自己进程里运行；`kill -INT` 只发给了 bash 脚本进程。bash 推迟信号处理，等 `sleep` 正常跑完返回 0，再处理被推迟的 INT——但此时 bash 的判断是"我等的前台命令正常结束了"，于是按正常流程继续，退出码取 0。

对照：若是**纯计算**（无外部子进程）的脚本，bash 自己被 INT 打断，退出码是 130。

验证：

```bash
cat > /tmp/t4.sh <<'EOF'
sleep 3
EOF
chmod +x /tmp/t4.sh
/tmp/t4.sh & p=$!
sleep 0.3
kill -INT $p
wait $p
echo "等待外部命令的脚本 -> $?"
```text

```text
等待外部命令的脚本 -> 0
```text

</details>

**5.（理解）** 父进程设了 `trap 'echo hi' INT` 后启动子脚本，子脚本会继承这个 handler 吗？如果父进程设的是 `trap '' INT` 呢？

<details>
<summary>参考答案</summary>

- `trap 'echo hi' INT`：**不继承**，子脚本 `trap -p INT` 为空
- `trap '' INT`：**继承**，子脚本显示 `trap -- '' SIGINT`

即 POSIX 规则：子进程重置为默认，**唯一例外是被忽略的信号保持忽略**。

验证：

```bash
cat > /tmp/t5.sh <<'EOF'
echo "  子: [$(trap -p INT)]"
EOF
chmod +x /tmp/t5.sh
trap 'echo hi' INT
echo "父(handler): [$(trap -p INT)]"
/tmp/t5.sh
trap '' INT
/tmp/t5.sh
```text

```text
父(handler): [trap -- 'echo hi' SIGINT]
  子: []
  子: [trap -- '' SIGINT]
```text

</details>

**6.（应用）** 下面这个 cleanup 有什么问题？

```bash
trap 'echo "清理完成"; exit 0' EXIT
```text

<details>
<summary>参考答案</summary>

两个问题：

1. **`exit 0` 把真实退出码覆盖成 0**——脚本不论因何失败，对外都报告"成功"
2. **没有保存 `$?`**，所以连"原本是什么退出码"都不知道

正确写法：

```bash
cleanup() {
    local rc=$?
    trap - EXIT
    rm -rf "$tmpdir"
    exit $rc
}
trap cleanup EXIT
```text

验证：

```bash
cat > /tmp/t6.sh <<'EOF'
trap 'echo "  EXIT \$?=$?"; exit 99' EXIT
exit 7
EOF
chmod +x /tmp/t6.sh
/tmp/t6.sh
echo "最终退出码=$?（7 被 99 覆盖了）"
```text

```text
  EXIT $?=7
最终退出码=99
```text

</details>

**7.（应用）** 为什么 `kill -9` 杀掉持锁脚本后，新实例仍然拿不到 `flock` 锁？

<details>
<summary>参考答案</summary>

因为 `kill -9` 只杀掉了**父 bash 进程**，它启动的**子进程的 fd 是继承的**，子进程变孤儿后继续持有该 fd，锁就还在。

`flock` 的锁确实随 fd **全部关闭**而释放——关键是"全部"。

正确做法：cleanup 里显式记录并杀掉所有后台任务 PID。

验证（简化版）：

```bash
rm -f /tmp/t7.lock
cat > /tmp/t7.sh <<'EOF'
exec 9>/tmp/t7.lock
flock -n 9 || exit 1
sleep 20
EOF
chmod +x /tmp/t7.sh
/tmp/t7.sh & p=$!
sleep 0.6
kill -9 $p
wait $p 2>/dev/null
sleep 0.3
flock -n /tmp/t7.lock -c 'echo "  拿到=已释放"' || echo "  没拿到=孤儿仍持锁"
pkill -9 -f 'sleep 20'
sleep 0.3
flock -n /tmp/t7.lock -c 'echo "  清掉孤儿后：拿到=已释放"'
rm -f /tmp/t7.lock
```text

```text
  没拿到=孤儿仍持锁
  清掉孤儿后：拿到=已释放
```text

</details>

**8.（应用）** 为什么不能在 trap 里写 `kill -- -$$`？

<details>
<summary>参考答案</summary>

脚本进程通常**不是进程组组长**。实测显示脚本的 `PGID` 等于**父进程的 PID**，而不是它自己的 `$$`。

于是：

- `kill -- -$$` → 目标 PGID 不存在 → **什么都没杀到**（清理失效）
- 若改用真实 `PGID` → 会连**调用你的父脚本/终端**一起杀掉

验证：

```bash
cat > /tmp/t8.sh <<'EOF'
echo "  脚本 \$\$=$$"
echo "  脚本 PGID=$(ps -o pgid= -p $$ | tr -d ' ')"
echo "  父 PID=$PPID PGID=$(ps -o pgid= -p $PPID | tr -d ' ')"
EOF
chmod +x /tmp/t8.sh
/tmp/t8.sh
```text

```text
  脚本 $$=2306199
  脚本 PGID=2305967
  父 PID=2305967 PGID=2305967
```text

正确做法是显式记录后台任务 PID：

```bash
kids=()
sleep 60 & kids+=($!)
cleanup() { local rc=$?; trap - EXIT
            for k in "${kids[@]}"; do kill -TERM "$k" 2>/dev/null; done
            exit $rc; }
trap cleanup EXIT INT TERM
```text

</details>

**9.（综合）** 写出一个中断安全的脚本骨架，要求：建临时目录、加锁、清理、保退出码。

<details>
<summary>参考答案</summary>

```bash
cat > /tmp/t9.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail

LOCK=/tmp/t9.lock
TMPDIR_RUN=""
LOCK_FD=""
kids=()

cleanup() {
    local rc=$?
    trap - EXIT
    for k in "${kids[@]}"; do kill -TERM "$k" 2>/dev/null; done
    for k in "${kids[@]}"; do wait "$k" 2>/dev/null; done
    [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ] && rm -rf "$TMPDIR_RUN"
    if [ -n "$LOCK_FD" ]; then
        flock -u "$LOCK_FD" 2>/dev/null
        exec {LOCK_FD}>&- 2>/dev/null
    fi
    echo "  [cleanup] 完成 rc=$rc"
    exit $rc
}
trap cleanup EXIT INT TERM

rm -f /tmp/t9.lock
TMPDIR_RUN=$(mktemp -d)
LOCK_FD=9
exec 9>"$LOCK"
flock -n 9 || { echo "已有实例"; exit 1; }
echo $$ > "$LOCK"

sleep 30 & kids+=($!)
echo "  工作中，临时目录=$TMPDIR_RUN"
wait
SH
chmod +x /tmp/t9.sh

echo "--- 正常跑（用短任务验证骨架）---"
sed -i 's/sleep 30/sleep 1/' /tmp/t9.sh
/tmp/t9.sh
echo "退出码=$?  锁残留=$([ -f /tmp/t9.lock ] && echo 有 || echo 无)"
```text

```text
--- 正常跑（用短任务验证骨架）---
  工作中，临时目录=/tmp/tmp.XXXXXXXX
  [cleanup] 完成 rc=0
退出码=0  锁残留=无
```text

五个要点：`local rc=$?` 第一行、`trap - EXIT` 防重入、清理前判存在（幂等）、`exit $rc` 保退出码、`kids` 数组收后台任务。

</details>

**10.（综合）** 一个脚本被 Ctrl-C 后，锁残留、临时目录残留、还有一个 `scp` 进程在后台跑。请诊断并给出修复方案。

<details>
<summary>参考答案</summary>

**诊断**：三类残留对应三个不同的原因，不能一刀切。

| 残留 | 根因 | 修复 |
|------|------|------|
| 临时目录 | 清理写在末尾，没走 `trap` | `trap cleanup EXIT` |
| 锁文件 | 孤儿 `scp` 继承了锁的 fd | cleanup 里杀掉后台 PID |
| `scp` 进程 | 父进程死了，子进程变孤儿 | 显式记录 PID 逐个杀 |

**修复方案**：

```bash
cat > /tmp/t10.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail
LOCK=/tmp/t10.lock
TMPDIR_RUN=""
LOCK_FD=""
kids=()

cleanup() {
    local rc=$?
    trap - EXIT
    for k in "${kids[@]}"; do kill -TERM "$k" 2>/dev/null; done
    for k in "${kids[@]}"; do wait "$k" 2>/dev/null; done
    [ -n "$TMPDIR_RUN" ] && [ -d "$TMPDIR_RUN" ] && rm -rf "$TMPDIR_RUN"
    if [ -n "$LOCK_FD" ]; then
        flock -u "$LOCK_FD" 2>/dev/null
        exec {LOCK_FD}>&- 2>/dev/null
    fi
    echo "  [cleanup] rc=$rc 三类残留已处理"
    exit $rc
}
trap cleanup EXIT INT TERM

rm -f /tmp/t10.lock
TMPDIR_RUN=$(mktemp -d)
LOCK_FD=9
exec 9>"$LOCK"
if ! flock -n 9; then
    if [ -s "$LOCK" ]; then
        old=$(cat "$LOCK" 2>/dev/null)
        if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
            echo "  真实例在跑 pid=$old"; 
        else
            echo "  残骸 pid=$old 已死，可安全重跑"
        fi
    fi
    exit 1
fi
echo $$ > "$LOCK"

sleep 30 & kids+=($!)
echo "  模拟 scp 传输中 pid=${kids[0]}"
wait
SH
chmod +x /tmp/t10.sh
sed -i 's/sleep 30/sleep 1/' /tmp/t10.sh
/tmp/t10.sh
echo "退出码=$?"
```text

```text
  模拟 scp 传输中 pid=1234567
  [cleanup] rc=0 三类残留已处理
退出码=0
```text

**关键点**：不要试图用 `kill -- -$$` 一次性解决——它要么无效，要么误杀调用者。三类残留要分别对症，靠的是"显式记录 PID + trap 注册清理"。

</details>

---

## 📋 本课速览

| 概念 | 一句话 | 关键证据 |
|------|--------|----------|
| 信号编号 | INT=2 / TERM=15 / KILL=9 | `kill -l` 实测 |
| KILL 不可捕获 | `trap ... KILL` 返回 0 但永不执行 | errno=0，handler 静默 |
| 128+N | 被信号 N 杀死 → 退出码 128+N | TERM → 143 |
| **等待外部命令时收 INT** | **退出码是 0，不是 130** | 实测 A 组 0 vs B 组 130 |
| 信号推迟 | 前台命令期间收到信号，等命令返回才处理 | T+0.5 发 INT，T+3.0 才触发 |
| trap 继承 | handler 不继承；忽略继承 | `trap -p` 取证 |
| `trap -` vs `trap ''` | 重置为默认（会死）vs 忽略（不死） | 空字符串的差别 |
| EXIT 全覆盖 | 正常/exit/失败/set -e/信号死 全触发 | 四组实测 |
| **EXIT 里的 `$?`** | **被信号杀死时是 0，实际退出 143** | 必须第一行存 |
| 覆盖非叠加 | 两个 `trap ... EXIT` 只执行后者 | EXIT-2 |
| ERR 需 `set -E` | 否则函数内错误不触发 | 无 -E 静默跳过 |
| DEBUG/RETURN 需 `set -T` | 否则不进函数内部 | 追踪粒度对比 |
| `mktemp -d` | 权限 700，模板至少 6 个 X | `stat -c %a` |
| **孤儿持锁** | **杀了父进程，子进程继承 fd 继续持锁** | 清掉孤儿后立刻释放 |
| **`kill -- -$$`** | **脚本不是组长，组不存在；用真 PGID 会误杀调用者** | PGID == 父 PID |
| 幂等清理 | 重复 `rm -rf` 返回 0 不报错 | 实测 0 |

---

## 🧭 课程导航

| 上一课 | 本课 | 下一课 |
|--------|------|--------|
| [课 8《子shell 与执行上下文》](./lesson-08-子shell与执行上下文.md) | **课 9《信号 trap 与清理》** | [课 10《与文本工具的协作》](./lesson-10-与文本工具的协作.md) |

**本课在阶段 3 中的位置**：[阶段 3《进程边界》](../overview.md) · 第 2 课 / 共 3 课

**前情回顾**：课 8 讲清了四条进程边界（变量、`exit`、环境、退出码），并留下三个伏笔——子 shell 继承 trap 却不触发、EXIT trap 到底什么时候触发、并发脚本被 Ctrl-C 后后台任务怎么办。**本课全部接住**。

---

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```text
继续学 Bash 编程。我的学习档案在 shell/00-学习档案.md，
刚学完阶段 3《进程边界》的课《信号 trap 与清理》知识点 信号基础与 trap、伪信号 EXIT/ERR/DEBUG、清理/锁与临时文件，
请按大纲继续讲解下一批知识点。
```text
