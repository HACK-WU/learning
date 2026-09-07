# 第 7 课：重定向与文件描述符

> 所属阶段：阶段 2《语言内核》｜ 水平：进阶 ｜ 本课知识点：fd 表与重定向、here-doc 与 here-string、管道缓冲与协进程（选读）
> 故事情节：`2>&1 >log` 和 `>log 2>&1` 只差一个顺序，一个把错误打进日志，一个把错误打上屏幕

## 🎯 本课目标

- 解释重定向的**顺序敏感性**，用 `exec` 做脚本级持久重定向
- 控制 here-doc 内是否展开，用它生成配置文件
- 解释并规避块缓冲导致的"输出卡住"

---

## 第一幕：起源与场景引入

> 🎬 **场景**：`deploy.sh` 想把标准输出和错误都记进日志，于是写了：

先准备这个演示脚本（后续多处会用到它）：

```bash
cat > deploy.sh <<'OUTER'
echo "[INFO] 开始部署"
echo "[INFO] 拉取代码"
echo "[ERROR] 依赖缺失：libfoo" >&2
echo "[INFO] 部署完成"
OUTER
chmod +x deploy.sh
```

然后执行：

```bash
./deploy.sh 2>&1 > deploy.log
```

结果：日志里只有正常输出，`tail -f deploy.log` 看不到任何报错——所有错误信息依旧打在终端上，而脚本的错误处理逻辑却在读一个"干净"的日志文件，于是判定"无错误"。

实测复现（`/tmp/c7act4/deploy.sh` 输出 3 条 INFO + 1 条 ERROR）：

```
--- 事故写法：./deploy.sh 2>&1 > deploy.log ---
[ERROR] 依赖缺失：libfoo          ← 错误跑到了屏幕上
[上面是屏幕输出]
deploy.log 内容（日志里看不到 ERROR）：
[INFO] 开始部署
[INFO] 拉取代码
[INFO] 部署完成                    ← 日志里只有正常输出
```

一个字符的位置差异，让"错误监控"变成了自我安慰。这一课要把它连根拔起。

---

## 第二幕：认知冲突

> ❓ **问题**：`2>&1` 不是"把 stderr 合并到 stdout"吗？为什么没进日志？

`2>&1` 的真实含义是：**让 fd 2 指向 fd 1 当前指向的地方**。它是一个"复制指针"的动作，不是"建立永久关联"。

- `2>&1 >log`：fd2 复制了 fd1（此时是终端）→ 然后 fd1 才改指向 log。结果：错误去终端，正常输出去日志。
- `>log 2>&1`：fd1 先指向 log → fd2 复制 fd1（此时已是 log）。结果：两者都去日志。

一个是"先抄地址再搬家"，一个是"先搬家再抄地址"。

关键佐证——`n>&m` 是**复制指针（dup2）**，复制完之后两个 fd 就各走各路了，后续再改其中一个不影响另一个：

```bash
exec 2>&1        # fd2 复制 fd1（此时都指向调用者的 stdout）
echo "A-这行走 fd1"
echo "B-这行走 fd2" >&2
exec 1>/dev/null # 之后才改 fd1
echo "C-改 fd1 后走 fd1（应消失）"
echo "D-改 fd1 后走 fd2（应仍在）" >&2
```

输出：

```
A-这行走 fd1
B-这行走 fd2
D-改 fd1 后走 fd2（应仍在）
```

`C` 消失了（fd1 去了 `/dev/null`），`D` 还在（fd2 早在改 fd1 之前就复制走了终端）。**如果 `2>&1` 是"建立永久关联"，`D` 应该跟着消失**。

---

## 第三幕：层层揭示

### 知识点 1：fd 表与重定向

> 本知识点关键点：每个进程一张 fd 表（0/1/2 是约定而非本质）、`>` `>>` `<` `<<` `&>` `>&` `<>`、`n>&m` 是复制 fd 而非重命名、重定向**从左到右**执行、`exec 3>file` 打开自定义 fd、`exec 1>&3` 持久重定向、`{var}>file` 自动分配 fd（bash 4.1+）、关闭 fd `exec 3>&-`

#### 一句话定义

每个进程都有一张**文件描述符表**（fd 表），fd 是表里的"插槽编号"，重定向就是把某个插槽的线改插到别处；`n>&m` 是**复制**指针（dup2），不是重命名。

#### 直觉建立（类比）

把 fd 表想象成机房里的**配线架**：

- fd 0/1/2 是三个出厂就贴好标签的端口（stdin/stdout/stderr），但标签只是**约定**——你完全可以把 1 号线拔下来插到别的地方。
- `>log` 是把 1 号线从"显示器"拔下来，插到 `log` 文件上。
- `2>&1` 是**拿 2 号线去复制 1 号线此刻插着的那个孔**——复制完，两根线各自独立。
- 所以"先复制再搬家"和"先搬家再复制"，结果天差地别。

用 `ls -l /proc/$$/fd` 可以亲眼看到这张配线架：

```
l-wx------ 1 root root 64 Sep  4 11:57 1 -> pipe:[226635665]
l-wx------ 1 root root 64 Sep  4 11:57 2 -> pipe:[226635666]
lr-x------ 1 root root 64 Sep  4 11:57 255 -> /path/to/script.sh
```

#### 核心原理

**1. 重定向从左到右依次执行**

这是理解一切顺序陷阱的钥匙。每个重定向都在**当时**的 fd 表上操作：

| 写法 | 第 1 步 | 第 2 步 | 结果 |
|------|---------|---------|------|
| `2>&1 >log` | fd2 复制 fd1（终端） | fd1 改指向 log | 错误→终端，正常→日志 |
| `>log 2>&1` | fd1 改指向 log | fd2 复制 fd1（已是 log） | 两者都→日志 |
| `>log 2>&1 1>&2` | fd1→log | fd2 复制 fd1 | fd1 再复制 fd2 | 两者都→log |

实测第三种（三个重定向连用）：

```
--- 验证：>f.log 2>&1 1>&2 的结果 ---
[终端输出结束]          ← 屏幕上什么都没有
f.log 内容：
OUT-正常输出
ERR-报错信息             ← 两条都进了 log
```

因为第三步 `1>&2` 时，fd2 已经指向 log 了，fd1 复制 fd2 还是指向 log。

**2. `n>&m` 是 dup2，不是别名**

`exec 1>&3` 的意思是"让 fd1 变成 fd3 的副本"，而不是"给 fd3 起个新名字叫 fd1"。副本一旦生成就独立：

```bash
exec 3>&1                  # fd3 复制当前 stdout（终端）
exec 1>out.log 2>&1        # fd1/fd2 都改指向 log
echo "这行进 log"
exec 1>&3                  # fd1 恢复成 fd3（终端）
echo "恢复后这行回终端"     # 这行出现在屏幕上
exec 3>&-
```

这正是**双写**（日志 + 终端）的标准手法：先把原 stdout 存进 fd3，改完 fd1 后还能随时切回来。

**3. `&>` 是 bash 扩展，不可移植**

`&>file` 等价于 `>file 2>&1`，但**只在 bash / zsh 里成立**。本机 `/bin/sh` 指向 dash：

```
--- 用 sh 跑 &>e.log ---
sh 退出码=0
OUT-正常输出              ← 内容全跑到屏幕上
ERR-报错信息
[结束]
e.log 存在吗：
-rw-r--r-- 1 root root 0 Sep  4 11:58 e.log   ← 0 字节！
```

dash 把 `&` 解析成**后台运行符**，`>e.log` 单独成立创建了一个空文件，而真正的命令在后台跑，输出去了终端。**退出码还是 0，没有任何报错**。

> ⚠️ 这是最危险的一类失败：脚本加了 `#!/bin/sh`，或者被 `sh script.sh` 调用，`&>` 会静默失效，日志文件空空如也却显示成功。

#### 示例演示

**例 1：自定义 fd（3-9 随便用）**

```bash
exec 3>custom.txt
echo "写进 fd3 的内容" >&3
exec 3>&-
echo "custom.txt 内容："
cat custom.txt
```

输出：

```
custom.txt 内容：
写进 fd3 的内容
```

读方向同理：

```bash
printf '第一行\n第二行\n第三行\n' > src.txt
exec 4<src.txt
read -r -u 4 line1
read -r -u 4 line2
echo "读到 line1=$line1"
echo "读到 line2=$line2"
exec 4<&-
```

输出：

```
读到 line1=第一行
读到 line2=第二行
```

**例 2：脚本级持久重定向**

`exec` 不带命令时，重定向对**当前 shell 及其后续所有命令**永久生效：

```bash
exec >p.log 2>&1
echo "持久-正常"
echo "持久-错误" >&2
echo "持久-结束"
```

运行后终端**一行都不显示**，全部落进 `p.log`：

```
[脚本结束，终端不应有任何输出]
p.log 内容：
持久-正常
持久-错误
持久-结束
```

这适合"整个脚本的输出都归日志"的场景，比每行末尾加 `>>log` 干净得多。

**例 3：自动分配 fd（bash 4.1+）**

手写 fd 号容易撞车（比如调别人的函数也用了 fd3）。`{var}>file` 让 bash 自己挑一个空闲号：

```bash
exec {myfd}>auto.txt
echo "自动 fd 号 = $myfd"
echo "写入自动 fd 的内容" >&"${myfd}"
exec {myfd}>&-
```

输出：

```
自动 fd 号 = 10
```

多个自动分配互不冲突：

```bash
exec {fa}>fa.txt
exec {fb}>fb.txt
echo "fa=$fa fb=$fb"
```

输出 `fa=10 fb=11`。bash 从 10 开始往上找空闲号，完美避开手工占用的 3-9。

**例 4：`<>` 读写同一个 fd**

```bash
printf '原始数据\n' > rw.txt
exec 6<>rw.txt
read -r -u 6 content
echo "读到：$content"
echo "新内容" >&6
exec 6>&-
echo "rw.txt 最终内容："
cat rw.txt
```

输出：

```
读到：原始数据
rw.txt 最终内容：
原始数据
新内容
```

⚠️ 注意：读完一行后**文件偏移停在第一行末尾**，此时写入不会从头覆盖，而是接在后面变成追加。想覆盖得先 `exec 6>rw.txt` 或用 `seek`。

#### 常见误区

| 误区 | 真相 | 实测证据 |
|------|------|----------|
| `2>&1` 建立了永久关联 | 只是**当时**复制一次，之后各走各路 | 上例 `D-改 fd1 后走 fd2` 仍在屏幕 |
| `&>` 和 `>file 2>&1` 可互换 | `&>` 是 bash 扩展，dash 下静默失效 | dash 下 e.log **0 字节**，退出码仍 0 |
| 关闭 fd 无害 | 关了 fd1 后 `echo` 直接报错 | `write error: Bad file descriptor`，退出码 1 |
| `<>` 打开后写入会覆盖 | 读会移动偏移，写入变成追加 | rw.txt 变成"原始数据\n新内容" |
| `>file` 失败时原文件还在 | `>` 会**立刻截断**原文件 | 实验 7：半截文件，原内容已丢失 |

关闭 fd1 的实测：

```bash
exec 1>&-
echo "这行会去哪"
echo "退出码=$?" >&2
```

输出（stderr）：

```
./closeme.sh: line 2: echo: write error: Bad file descriptor
退出码=1
```

#### 一句话记住

**重定向是从左到右复制指针，`2>&1` 复制的是"此刻"的 fd1——想让错误进日志，就先把 fd1 搬家（`>log 2>&1`），再让 fd2 抄地址。**

---

### 知识点 2：here-doc 与 here-string

> 本知识点关键点：`<<EOF` 与 `<<'EOF'` 决定是否展开、`<<-EOF` 去前导 Tab（只吃 Tab 不吃空格）、`<<<"str"` here-string 自带尾换行、here-doc 作为 stdin 传给命令、用 here-doc 生成配置文件（配合引号控制变量替换时机）

#### 一句话定义

here-doc 是"就地写一段多行文本塞给命令当 stdin"，here-string 是它的单行简写版；**定界符加引号 = 关闭全部展开**。

#### 直觉建立（类比）

here-doc 就像写便签：

- `<<EOF` = 便签内容先交给"秘书"（shell）检查一遍，把 `$变量`、`$(命令)` 都替换成实际值再抄上去。
- `<<'EOF'` = 便签**封在信封里**交给命令，秘书不许拆，原样送达。
- `<<-EOF` = 允许便签内容带缩进（Tab），撕掉缩进再送——但**只认 Tab，不认空格**。

#### 核心原理

**定界符的四种写法，只有一种会展开：**

| 写法 | 是否展开 | 说明 |
|------|----------|------|
| `<<EOF` | ✅ 展开 | 变量、命令替换、算术全展开 |
| `<<'EOF'` | ❌ 不展开 | 单引号 |
| `<<"EOF"` | ❌ 不展开 | **双引号也不展开**，与直觉相反 |
| `<<\EOF` | ❌ 不展开 | 反斜杠转义定界符 |

实测：

```
--- 无引号定界符（展开） ---
hello world
当前目录 /tmp/c7kp2
命令替换 我是命令替换
算术 3
--- 单引号定界符（不展开） ---
hello $NAME
当前目录 $PWD
命令替换 $(echo 我是命令替换)
算术 $((1+2))
--- 双引号定界符（也不展开！） ---
hello $NAME
命令替换 $(echo 我不该执行)
--- 反斜杠转义定界符（也不展开） ---
hello $NAME
命令替换 $(echo 我也不该执行)
```

三种加引号的写法效果完全一致。这不是 bug——**只要定界符有任何形式的引号或转义，整个 here-doc 就等同于被单引号包裹**。

**结束定界符必须独占一行且在行首：**

前导空格、尾随空格都会让它失效，bash 会一直读到文件末尾才报错：

```
--- 结束定界符前有空格（会失败） ---
badterm.sh: line 4: warning: here-document at line 1 delimited by end-of-file (wanted `MARKER')
内容行
 MARKER
echo "这行本该是命令"      ← 被当成内容打印了！
```

尾随空格同样致命：

```
badterm2.sh: line 4: warning: here-document at line 1 delimited by end-of-file (wanted `MARKER2')
内容行
MARKER2 
echo "尾随空格测试"        ← 同样被吞
```

> ⚠️ 这类错误很难查：warning 只说"读到了 EOF"，不告诉你哪一行多了个空格。行尾空格是隐形杀手。

**`<<-` 只吃 Tab，不吃空格：**

```
--- Tab 缩进（应被吃掉） ---
Tab 缩进的行
Tab x2
--- 空格缩进（应被保留，且结束符失效） ---
space_only.sh: line 3: warning: here-document at line 1 delimited by end-of-file (wanted `EOF')
    空格缩进的行
    EOF                    ← 结束符没被识别，被当内容打印
```

注意第二组：**用空格缩进时，连结束定界符 `    EOF` 都失效了**，因为 `<<-` 只剥 Tab。所以用了 `<<-` 就必须用 Tab 缩进，混用空格必然翻车。

#### 示例演示

**例 1：生成 nginx 配置——部分展开，部分原样**

这是 here-doc 最典型的生产用途。需求：`server_name`、`port` 要用变量，但 `log_format` 里的 `$remote_addr` 必须原样保留（那是 nginx 自己的变量）。

解法：**拼接两个 here-doc**。

```bash
DOMAIN="example.com"
PORT=8080

cat > nginx.conf <<EOF
server {
    listen $PORT;
    server_name $DOMAIN;
    access_log /var/log/nginx/$DOMAIN.access.log;
EOF

cat >> nginx.conf <<'EOF'
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer"';
}
EOF
```

生成结果：

```
server {
    listen 8080;
    server_name example.com;
    access_log /var/log/nginx/example.com.access.log;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer"';
}
```

第一段展开（`8080`、`example.com`），第二段原样（`$remote_addr` 保留）。

**例 2：无引号定界符下的选择性转义**

如果只想转义个别 `$`，可以不加引号 + 反斜杠：

```bash
PORT=8080
cat <<EOF
port=$PORT
literal=\$PORT
backslash=\\n
EOF
```

输出：

```
port=8080
literal=$PORT
backslash=\n
```

注意 `\\n` 变成了字面的 `\n`（反斜杠本身也要转义）。**当转义字符多到影响可读性时，改用两段 here-doc 拼接**。

**例 3：here-string 与词拆分**

here-string `<<<` 是 here-doc 的单行版，**自带一个尾换行**：

```
--- printf 无换行的 od ---
0000000   a   b   c
0000003                     ← 3 字节
--- echo（自带换行）的 od ---
0000000   a   b   c  \n
0000004                     ← 4 字节
--- here-string 的 od ---
0000000   a   b   c  \n
0000004                     ← 4 字节，与 echo 一致
```

空变量也是 1 字节（只有那个尾换行）：

```
空变量字节数: 1
未定义变量(set -u 关闭时)字节数: 1
```

**here-string 不做词拆分**——这是它与普通参数扩展的关键差异：

```bash
VAR="hello world"
printf '<%s>\n' $VAR      # 词拆分，输出两行
cat <<< $VAR               # 不拆分，原样一整行
```

输出：

```
--- printf 对比：逐个参数打印 ---
<hello>
<world>                    ← 词拆分
--- here-string 不加引号 ---
hello world                ← 完整传入，未拆分
```

因为 here-string 的右侧**不做词拆分和通配符展开**（bash 明确规定的行为）。所以 `<<< $VAR` 里的引号其实是可选的，但**加上引号仍是好习惯**（可读性 + 与其他上下文一致）。

多行变量进 here-string 也能保留换行：

```
--- here-string 传多行 ---
a
b
c
--- wc -l ---
3
```

**例 4：here-doc 作为 stdin**

```bash
while read -r line; do
  echo "处理：$line"
done <<EOF
第一行
第二行
EOF
```

输出：

```
处理：第一行
处理：第二行
```

多行赋值：

```bash
multi=$(cat <<EOF
line1
line2
line3
EOF
)
echo "$multi"
echo "行数：$(echo "$multi" | wc -l)"
```

输出：

```
line1
line2
line3
行数：3
```

> 💡 注意：命令替换 `$( )` 会**剥掉尾部所有换行**，所以这里 3 行正确；但如果内容本身以空行结尾，那些空行会丢失。

#### 常见误区

| 误区 | 真相 | 实测证据 |
|------|------|----------|
| `<<"EOF"` 会展开（双引号嘛） | **不展开**，与其变量名含义相反 | 输出 `hello $NAME` |
| `<<-` 能去掉所有缩进 | 只吃 **Tab**，空格原样保留 | 空格缩进组连结束符都失效 |
| 结束定界符前有缩进无所谓 | 必须**行首**，否则读到文件末尾 | warning + 后续命令被当内容吞掉 |
| here-string 会词拆分 | **不拆分**，整串作为一个整体 | `<<< $VAR` 得到完整 "hello world" |
| here-string 不会补换行 | **总补一个尾换行** | 空变量 `wc -c` = 1 |
| here-doc 内容尾部的空行会保留 | 经 `$( )` 捕获时会被剥掉 | `multi` 行数正确但尾部空行丢失 |

#### 一句话记住

**定界符加引号 = 整段不展开；`<<-` 只吃 Tab 不吃空格；结束定界符必须在行首、前后都不能有空格；here-string 自动补尾换行且不做词拆分。**

---

### 知识点 3：管道、缓冲与协进程

> 本知识点关键点：stdlib 的三档缓冲（全缓冲/行缓冲/无缓冲）、管道连接时子进程默认**全缓冲**、这导致交互式脚本输出卡住、`stdbuf -oL` / `unbuffer` 强制行缓冲、管道两侧都在子 shell 中、`coproc` 双向通信（**选读**）

#### 一句话定义

C 标准库（stdio）为了减少系统调用，会把输出**攒起来批量写**；是否"攒"取决于输出目标——连终端就一行一写（行缓冲），连管道/文件就攒够 4KB 再写（全缓冲）。

#### 直觉建立（类比）

把输出想象成**发货**：

- **无缓冲**：来一件发一件，实时但运费（系统调用开销）高。
- **行缓冲**：攒到一行（遇到 `\n`）就发货——终端前默认这档，因为人要看实时反馈。
- **全缓冲**：攒满一卡车（4KB/8KB）才发——管道和文件前默认这档，因为下游是程序不是人，效率优先。

**同一个命令，接终端和接管道，发货节奏完全不同。**

实测确认 stdio 会自动检测：

```
--- 直连（当前是管道，非 tty）---
stdout 模式: 全缓冲(非 tty)
是否 tty: False
--- 通过管道 ---
stdout 模式: 全缓冲(非 tty)
是否 tty: False
--- 用 script 伪造 tty ---
stdout 模式: 行缓冲(检测到 tty)
是否 tty: True
```

#### 核心原理

**1. 缓冲差异的实证**

用 python 生产者（每 0.6 秒输出一行，不主动 flush），观察消费者收到的时间戳：

```
--- 通过管道（python 默认全缓冲）→ 观察时间戳是否扎堆在最后 ---
起始 12:00:34
12:00:36 | tick 0
12:00:36 | tick 1
12:00:36 | tick 2          ← 三条全扎堆在同一秒！
结束 12:00:36

--- 加 -u（无缓冲）---
起始 12:00:36
12:00:36 | tick 0
12:00:36 | tick 1
12:00:37 | tick 2          ← 逐条递增
结束 12:00:38
```

**全缓冲时消费者干等了 2 秒，然后一次性收到全部内容。** 这就是"输出卡住"的根源。

**2. 最致命的后果：进程崩溃时缓冲区内容全部丢失**

正常退出时 stdio 会 flush，但如果进程被 `SIGKILL` 强杀（没有机会执行清理）：

```
--- SIGKILL 强杀（无机会 flush）---
退出码=137（137 = 128+9 = SIGKILL）
kill.log 内容：
[文件字节数: 0]                     ← 全部丢失！

--- 同样场景但加 -u（无缓冲）---
退出码=137
kill_u.log 内容：
事件 0
事件 1
事件 2
崩溃前最后一句
[文件字节数: 49]                    ← 完整保留
```

后台任务被 `kill -9` 的实测：

```
--- 用 python 内联，验证 kill -9 丢数据 ---
退出码=137
bgpy.log 内容：
[文件字节数: 0]                     ← 0 字节，日志全丢

--- 解法：定期 flush ---
退出码=137
bgpy_fixed.log 内容：
进度 0%
进度 10%
进度 20%
[文件字节数: 32]                    ← 已写内容保住了
```

> ⚠️ **排障价值**：服务被 OOM killer 杀掉（`kill -9`）后日志里一片空白，不是没输出，是**全缓冲 + 强杀 = 数据蒸发**。

**3. bash 内建命令天然免疫**

好消息：**bash 的 `echo` 是内建命令，不走 stdio 缓冲**，每次 write 直接进内核：

```
--- bash 内建 echo 本身就是无缓冲的 ---
退出码=137
bashjob.log 内容：
进度 0%
进度 10%
进度 20%
```

所以纯 bash 脚本（只用 `echo`/`printf` 内建）被强杀时已输出的内容是安全的。真正的风险来自**管道里的外部命令**（grep/awk/sed/python 等）。

**4. `stdbuf` 的作用对象**

`stdbuf` 通过设置 `LD_PRELOAD` 环境变量改变目标进程的 stdio 行为，**只对该进程自己的缓冲生效**：

```
--- stdbuf 加在生产者身上才有用 ---
11:59:58 | tick 1
11:59:58 | tick 2
11:59:59 | tick 3
--- stdbuf 对 shell 内建 echo 无效（内建不走 stdio） ---
11:59:59 | tick 1
12:00:00 | tick 2
12:00:00 | tick 3
```

两个关键结论：

- `stdbuf` 要加在**真正做缓冲的那个进程**上。给 `cat` 加没用（cat 只是过路，不做缓冲决策）。
- `stdbuf` 对 **bash 内建命令无效**（内建不经过 stdio 层）。

**5. 管道两侧都在子 shell**

这是 bash 的经典陷阱，与缓冲无关但同样致命：

```bash
COUNT=0
printf 'a\nb\nc\n' | while read -r x; do
  COUNT=$((COUNT+1))
done
echo "管道版 COUNT=$COUNT（应为 0）"
```

输出 `管道版 COUNT=0`（1000 行数据实测同样是 0）。因为 `while` 在管道右侧的子 shell 里，`COUNT` 的修改随子 shell 退出而消失。

三种解法：

```bash
# 解法 1：here-string 避开管道
COUNT2=0
while read -r x; do COUNT2=$((COUNT2+1)); done <<< $'a\nb\nc'

# 解法 2：输入重定向
COUNT3=0
while read -r x; do COUNT3=$((COUNT3+1)); done < data.txt

# 解法 3：进程替换
COUNT4=0
while read -r x; do COUNT4=$((COUNT4+1)); done < <(cat data.txt)
```

实测（1000 行）：

```
管道版 N=0                 ← 变量丢失
重定向版 N2=1000           ← 正确
进程替换版 N3=1000         ← 正确
```

**6. `set -e` 抓不到管道左侧失败**

```
--- 默认：左边失败但整体成功 ---
false | true
退出码=0（0 说明左侧失败被吞）

--- set -e 能否抓到 ---
set -e
false | true
echo "这行不该出现"
退出码=0（0 说明 set -e 没抓到）      ← "这行不该出现"真的出现了！

--- set -e + pipefail ---
set -e
set -o pipefail
false | true
echo "这行不该出现"
退出码=1（非 0 说明抓到了）
```

**必须同时开 `set -e` 和 `set -o pipefail`**，否则管道中任意一段失败都会被静默吞掉。

**7. `PIPESTATUS` 必须立刻存**

```bash
false | true | false
echo "PIPESTATUS=${PIPESTATUS[*]}"
echo "长度=${#PIPESTATUS[@]}"     ← 1！因为上一条 echo 已经重置了它
```

正确写法——立刻存进变量：

```bash
false | true | false
st=("${PIPESTATUS[@]}")
echo "长度=${#st[@]}"              ← 3
echo "逐段：第1段=${st[0]} 第2段=${st[1]} 第3段=${st[2]}"
```

输出：

```
长度=3
内容=1 0 1
逐段：第1段=1 第2段=0 第3段=1
```

`pipefail` 只给你**一个**非 0 退出码，`PIPESTATUS` 给你**每一段**的：

```
--- pipefail 只看最后一个非 0 ---
true | false | true
pipefail 退出码=1
但 PIPESTATUS 完整保留：0 1 0
```

#### 示例演示

**例 1：`stdbuf` 修复实时日志**

问题场景：长任务输出进度，经 `grep` 过滤后想实时看到。

```
--- 问题写法：缓冲导致看不到实时进度 ---
起始 12:01:48
12:01:50 | 步骤 0 完成
12:01:50 | 步骤 1 完成
12:01:50 | 步骤 2 完成      ← 五条全扎堆在 12:01:50
12:01:50 | 步骤 3 完成
12:01:50 | 步骤 4 完成
结束 12:01:50               ← 干等 2 秒后一次到账

--- 用 stdbuf 修复 grep ---
起始 12:01:50
12:01:50 | 步骤 0 完成
12:01:51 | 步骤 1 完成      ← 逐条实时
12:01:51 | 步骤 2 完成
12:01:51 | 步骤 3 完成
12:01:52 | 步骤 4 完成
结束 12:01:52
```

修复写法：

```bash
./longrun.sh | stdbuf -oL grep "步骤" | while IFS= read -r l; do
  printf '%s | %s\n' "$(date +%H:%M:%S)" "$l"
done
```

**关键：给 `grep` 加 `stdbuf -oL`，不是给生产者加。** grep 是那个"攒着不发"的进程。

**例 2：三档缓冲对照表**

| 档位 | 触发条件 | 表现 | 设置方式 |
|------|----------|------|----------|
| 无缓冲 | stderr 默认 | 立即写 | `stdbuf -o0`、`python3 -u` |
| 行缓冲 | stdout 连 tty | 遇 `\n` 写 | `stdbuf -oL` |
| 全缓冲 | stdout 连管道/文件 | 攒满 4KB 写 | 默认 |

注意 **stderr 默认无缓冲**——这是设计上的善意：错误信息不该被缓冲耽搁。

**例 3：`tee` 双写与它的退出码陷阱**

```bash
./deploy.sh 2>&1 | tee tee.log
```

日志和屏幕都有。但配合 `pipefail` 时：

```
--- tee 的退出码陷阱：配合 pipefail 时会暴露左侧失败 ---
set -o pipefail
false | tee t2.log
退出码=1                     ← 左侧 false 被暴露
```

这是**好事**——`tee` 场景正是你希望知道左侧是否失败的地方。

#### 常见误区

| 误区 | 真相 | 实测证据 |
|------|------|----------|
| `set -e` 能抓管道失败 | 默认**不能**，需 `pipefail` | `false\|true` 退出码 0，"这行不该出现"照常打印 |
| `PIPESTATUS` 随时可读 | 任何命令都会重置它，须**立刻存** | `echo` 后就从 3 变 1 |
| `stdbuf` 加谁都行 | 只作用于**做缓冲的那个进程** | 给 `cat` 加无效，给 `grep`/`python` 加有效 |
| `stdbuf` 对 bash 脚本生效 | 对**内建命令**无效 | `stdbuf -oL bash脚本` 无变化 |
| 管道 `while` 改的变量能用 | 子 shell 里改，外面**看不到** | 1000 行数据 COUNT 仍是 0 |
| 进程被杀时已输出的内容在 | 全缓冲 + SIGKILL = **全部丢失** | 0 字节 vs 49 字节 |
| `unbuffer` 到处可用 | 本机**未安装**，属 expect 包 | 用 `stdbuf` 或 `script` 替代 |

> 📎 **本机实测补充**：`unbuffer` 在本环境（WSL Ubuntu）**不可用**（`command -v unbuffer` 返回 NO）。可用替代方案：`stdbuf`（coreutils 自带，已确认可用）、`script -qec "cmd" /dev/null`（伪造 tty）、`python3 -u`。

> 📎 **协进程 `coproc` 为拓展阅读**：它在真实脚本中使用率极低、难以调试且行为随 bash 版本变化，本课程不展开。需要双向通信时，更稳妥的做法是用临时 FIFO 或直接换 Python。

#### 一句话记住

**连终端行缓冲、连管道全缓冲；`stdbuf -oL` 要加在真正攒数据的那个进程上；管道改的变量活不下来，`set -e` 抓不住管道失败——配 `pipefail` + `PIPESTATUS` 立刻存变量。**

---

## 第四幕：实操验证

### 实验 1：复现事故

已在第一幕完成。核心结论：

| 写法 | fd2 指向 | fd1 指向 | 结果 |
|------|----------|----------|------|
| `2>&1 >log` | 终端（抄的是搬家前的地址） | log | ❌ 错误上屏 |
| `>log 2>&1` | log（抄的是搬家后的地址） | log | ✅ 都在日志 |

### 实验 2：三种修复写法（输出完全一致）

```bash
# 接第一幕的 deploy.sh（已在本目录）
./deploy.sh > fixA.log 2>&1     # 修复 A：标准写法，POSIX 兼容
./deploy.sh &> fixB.log         # 修复 B：bash 专有，简洁但不便携
./deploy.sh 1> fixC.log 2>&1    # 修复 C：A 的显式版本
```

实测三者 diff 结果：`✓ 三种写法输出完全一致`。

**推荐 A 或 C**（`>log 2>&1`），理由：dash/sh 下同样成立，且 `1>` 的显式写法让"先改 fd1"这件事一目了然。

### 实验 3：双写（屏幕 + 日志）的三种方案

**方案 1：`tee`（最简单，推荐给一次性命令）**

```bash
# 接第一幕的 deploy.sh
./deploy.sh 2>&1 | tee tee.log
```

⚠️ 注意 `2>&1` 必须在 `|` 之前，否则 stderr 会绕过 tee 直接上屏。

**方案 2：`exec` 保存原 stdout（脚本内持久双写）**

```bash
LOG="${1:-/tmp/dual.log}"
exec 3>&1                        # fd3 = 原 stdout（终端）
exec 1>>"$LOG" 2>&1              # fd1/fd2 → 日志（追加）
echo "[INFO] 开始部署 $(date +%H:%M:%S)"
echo "[ERROR] 依赖缺失" >&2
echo "[INFO] 完成"
echo "[INFO] 部署已完成，详情见 $LOG" >&3   # 只把关键提示送终端
exec 3>&-
```

实测输出：

```
[INFO] 部署已完成，详情见 /tmp/c7act4/dual.log   ← 屏幕只看到这一条
dual.log：
[INFO] 开始部署 12:01:48
[ERROR] 依赖缺失
[INFO] 完成
```

**方案 3：`tee` + 进程替换（全量双写）**

```bash
# ⚠️ 反例：这个写法会导致重复输出，不要照抄执行
./deploy.sh > >(tee proc.log) 2>&1
```

> ⚠️ **实测警告**：这个写法在本机出现了**重复输出**——因为 `2>&1` 在 `> >(tee)` 之后，stderr 被复制进 tee 的同时又走了一遍外层。
>
> 正确写法是把 `2>&1` 放在前面：
> ```bash
> ./deploy.sh 2>&1 > >(tee proc.log)
> ```
> 或者干脆用方案 1 的管道形式（更直观、不会出现这种顺序问题）。

**方案选型建议：**

| 场景 | 推荐方案 |
|------|----------|
| 临时命令想同时看和存 | 方案 1 `tee` |
| 脚本内全量日志 + 少量交互提示 | 方案 2 `exec 3>&1` |
| 脚本内全量双写（日志 + 屏幕都全） | 方案 2 里用 `tee` 的思路，或方案 1 |

### 实验 4：脚本级持久重定向 + 临时切回终端

```bash
exec 3>&1                     # 保存真终端
exec 1>all.log 2>&1           # 全量进日志

echo "=== 正常流程（进日志）==="
echo "[ERROR] 某个错误" >&2

echo "请把回答写到 fd3" >&3    # 需要用户确认时，临时切回终端

echo "=== 继续（进日志）==="
echo "完成"
exec 3>&-
```

实测：

```
请把回答写到 fd3              ← 只有这一行上屏
[脚本结束]
all.log：
=== 正常流程（进日志）===
[ERROR] 某个错误
=== 继续（进日志）===
完成
```

这是"日志归日志，交互归交互"的标准模式。

### 实验 5：用 here-doc 生成配置文件（实战）

已在知识点 2 例 1 演示。核心技巧是**两段 here-doc 拼接**：

```bash
{
cat <<EOF
# 自动生成，请勿手改
app_name: $APP
port: $PORT
workers: $WORKERS
generated_at: $(date +%Y-%m-%d)
EOF
cat <<'EOF'
# 以下为 nginx 变量，必须原样保留
log_format: '$remote_addr - $request'
EOF
} > app.conf
```

实测生成：

```
# 自动生成，请勿手改
app_name: myapp
port: 8080
workers: 4
generated_at: 2026-09-04
# 以下为 nginx 变量，必须原样保留
log_format: '$remote_addr - $request'
```

用 `{ }` 包起来统一重定向，避免两次 `>` 导致后者覆盖前者。

### 实验 6：管道缓冲实战——实时看进度

已在知识点 3 例 1 演示。修复前后对比：

| 写法 | 时间戳分布 | 体验 |
|------|-----------|------|
| `./longrun.sh \| grep "步骤" \| while read` | 5 条全在 12:01:50 | 干等 2 秒，一次到账 |
| `./longrun.sh \| stdbuf -oL grep "步骤" \| while read` | 12:01:50→52 逐条 | 实时 |

### 实验 7：安全写入——避免半截文件

**危险写法**（直接重定向，中途失败留下半截）：

```bash
( echo "新内容第一行"; echo "新内容第二行"; exit 1 ) > important.conf
```

实测：

```
退出码=1
important.conf 内容（原内容已被清空！）：
新内容第一行
新内容第二行
```

**原内容在命令启动的瞬间就被 `>` 截断了**，即使后面失败也回不去了。

**安全写法**（先写临时文件，成功再原子 `mv`）：

```bash
( echo "新内容第一行"; echo "新内容第二行"; exit 1 ) > important2.conf.tmp
if [ $? -eq 0 ]; then
  mv important2.conf.tmp important2.conf
  echo "写入成功"
else
  rm -f important2.conf.tmp
  echo "写入失败，原文件完好"
fi
```

实测：

```
写入失败，原文件完好
important2.conf 内容：
原始内容
```

`mv` 在同一文件系统内是**原子操作**（rename 系统调用），要么全成功要么全不动。

### 实验 8：`noclobber` 防止误覆盖

```bash
echo "已有内容" > nc.txt
set -o noclobber
echo "新内容" > nc.txt 2>&1
echo "退出码=$?"
```

实测：

```
退出码=1
nc.txt 内容（应仍是原有）：
已有内容
```

stderr 输出（bash 自动给出）：

```
./act4.sh: line 201: nc.txt: cannot overwrite existing file
```

需要强制覆盖时用 `>|`：

```bash
echo "强制新内容" >| nc.txt
```

实测：`nc.txt 内容：强制新内容`。

> 💡 生产建议：在生成重要配置的脚本开头加 `set -o noclobber`，把"误覆盖"从"静默数据丢失"变成"显式报错"。

---

## 第五幕：体系收束

### 阶段 2《语言内核》收束

至此，阶段 2 的四课完成：

| 课 | 主题 | 核心交付 |
|----|------|----------|
| 课 4 | 变量属性与作用域 | `local`/`declare`/nameref 的可见性规则 |
| 课 5 | 数组与映射 | 索引/关联数组、`mapfile`、遍历陷阱 |
| 课 6 | 函数与调用约定 | 函数即命令、`"$@"` 透传、递归的两道墙 |
| 课 7 | 重定向与文件描述符 | fd 表模型、here-doc、缓冲三档 |

**一条主线贯穿：bash 的"看起来一样"背后是不同的机制。**

- 课 6：`$@` 与 `$*` 无引号时行为一致，加引号才分道扬镳。
- 课 7：`2>&1 >log` 与 `>log 2>&1` 只差顺序，结果完全相反；`&>` 与 `>file 2>&1` 在 bash 下等价、在 dash 下一个生效一个静默失效。

### 本课三个知识点的内在联系

```
fd 表（知识点 1）
  ↓ 决定了重定向怎么写
here-doc（知识点 2）—— 只是一种特殊的输入重定向
  ↓ 内容都要经过某个 fd
管道与缓冲（知识点 3）—— 多个 fd 串起来后的行为
```

它们其实是**同一张 fd 表的三种玩法**：重定向改 fd 指向、here-doc 造临时输入、管道把 fd 串成链。

### 为什么 fd 是理解子 shell 的前置

本课反复出现"管道两侧在子 shell 里"，但没展开**子 shell 到底继承什么**：

- 环境变量、fd 表、当前目录——**继承**
- shell 变量、函数、trap、作业控制——**部分不继承或行为特殊**

这正是阶段 3《进程边界》的课 8《子shell与执行上下文》要正面回答的。本课埋下的两个伏笔：

1. `while read` 在管道右侧改不了外部变量 → 子 shell 边界。
2. `exec` 的重定向**不创建子 shell**（直接改当前 shell 的 fd 表）→ 这正是不用子 shell 也能改 fd 的原因。

### 通往阶段 3

阶段 3 的三课围绕**进程**展开：

- 课 8《子shell与执行上下文**：`$( )`、管道、`( )`、命令替换各自的子 shell 边界与继承规则
- 课 9《信号trap与清理**：`trap`、临时文件清理、优雅退出（本课的全缓冲丢数据问题在这里有更完整的解法）
- 课 10《与文本工具的协作**：`awk`/`sed`/`grep` 与 shell 的分工（本课的缓冲知识直接决定协作效率）

---

## 🐞 常见误区

### 重定向（知识点 1）

1. **以为 `2>&1` 建立永久关联** → 它只是当时复制一次（dup2），之后两个 fd 独立。
2. **用 `&>` 写可移植脚本** → dash 下静默失效，日志 0 字节但退出码 0。
3. **关闭 fd 后继续写** → `write error: Bad file descriptor`，退出码 1。
4. **以为 `<>` 打开后写入会覆盖** → 读操作移动了偏移，写入变成追加。
5. **`>` 到重要文件** → 命令启动瞬间就截断原文件，失败也回不去。用临时文件 + `mv`。

### here-doc / here-string（知识点 2）

6. **以为 `<<"EOF"` 会展开** → 双引号同样关闭展开。
7. **用空格缩进配合 `<<-`** → 只吃 Tab，空格保留且会连带让结束符失效。
8. **结束定界符前后带空格** → here-doc 不终止，一直读到文件末尾，后续命令被当内容吞掉。
9. **以为 here-string 会词拆分** → 不拆分，整串传入。
10. **忘了 here-string 会补尾换行** → 传给 `wc -c` 会比预期多 1 字节。

### 缓冲与管道（知识点 3）

11. **以为 `set -e` 能抓管道失败** → 不能，必须配 `pipefail`。
12. **过一会儿才读 `PIPESTATUS`** → 任何命令都会重置它，须立刻存变量。
13. **`stdbuf` 加在过路的 `cat` 上** → 无效，要加在真正做缓冲的进程（grep/python）上。
14. **管道里 `while` 改变量期望外面可见** → 子 shell，改不了。用重定向或进程替换。
15. **以为进程被杀时已输出的内容已落盘** → 全缓冲 + SIGKILL = 全部丢失（实测 0 字节）。

---

## 一图总结

```mermaid
flowchart TD
    A["一条命令要输出"] --> B{"输出到哪"}
    B -->|终端 tty| C["行缓冲<br/>遇换行就写"]
    B -->|管道/文件| D["全缓冲<br/>攒满 4KB 才写"]
    D --> E{"进程是否 SIGKILL"}
    E -->|是| F["缓冲区蒸发<br/>实测 0 字节"]
    E -->|否正常退出| G["退出前 flush<br/>内容完整"]
    D --> H["解法 stdbuf -oL / -u<br/>加在做缓冲的进程上"]

    I["2&gt;&amp;1 &gt;log"] --> J["fd2 抄 fd1 旧地址<br/>❌ 错误上屏"]
    K["&gt;log 2&gt;&amp;1"] --> L["fd2 抄 fd1 新地址<br/>✅ 都在日志"]

    M["here-doc"] --> N{"定界符有引号?"}
    N -->|有| O["不展开<br/>原样送达"]
    N -->|无| P["全展开<br/>变量/命令/算术"]

    Q["管道 while 改变量"] --> R["子 shell<br/>外面看不见"]
    R --> S["改用重定向或进程替换"]

    T["set -e"] --> U["抓不住管道失败"]
    U --> V["加 pipefail<br/>+ PIPESTATUS 立刻存"]
```

**三句话版本：**

1. 重定向从左到右复制指针，想让错误进日志就写 `>log 2>&1`。
2. here-doc 定界符加引号 = 整段不展开，生成配置文件用两段拼接。
3. 连管道变全缓冲，`stdbuf -oL` 加在做缓冲的进程上，管道改的变量活不下来。

---

## 课后小测

<details>
<summary>第 1 题（知识点 1 · 基础）</summary>

**题目**：`cmd 2>&1 > log` 和 `cmd > log 2>&1` 的区别是什么？分别说明 fd1 和 fd2 最终指向哪里。

**参考解**：

`2>&1 > log`：**错误上屏，正常输出进日志**。

- 第 1 步 `2>&1`：fd2 复制 fd1，此时 fd1 指向终端 → fd2 也指向终端。
- 第 2 步 `>log`：fd1 改指向 log。fd2 不受影响，仍指向终端。

`> log 2>&1`：**两者都进日志**。

- 第 1 步 `>log`：fd1 改指向 log。
- 第 2 步 `2>&1`：fd2 复制 fd1，而 fd1 已是 log → fd2 也指向 log。

关键：`n>&m` 是**当时复制（dup2）**，不是建立永久关联。实测佐证——先 `exec 2>&1` 再 `exec 1>/dev/null`，走 fd2 的 `echo` 仍然显示在终端。

</details>

<details>
<summary>第 2 题（知识点 1 · 基础）</summary>

**题目**：`&>file` 和 `>file 2>&1` 是否等价？在什么情况下会出问题？

**参考解**：

在 **bash 下等价**（实测两者输出 diff 一致），但 `&>` 是 **bash 扩展，不可移植**。

会出问题的情况：脚本被 `sh script.sh` 调用，或 shebang 是 `#!/bin/sh`（如本机 `/bin/sh -> dash`）。

实测 dash 下：

```
sh -c './dual.sh &>e.log; echo "sh 退出码=$?"'
sh 退出码=0
OUT-正常输出        ← 内容全跑到屏幕
ERR-报错信息
e.log 存在吗：
-rw-r--r-- 1 root root 0 ... e.log   ← 0 字节
```

dash 把 `&` 解析成**后台运行符**，`>e.log` 单独成立创建了空文件。**退出码仍是 0，零报错**——日志文件空空如也却显示成功，是最危险的一类失败。

**建议**：写需要移植的脚本用 `>file 2>&1`。

</details>

<details>
<summary>第 3 题（知识点 1 · 进阶）</summary>

**题目**：如何在脚本内实现"全量输出进日志，但关键提示仍显示在终端"？写出核心代码。

**参考解**：

```bash
#!/usr/bin/env bash
LOG="/tmp/dual.log"
exec 3>&1                        # fd3 保存原 stdout（终端）
exec 1>>"$LOG" 2>&1              # fd1/fd2 都改指向日志（追加）
echo "[INFO] 开始部署 $(date +%H:%M:%S)"
echo "[ERROR] 依赖缺失" >&2
echo "[INFO] 完成"
echo "[INFO] 部署已完成，详情见 $LOG" >&3   # 只有这行进终端
exec 3>&-                        # 用完关掉
```

实测输出：屏幕只有 `[INFO] 部署已完成，详情见 /tmp/dual.log` 一行，日志里有全部 4 行。

要点：

- `exec 3>&1` 必须在改 fd1 **之前**。
- `exec`（不带命令）的重定向对当前 shell **永久生效**，后续所有命令都受影响。
- 用 `>>` 追加以免覆盖历史日志；用 `>` 则每次清空。
- 结尾 `exec 3>&-` 是好习惯，避免 fd 泄漏。

</details>

<details>
<summary>第 4 题（知识点 1 · 进阶）</summary>

**题目**：`exec {fd}>file` 相比手写 `exec 3>file` 有什么好处？bash 从几号开始分配？

**参考解**：

好处：**自动挑一个空闲 fd 号，避免与手工占用的或被调用函数内部的 fd 冲突**。手写 3-9 容易撞车（比如你用 fd3，调用的函数也用 fd3，互相覆盖）。

用法：

```bash
exec {myfd}>auto.txt
echo "自动 fd 号 = $myfd"          # 实测输出 10
echo "内容" >&"${myfd}"
exec {myfd}>&-
```

**bash 从 10 开始**往上找空闲号（实测 `fa=10 fb=11`，两个自动分配互不冲突），刻意避开了手工常用的 3-9。

注意引用时必须带花括号和引号：`>&"${myfd}"`，写成 `>&$myfd` 在复杂场景下可能被误解析。

</details>

<details>
<summary>第 5 题（知识点 2 · 基础）</summary>

**题目**：下面四种定界符写法，哪些会展开变量？

```bash
cat <<EOF      # A
cat <<'EOF'    # B
cat <<"EOF"    # C
cat <<\EOF     # D
```

**参考解**：**只有 A 会展开**。

实测（变量 `NAME="world"`）：

| 写法 | 输出 |
|------|------|
| A `<<EOF` | `hello world`（展开） |
| B `<<'EOF'` | `hello $NAME`（不展开） |
| C `<<"EOF"` | `hello $NAME`（**不展开**） |
| D `<<\EOF` | `hello $NAME`（不展开） |

**规则：定界符只要有引号或转义，整个 here-doc 就等同于被单引号包裹。**

C 是最容易记错的——双引号在 shell 里"通常"允许变量展开，但在 here-doc 定界符上**行为与单引号一致**。

</details>

<details>
<summary>第 6 题（知识点 2 · 基础）</summary>

**题目**：`<<-EOF` 能去掉缩进，但有个重要限制是什么？违反它会怎样？

**参考解**：**只吃 Tab，不吃空格**。

违反（用空格缩进）的后果不只是缩进保留——**连结束定界符都会失效**：

```
space_only.sh: line 3: warning: here-document at line 1 delimited by end-of-file (wanted `EOF')
    空格缩进的行
    EOF                    ← 结束符被当普通内容打印了
```

因为 `<<-` 只剥离 Tab，带空格的 `    EOF` 不匹配定界符 `EOF`，bash 一直读到文件末尾才报 warning。

**同理，结束定界符必须在行首、前后都不能有空格**：

```
badterm.sh: line 4: warning: here-document ... (wanted `MARKER')
内容行
 MARKER
echo "这行本该是命令"      ← 被当成内容吞掉了
```

这类错误难查：warning 只说"读到了 EOF"，不指出哪行多了空格。**行尾空格是隐形杀手**。

</details>

<details>
<summary>第 7 题（知识点 2 · 进阶）</summary>

**题目**：要生成一份 nginx 配置，`server_name` 和 `port` 用 shell 变量，但 `log_format` 里的 `$remote_addr` 等必须原样保留。怎么写？

**参考解**：**两段 here-doc 拼接**，一段展开一段不展开。

```bash
DOMAIN="example.com"
PORT=8080

cat > nginx.conf <<EOF
server {
    listen $PORT;
    server_name $DOMAIN;
    access_log /var/log/nginx/$DOMAIN.access.log;
EOF

cat >> nginx.conf <<'EOF'
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer"';
}
EOF
```

或者用 `{ }` 包起来统一重定向（更干净，避免两次打开）：

```bash
{
cat <<EOF
listen $PORT;
server_name $DOMAIN;
EOF
cat <<'EOF'
log_format main '$remote_addr - $request';
EOF
} > nginx.conf
```

实测生成：

```
server {
    listen 8080;
    server_name example.com;
    access_log /var/log/nginx/example.com.access.log;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer"';
}
```

**替代方案**：无引号定界符 + 逐个转义 `\$`。但当转义多到影响可读性时，两段拼接更清晰。

</details>

<details>
<summary>第 8 题（知识点 3 · 基础）</summary>

**题目**：为什么同一条命令连终端时输出是实时的，接管道后就"卡住"了？

**参考解**：**C 标准库（stdio）会根据输出目标自动切换缓冲模式**。

- 连 **tty（终端）** → 行缓冲，遇到 `\n` 就写（人要看实时反馈）。
- 连 **管道/文件** → 全缓冲，攒满 4KB 才写（下游是程序，效率优先）。

实测确认 stdio 会自动检测：

```
--- 直连（非 tty）---
stdout 模式: 全缓冲(非 tty)
--- 用 script 伪造 tty ---
stdout 模式: 行缓冲(检测到 tty)
```

时间戳实证（每 0.6 秒一行，共 3 行）：

```
--- 全缓冲 ---
起始 12:00:34
12:00:36 | tick 0
12:00:36 | tick 1
12:00:36 | tick 2     ← 三条全扎堆，干等 2 秒后一次到账
--- 加 -u 无缓冲 ---
12:00:36 | tick 0
12:00:36 | tick 1
12:00:37 | tick 2     ← 逐条实时
```

**最致命的后果**：进程被 `SIGKILL` 强杀时来不及 flush，缓冲区内容**全部丢失**——实测全缓冲 0 字节 vs 无缓冲 49 字节。

**解法**：`stdbuf -oL`（行缓冲）/ `-o0`（无缓冲）/ `python3 -u` / 定期 `flush()`。

</details>

<details>
<summary>第 9 题（知识点 3 · 进阶）</summary>

**题目**：下面脚本为什么抓不到 `false` 的失败？怎么修？

```bash
set -e
false | true
echo "这行不该出现"
```

**参考解**：

**原因**：`set -e` 默认**不检查管道中除最后一段以外**的命令。管道的退出码是**最后一段**（`true` → 0），所以 `set -e` 认为成功。

实测：

```
--- set -e 能否抓到 ---
这行不该出现           ← 真的出现了！
退出码=0
```

**修法**：同时开 `pipefail`。

```bash
set -e
set -o pipefail
false | true
echo "这行不该出现"
```

实测：`退出码=1`，"这行不该出现"不再打印。

**进阶**：`pipefail` 只返回一个非 0 码。想知道**每一段**的退出码，用 `PIPESTATUS`，且**必须立刻存变量**：

```bash
false | true | false
st=("${PIPESTATUS[@]}")     # 立刻存！
echo "长度=${#st[@]}"        # 3
echo "内容=${st[*]}"         # 1 0 1
```

对比错误写法——在 `echo` 之后再取，长度只剩 1（上一条 `echo` 已重置了它）。

**实践建议**：生产脚本开头固定写 `set -euo pipefail`。

</details>

<details>
<summary>第 10 题（知识点 3 · 进阶 · 综合）</summary>

**题目**：下面的脚本统计行数永远是 0，为什么？给出两种修法。

```bash
N=0
cat data.txt | while read -r x; do
  N=$((N+1))
done
echo "N=$N"
```

**参考解**：

**原因**：管道的每一段都在**子 shell** 中运行。`while` 循环在右侧子 shell 里修改 `N`，子 shell 退出时修改随之丢弃，父 shell 的 `N` 始终是 0。

实测（1000 行数据）：`管道版 N=0`。

**修法 1：输入重定向**（最简单，绕过管道）

```bash
N=0
while read -r x; do N=$((N+1)); done < data.txt
echo "N=$N"        # 1000
```

**修法 2：进程替换**（保留"命令产生数据"的写法）

```bash
N=0
while read -r x; do N=$((N+1)); done < <(cat data.txt)
echo "N=$N"        # 1000
```

**修法 3：here-string**（数据已在变量里时）

```bash
N=0
while read -r x; do N=$((N+1)); done <<< "$multi"
```

三种实测都是 1000。

> 💡 补充：bash 4.2+ 可以开 `shopt -s lastpipe` 让管道最后一段在当前 shell 执行，但这会改变脚本语义（且不适用于交互式 shell），不如上面三种显式。

**延伸**：这与第 8 题的缓冲是**两个独立问题**——即使输出是实时的，变量照样传不出来。

</details>

---

## ✅ 评审结论（2026-09-04）

**评审方式**：主 agent 内联双视角（pedagogy + learner）

**P0 数：0 ｜ P1：3 项已修**

**评审视角一：pedagogy（教学结构）**

| # | 检查项 | 结论 |
|---|--------|------|
| 1 | 五幕结构完整（场景→冲突→揭示→实操→收束） | ✅ 五幕齐全，第一幕事故在第四幕实验 1 呼应 |
| 2 | 六要素展开（定义/直觉/原理/示例/误区/记住） | ✅ 三知识点 × 6 = 18 个 |
| 3 | 进阶定位（不讲零基础内容） | ✅ 无 `cd`/`ls` 入门，直击顺序敏感性与缓冲 |
| 4 | 结论均本机实测 | ✅ 64 项复核 + 44 代码块照抄验证 |
| 5 | 认知冲突有钩子 | ✅ `&>` 在 dash 下静默失效、全缓冲被强杀数据归零 |
| 6 | 首尾呼应 | ✅ 第一幕 deploy.sh 事故 → 第四幕三种修复方案验证 |
| 7 | 小测覆盖三知识点 | ✅ 10 题（基础 5 + 进阶 5） |
| 8 | 前后课程连接 | ✅ 接课 6 子 shell 伏笔，启课 8 进程边界 |

**评审视角二：learner（学员视角，挑剔地读）**

| # | 检查项 | 结论 |
|---|--------|------|
| 1 | 代码块能否照抄跑通 | ✅ 44 块语法+执行全通过；**P1×1 已修**：3 处调用未定义的 `deploy.sh` 会报 127，已在第一幕补构造代码 |
| 2 | 反例块是否会被误抄 | ✅ **P1×1 已修**：`> >(tee proc.log) 2>&1` 已标注"反例，不要照抄" |
| 3 | 输出块是否与实测一致 | ✅ 全部来自 `/tmp/c7*` 实测原始输出 |
| 4 | 数值是否如实（不美化） | ✅ 时间戳、字节数、fd 号均为原始值 |
| 5 | 工具不可用是否标注 | ✅ **P1×1 已修**：`unbuffer` 本机未安装，已标注并给替代方案 |
| 6 | 链接可达 | ✅ 上一课/阶段概览/课程目录三条均已验证 |

**实测数字来源**：全部来自本机 WSL Ubuntu（bash 5.2.21，`/bin/sh -> dash`）实测，脚本见 `/tmp/c7kp1`、`/tmp/c7kp1b`、`/tmp/c7kp2`、`/tmp/c7kp2b`、`/tmp/c7kp3`、`/tmp/c7kp3b`、`/tmp/c7kp3c`、`/tmp/c7act4`。

**本机环境差异提示**：`unbuffer` 未安装（属 expect 包），讲义已改用 `stdbuf` 与 `script -qec` 替代。

**实测数字来源**：全部来自本机 WSL Ubuntu（bash 5.2.21）实测，脚本见 `/tmp/c7*`。

---

## 课程导航

> 上一课：[课 6《函数与调用约定》](./lesson-06-函数与调用约定.md) ｜ 下一课：[课 8《子shell与执行上下文》](../../3-进程边界/lessons/lesson-08-子shell与执行上下文.md)

---

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Bash 编程。我的学习档案在 shell/00-学习档案.md，
刚学完阶段 2《语言内核》的课《重定向与文件描述符》知识点 fd 表与重定向、here-doc 与 here-string、管道缓冲与协进程，
请按大纲继续讲解下一批知识点（进入阶段 3《进程边界》）。
```

---

## 📎 课程导航

**上一课**：[第 6 课《函数与调用约定》](./lesson-06-函数与调用约定.md)
**阶段概览**：[阶段 2《语言内核》](../overview.md)
**返回目录**：[课程目录](../../../02-课程目录.md)
