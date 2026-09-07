# 第 5 课：数组与映射

> 所属阶段：阶段 2《语言内核》｜ 水平：进阶 ｜ 本课知识点：索引数组、关联数组、mapfile 与数组操作
> 故事情节：deploy.sh 里 SERVICES="web api worker" 一直用得好好的，直到有人加了个叫 web server 的服务

## 🎯 本课目标

- 正确展开数组（""），处理稀疏数组与含空格元素
- 用关联数组做计数、去重、配置表，并正确判断键是否存在（-v）
- 用 mapfile -t 安全读入行，做切片、追加、排序去重

---

## 第一幕：起源与场景引入

> 🎬 **场景**：deploy.sh 里有一行 SERVICES="web api worker"，循环部署每个服务。跑了两年没事。某天有人加了个服务叫 web server（带空格），部署日志里开始出现「检查 [web]」和「检查 [server]」两条——一个服务裂成了两个。

看这段代码，你觉得它会输出什么？

`ash
SERVICES="web api worker"
check_health() { echo "  检查 [] ... ok"; }
for s in ; do check_health ""; done
`

两年来的输出（正常）：

`
  检查 [web] ... ok
  检查 [api] ... ok
  检查 [worker] ... ok
`

看起来毫无问题。现在把服务名换成带空格的，改用数组但**漏了引号**：

`ash
SERVICES=("web server" "api gateway" "worker")
for s in ; do check_health ""; done    # 注意：没加引号
`

实测输出：

`
  检查 [web] ... ok
  检查 [server] ... ok       # ← "web server" 裂成了两个
  检查 [api] ... ok
  检查 [gateway] ... ok      # ← "api gateway" 也裂了
  检查 [worker] ... ok
`

三个服务变成了五个。更糟的是**没有报错**——脚本愉快地跑完，退出码 0，只是部署了错误的东西。

而正确的写法只差**一对引号**：

`ash
for s in ""; do check_health ""; done
`

输出：

`
  检查 [web server] ... ok
  检查 [api gateway] ... ok
  检查 [worker] ... ok
`

这就是本课要解决的核心：**shell 的数组是最常用的数据结构，也是最容易写错的一个**——因为它的正确性几乎完全依赖一对引号，而漏掉引号时它不报错，只是安静地做错事。

---

## 第二幕：认知冲突

> ❓ **问题**：为什么 "" 和  差一对引号，结果就完全不同？

先看一个更基础的现象——@ 和 * 到底有什么区别：

`ash
arr=(a b c)
printf '"%s" ' ""; echo "   <-- \"\\""
printf '"%s" ' ""; echo "   <-- \"\\""
`

输出：

`
"a" "b" "c"      <-- ""
"a b c"          <-- ""
`

加引号时，@ 保持**独立元素**，* 合并成**单个字符串**。而不加引号时两者完全一样：

`ash
echo "无引号 : "    # → a b c
echo "无引号 : "    # → a b c
`

**关键洞察**：不加引号时，@ 和 * 都先展开成 a b c，然后这个字符串再被 shell 做**单词分割**——所以三个元素和一个字符串在这个阶段已经无法区分了。

引号的作用不是「保护数组」，而是**阻止展开后的单词分割**。所以：

| 写法 | 结果 | 元素个数 |
|------|------|----------|
|  | 先展开后分割 | 3（简单情况）／含空格则裂开 |
| "" | 展开后每个元素独立加引号 | **3（永远正确）** |
|  | 先展开后分割 | 同  |
| "" | 合并成一个字符串 | 1 |

**只有 "" 是安全的**，其余四种都有各自的问题。

但还有个更深的问题。看这个：

`ash
declare -A cfg=([host]="localhost")
echo "cfg[host]="
echo "cfg[nope]=[]"
`

不加 set -u 时， 是空字符串——**你分不清是「键不存在」还是「键存在但值为空」**。

而加上 set -u（生产脚本的标配）之后：

`
bash: cfg[nope]: unbound variable
`

**直接报错退出**。

所以本课真正的冲突不是「引号要不要加」，而是：**shell 的数组没有「安全访问」的概念——访问不存在的东西要么静默给空值，要么直接炸掉，中间没有缓冲地带**。得自己用 -v 建这道防线。

---
---

## 第三幕：层层揭示

### 知识点 1：索引数组

> 本知识点关键点：三种创建方式、@ 与 * 的引号差异、稀疏数组与真实下标、下标算术与负数下标、追加/删除/切片、空数组与未定义的区别

#### 一句话定义

索引数组是**按下标（整数）访问**的有序集合，下标可以不连续（稀疏），元素统一按字符串存储。

#### 直觉建立（类比）

把索引数组想成一排**带编号的信箱**，编号从 0 开始。

- `arr[3]="x"` 是直接往 3 号信箱塞信——**不需要 0/1/2 号先存在**，这就是稀疏数组的来历
- `${#arr[@]}` 数的是**有信的信箱数量**，不是最大编号
- `${!arr[@]}` 列出的是**有信的信箱编号**，不是 0 到 N 的连续序列
- `unset arr[1]` 是把 1 号信箱**清空**，不是把后面所有信箱往前挪——编号不会重新排

这一点和 Python/JS 的数组完全不同：那些语言的数组是紧凑的，`del arr[1]` 之后后面元素会前移。bash 不会。

#### 核心原理

**1. 三种创建方式（实测等价）**

```bash
arr1=(a b c)              # 最常用
declare -a arr2=(x y z)   # 显式声明
arr3[0]="one"; arr3[2]="three"   # 逐个赋值，可直接造稀疏数组
```

第三种方式实测：arr3 长度=2，下标=0 2——中间的下标 1 是**空洞**，不存在。

**2. @ 与 * 的引号差异（本课最重要的一条）**

实测：

```bash
arr=(a b c)
printf '"%s" ' "${arr[@]}"   # → "a" "b" "c"      三个独立元素
printf '"%s" ' "${arr[*]}"   # → "a b c"          一个合并字符串
```

`*` 的连接符受 IFS 控制：

```bash
IFS="-"
echo "${arr[*]}"              # → a-b-c
unset IFS                     # 恢复默认（空格）
```

含空格元素时的致命差异（实测）：

```bash
files=("my report.txt" "data.csv")
for f in ${files[@]};     do echo "[$f]"; done   # → [my] [report.txt] [data.csv]   ← 裂了
for f in "${files[@]}";   do echo "[$f]"; done   # → [my report.txt] [data.csv]      ← 正确
```

**3. 长度：两个 $# 长得像，含义不同**

```bash
arr=(a b c)
echo "${#arr[@]}"    # → 3   元素个数
echo "${#arr[0]}"    # → 1   第 0 个元素的字符数
echo "${#arr}"       # → 1   等价于 ${#arr[0]}（不带下标 = 下标 0）
```

`${#arr}` 这个写法是个陷阱——你想要长度 3，它给你 1。

**4. 稀疏数组：遍历必须用下标**

```bash
sp=(); sp[3]="three"; sp[7]="seven"
echo "${#sp[@]}"                       # → 2   长度
echo "${!sp[*]}"                       # → 3 7 真实下标

for e in "${sp[@]}";  do echo "$e"; done            # → three seven   只有值
for i in "${!sp[@]}"; do echo "sp[$i]=${sp[i]}"; done   # → sp[3]=three  sp[7]=seven
```

**取下标用 `${!arr[@]}`**——这个 `!` 和 indirect 那个 `${!var}` 长得很像，但作用在数组上是完全不同的含义（取下标列表）。

**5. 下标算术与负数下标**

```bash
a=(a b c d e)
echo "${a[2]}"      # → c
echo "${a[-1]}"     # → e    负下标从末尾数
echo "${a[-2]}"     # → d
n=2
echo "${a[n+1]}"    # → d    下标内可做算术（下标是算术上下文）
```

**6. 追加、删除、切片**

```bash
b=(1 2)
b+=(3 4)              # 追加多个元素
b[10]=11              # 跳跃赋值 → 下标 0 1 2 3 10，长度 5
unset "b[1]"          # 删除单个 → 下标 0 2 3 10，长度 4（不重新编号）
```

切片：

```bash
c=(a b c d e f)
echo "${c[@]:1:3}"    # → b c d     从下标 1 取 3 个
echo "${c[@]: -2}"    # → e f       负偏移（冒号后必须有空格！）
echo "${c[@]:2}"      # → c d e f   从下标 2 到末尾
```

⚠️ `${c[@]:-2}`（没有空格）会被解析成"默认值"语法，返回整个数组——**负偏移前必须留空格**。

**7. 空数组 vs 未定义（在 set -u 下天差地别）**

这是生产脚本最常见的崩溃点，实测：

```bash
set -u
unset e1                    # 从未声明过
e2=()                       # 声明了但是空

echo "${#e1[@]}"            # → bash: e1: unbound variable   报错！
echo "${#e2[@]}"            # → 0                             正常
echo "${e2[@]}"             # → （空）                        正常
```

**结论**：set -u 下，**未声明过的数组名会报错，已声明的空数组不会**。这就是为什么所有要用的数组都应该先 `arr=()` 初始化——一行初始化换掉一个潜在的崩溃点。

#### 示例演示

**示例 1：安全遍历（唯一正确姿势）**

```bash
declare -a services=("web" "api" "worker")
for svc in "${services[@]}"; do
    echo "部署 $svc"
done
```

**示例 2：需要下标时**

```bash
for i in "${!services[@]}"; do
    echo "$((i+1)). ${services[i]}"
done
```

**示例 3：切片做队列（注意 O(n)）**

```bash
q=(a b c d e)
head_elem="${q[0]}"
q=("${q[@]:1}")       # 出队：重建整个数组
echo "出队: $head_elem  剩余: ${q[*]}"
```

每次出队都重建数组，是 O(n)。元素多时应该用索引游标代替，别真拿数组当队列用。

**示例 4：查元素是否存在**

```bash
has_elem() {
    local needle=$1; shift
    local e
    for e in "$@"; do
        [[ "$e" == "$needle" ]] && return 0
    done
    return 1
}
list=("apple" "banana" "cherry")
has_elem "banana" "${list[@]}" && echo "在" || echo "不在"
```

**示例 5：数组作为函数参数——@ 与 * 的又一处分歧**

```bash
show_all() { echo "收到 $# 个参数"; for x in "$@"; do echo "  [$x]"; done; }
arr=("a b" "c")

show_all "${arr[@]}"    # → 收到 2 个参数：[a b] [c]     正确
show_all "${arr[*]}"    # → 收到 1 个参数：[a b c]       错误，元素被合并了
```

#### 常见误区

| ❌ 误区 | ✅ 事实 |
|---------|---------|
| `${arr[@]}` 不加引号也行 | 含空格元素会裂开，**必须** `"${arr[@]}"` |
| `${#arr}` 是数组长度 | 是**第 0 个元素的字符数**，长度是 `${#arr[@]}` |
| 数组下标总是连续的 | 可以稀疏，`sp[7]=x` 直接跳过中间 |
| `unset arr[1]` 后后面元素前移 | **不移动**，留下空洞，下标变成 0 2 3 |
| `${arr[@]:-2}` 取最后两个 | 冒号后**必须空格**：`${arr[@]: -2}`，否则是默认值语法 |
| set -u 下未声明数组取长度安全 | **报错** unbound variable，先 `arr=()` 初始化 |
| 数组能当队列高效使用 | 切片 `arr=("${arr[@]:1}")` 是 O(n)，大数组很慢 |

#### 一句话记住

> **遍历永远写 `"${arr[@]}"`，取下标用 `${!arr[@]}`，长度是 `${#arr[@]}`；set -u 下先 `arr=()` 再使用。**
---

### 知识点 2：关联数组

> 本知识点关键点：必须 `declare -A` 声明（否则退化成索引数组）、键可以是任意字符串、`-v` 判断键存在（`-n` 不行）、遍历顺序是哈希序不保序、计数/去重/配置表三个经典用法、`set -u` 下的访问陷阱

#### 一句话定义

关联数组是**按键（字符串）访问**的映射表，`declare -A` 声明后可用任意字符串作键。

#### 直觉建立（类比）

索引数组是**一排带编号的信箱**，关联数组是**一排带名牌的信箱**——信箱上写的不是 0/1/2，而是 `host`、`port`、`db host` 这样的名字。

关键区别：索引数组的"编号"是算术上下文（`arr[1+1]` 等于 `arr[2]`），关联数组的"名字"是**纯字符串**，不做任何求值。所以 `cfg[db host]` 就是字面意义上的 `db host` 这个键，中间有空格也没关系。

⚠️ 但如果你**忘了写 `declare -A`**，bash 会把它当成索引数组，键名被扔进算术上下文求值——`nod[k]` 里的 `k` 被当成变量，值为空则得 0，于是变成 `nod[0]`。这是关联数组最隐蔽的初始化错误，而且**不报错**。

#### 核心原理

**1. 必须 `declare -A`（实测对比）**

```bash
nod=([k]=v)              # 没写 -A！
echo "nod=[$nod]"        # → v
echo "nod[0]=[${nod[0]}]" # → v       ← k 被当算术式求值成 0，退化成 nod[0]

declare -A yes=([k]=v)
echo "yes[k]=${yes[k]}"  # → v        ← 正确
```

**2. 键是任意字符串（含空格）**

```bash
declare -A cfg=(["db host"]="localhost" ["db port"]="3306")
echo "${cfg["db host"]}"    # → localhost
echo "${!cfg[@]}"           # → db port db host
```

**3. 判断键存在：只有 `-v` 是对的**

这是本课第二个核心陷阱。设一个值为空字符串的键：

```bash
declare -A m=([a]=1 [b]="")     # b 存在，但值是空
```

| 方法 | `m[b]`（存在但空） | `m[zz]`（不存在） | 结论 |
|------|-------------------|------------------|------|
| `[ -v "m[b]" ]` | yes | no | ✅ **正确** |
| `[ -n "${m[b]}" ]` | no（误判） | no | ❌ 分不清 |
| `${m[b]-DEFAULT}` | 空（拿不到 DEFAULT） | DEFAULT | ❌ 分不清 |

实测：

```bash
[ -v "m[b]" ] && echo "存在" || echo "不存在"    # → 存在   ✅
[ -n "${m[b]}" ] && echo "非空" || echo "空"     # → 空     ❌ 误判为不存在
```

**记住：判断键存在用 `-v`，永远不要用 `-n`。**

**4. 遍历顺序是哈希序，不保序**

```bash
declare -A ord
for i in 5 3 9 1 7; do ord["k$i"]=$i; done
echo "${!ord[*]}"    # → k9 k5 k7 k1 k3   ← 不是插入顺序 k5 k3 k9 k1 k7
```

实测插入顺序 `k5 k3 k9 k1 k7`，遍历出来是 `k9 k5 k7 k1 k3`。**bash 的关联数组不保证任何顺序**（哈希序，且同一次运行内稳定，跨版本/跨数据量可能变）。

需要排序输出时，把键取出来排序：

```bash
mapfile -t keys < <(printf '%s\n' "${!ord[@]}" | sort)
for k in "${keys[@]}"; do echo "$k=${ord[$k]}"; done
```

**5. `set -u` 下的三种行为**

这是生产脚本的崩溃高发区，实测：

```bash
set -u
declare -A u=([x]=1)

echo "${u[x]}"          # → 1                                  正常
echo "${u[y]}"          # → bash: u[y]: unbound variable        报错退出！
[ -v "u[y]" ] && ...    # → 安全，不报错
```

**`set -u` 下访问不存在的关联数组键会直接终止脚本**。所以每次访问不确定的键之前，要么用 `-v` 检查，要么用 `${arr[key]:-默认值}` 兜底。

**6. `set -u` 下的自增陷阱（最容易踩）**

计数是关联数组最常见的用法，但在 `set -u` 下**直接自增会崩**：

```bash
set -u
declare -A cnt
((cnt["apple"]++))     # → bash: cnt: unbound variable   报错！
```

为什么？因为 `(( ))` 里访问 `cnt["apple"]` 时，这个键还不存在，`set -u` 判定为未绑定变量。

**三种修复方案（实测全部可用）**：

```bash
# 方案 1：-v 检查后初始化（最稳，推荐）
[ -v "cnt[$k]" ] || cnt[$k]=0
((cnt[$k]++))

# 方案 2：用 :-0 兜底（简洁）
((cnt[$k] = ${cnt[$k]:-0} + 1))

# 方案 3：键已知时，预先初始化为 0
declare -A cnt=([apple]=0 [banana]=0)
((cnt[apple]++))
```

**7. 索引数组 vs 关联数组的 `set -u` 豁免规则（实测总结）**

| 场景 | `set -u` 下行为 |
|------|----------------|
| `${#arr[@]}`（已声明，含空数组） | ✅ 正常 |
| `"${arr[@]}"`（已声明，含空数组） | ✅ 正常 |
| `${#undeclared[@]}`（从未声明） | ❌ 报错 unbound variable |
| 关联数组访问不存在的键 | ❌ 报错（无论是否 set -u，只是 set -u 下更严格） |
| `((关联数组[不存在的键]++))` | ❌ 报错 |
| `((索引数组[不存在的下标]++))` | ✅ 正常，当 0 处理 |

最后一条值得单独说：索引数组在算术上下文里，不存在的下标被当 0，不报错（实测 `((xs[5]++))` 后 `xs[5]=1`）。但关联数组不行——因为它的键不是数字，`set -u` 会当成未绑定变量。

#### 示例演示

**示例 1：计数（经典用法）**

```bash
declare -A cnt
words="apple banana apple cherry banana apple"
for w in $words; do
    ((cnt[$w] = ${cnt[$w]:-0} + 1))     # set -u 安全写法
done
for k in "${!cnt[@]}"; do echo "$k = ${cnt[$k]}"; done
```

实测输出：

```
cherry = 1
apple = 3
banana = 2
```

**示例 2：去重且保序**

关联数组做"已见过的"集合，索引数组保序：

```bash
declare -A seen
declare -a result=()
items="a b a c b a"
for it in $items; do
    if [ ! -v "seen[$it]" ]; then
        seen[$it]=1
        result+=("$it")
    fi
done
echo "${result[*]}"    # → a b c    保序去重
```

**示例 3：配置表（替代一堆全局变量）**

```bash
declare -A CONF=(
    [host]="prod-web-01"
    [port]="8080"
    [timeout]="30"
)
for k in "${!CONF[@]}"; do
    printf "%-10s = %s\n" "$k" "${CONF[$k]}"
done
```

**示例 4：二维数组模拟（复合键）**

bash 没有真正的二维数组，用"复合键字符串"模拟：

```bash
declare -A matrix
matrix["0,0"]="a"; matrix["0,1"]="b"
matrix["1,0"]="c"; matrix["1,1"]="d"

for r in 0 1; do
    for c in 0 1; do
        printf "matrix[%s,%s]=%s " "$r" "$c" "${matrix["$r,$c"]}"
    done
    echo
done
```

**示例 5：删除键与清空**

```bash
declare -A d=([a]=1 [b]=2 [c]=3)
unset "d[b]"          # 删单个键 → c a，长度 2
d=()                  # 清空整个关联数组 → 长度 0
```

#### 常见误区

| ❌ 误区 | ✅ 事实 |
|---------|---------|
| `arr=([k]=v)` 就建了关联数组 | **必须 `declare -A`**，否则退化成索引数组，键被算术求值 |
| `[ -n "${m[k]}" ]` 判断键存在 | 值为空时误判，用 `[ -v "m[k]" ]` |
| 关联数组保持插入顺序 | **不保序**（哈希序），需要顺序就自己排序 |
| `set -u` 下 `((cnt[$k]++))` 安全 | 键不存在时**报错退出**，用 `${cnt[$k]:-0}` 兜底 |
| 关联数组能切片 `${m[@]:0:1}` | 顺序无意义，切片结果不可靠 |
| 关联数组能 `+=` 追加元素 | 无此语义，只能 `m[key]=value` 逐个赋值 |

#### 一句话记住

> **关联数组必须 `declare -A`；判断键存在只用 `-v`；遍历顺序不保序；`set -u` 下自增必须先兜底。**
---

### 知识点 3：mapfile 与数组操作

> 本知识点关键点：`mapfile -t` 读入行（含 `-t` 去换行、末尾无换行也读入）、对比 `while read` 的子 shell 坑、进程替换避免子 shell、`-s`/`-n`/`-C` 选项、字符串切分、排序去重靠外部命令、数组拼接与 `+=`

#### 一句话定义

`mapfile`（别名 `readarray`）把**标准输入的每一行**读成数组的一个元素，是 shell 里最安全的逐行读入方式。

#### 直觉建立（类比）

`while read` 循环像**一个人站传送带旁，来一个包裹处理一个**——处理完包裹就没了，而且他站在小隔间里（管道版是子 shell），他在隔间里数的数，外面看不到。

`mapfile` 像**直接把传送带上所有包裹搬进仓库排好队**——全部一次性入库，之后你想怎么遍历、跳着看、反复看都行，而且仓库在主房间里（当前 shell），不存在"数了数外面看不见"的问题。

代价是：**包裹特别多时仓库会爆**（一次性读入内存）。

#### 核心原理

**1. 基本用法与 `-t`**

```bash
printf 'line1\nline2\nline3\n' > f.txt
mapfile -t lines < f.txt
echo "${#lines[@]}"      # → 3
echo "${lines[0]}"       # → line1
```

`-t` 是**去掉每行末尾的换行符**。不加 `-t` 时：

```bash
mapfile raw < f.txt
printf '%q\n' "${raw[0]}"    # → $'line1\n'      换行符被保留了
```

**几乎总是要加 `-t`**——不加的话每个元素尾部都带 `\n`，后续字符串比较会全部失配。

**2. 对比 `while read`：子 shell 陷阱**

这是 `mapfile` 存在的核心理由。看这个经典 bug：

```bash
cnt=0
cat f.txt | while read -r l; do cnt=$((cnt+1)); done
echo "cnt=$cnt"          # → 0     ← 数了 3 行，结果是 0！
```

**管道会创建子 shell**，`while` 循环在子 shell 里跑，`cnt` 的修改随着子 shell 退出而丢弃。

两种修法：

```bash
# 修法 1：改用重定向（不创建子 shell）
cnt=0
while read -r l; do cnt=$((cnt+1)); done < f.txt
echo "cnt=$cnt"          # → 3     ✅

# 修法 2：用 mapfile（更简洁）
mapfile -t lines < f.txt
echo "${#lines[@]}"      # → 3     ✅
```

**3. 最后一行没有换行符**

这是 `while read` 的第二个坑：

```bash
printf 'a\nb\nc' > nonl.txt      # 注意最后没有 \n

mapfile -t nl < nonl.txt
echo "${#nl[@]}  内容: ${nl[*]}"     # → 3  内容: a b c     ✅ 最后一行读到了

while read -r l; do echo "读到: [$l]"; done < nonl.txt
# → 读到: [a]  读到: [b]              ❌ c 丢了！
```

**`while read` 遇到没有换行符结尾的最后一行会返回非零，循环直接结束**。要补上 `|| [ -n "$l" ]`：

```bash
while IFS= read -r l || [ -n "$l" ]; do echo "读到: [$l]"; done < nonl.txt
# → 读到: [a]  读到: [b]  读到: [c]    ✅
```

**`mapfile` 没这个问题**——它照样读入最后一行。

**4. 常用选项（实测）**

```bash
printf 'a\nb\nc\nd\n' > o.txt

mapfile -t -s 1 sk < o.txt      # -s 1：跳过前 1 行      → b c d
mapfile -t -n 2 hd < o.txt      # -n 2：最多读 2 行      → a b
mapfile -t -d ':' cd < colon.txt # -d：自定义分隔符（默认 \n）
```

`-C 回调 -c 间隔`：每读入 N 行触发一次回调（适合做进度条）：

```bash
mapfile -t -C 'echo "已读 $1 行，当前: $2"' -c 1 cb < o.txt
```

实测输出：

```
已读 0 行，当前: a
已读 1 行，当前: b
已读 2 行，当前: c
已读 3 行，当前: d
```

注意 `$1` 是**下标**，`$2` 是**该行内容**。

**5. 从命令输出读入：进程替换**

```bash
mapfile -t out < <(printf 'x\ny\nz\n')     # ✅ 进程替换，无子 shell
```

`< <(...)` 是两个东西：`<` 是重定向，`<(...)` 是进程替换（把命令输出变成临时文件描述符）。这样 `mapfile` 在当前 shell 执行，变量不会丢。

**6. 字符串切分成数组**

```bash
s="a:b:c"
IFS=":" read -ra parts <<< "$s"
echo "${parts[*]}"       # → a b c
echo "${#parts[@]}"      # → 3
```

- `-r` 禁止反斜杠转义（几乎总是要加）
- `-a` 读入数组
- `<<<` 是 here-string，把字符串当标准输入

**7. 排序与去重：shell 没有内建，靠外部命令**

数组本身**没有排序方法**。标准做法是 `printf` + `sort` + `mapfile`：

```bash
fruits=("green apple" "banana" "apple")
mapfile -t sorted < <(printf '%s\n' "${fruits[@]}" | sort)
for f in "${sorted[@]}"; do echo "[$f]"; done
```

实测输出（`mapfile` 保住了含空格的元素）：

```
[apple]
[banana]
[green apple]
```

去重加 `-u`：

```bash
nums=(3 1 4 1 5 9 2 6)
mapfile -t uniqd < <(printf '%s\n' "${nums[@]}" | sort -n -u)
```

⚠️ **用 `$(...)` 接住排序结果会把含空格的元素切开**：

```bash
sorted_str=$(printf '%s\n' "${fruits[@]}" | sort)   # ❌ 变成一坨字符串
```

正确做法是用 `mapfile` 读回数组。

**8. 拼接与追加**

```bash
a1=(1 2); a2=(3 4)
both=("${a1[@]}" "${a2[@]}")     # 拼接成新数组 → 1 2 3 4
a1+=("${a2[@]}")                 # 追加到原数组 → a1: 1 2 3 4
```

注意 `+=` 右侧也要写 `"${a2[@]}"`——写 `$a2` 只会追加第 0 个元素。

**9. 内存边界**

`mapfile` 一次性读入全部行。1000 行实测正常，但**几十万行的大文件要慎用**——应该改回流式处理（`while read` + 重定向），或者用 `awk`/`sed` 这类流式工具处理完再取结果。

#### 示例演示

**示例 1：读入服务清单并过滤注释**

```bash
declare -a SERVICES=()
load_services() {
    local -n _out=$1
    local line
    _out=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue      # 跳过注释
        [[ -z "${line//[[:space:]]/}" ]] && continue     # 跳过空行
        _out+=("$line")
    done < /path/to/services.txt
}
load_services SERVICES
echo "载入 ${#SERVICES[@]} 个服务: ${SERVICES[*]}"
```

`IFS=` 是为了保留行首尾空格，`-r` 保留反斜杠。

**示例 2：去重保序函数（关联数组 + 索引数组组合）**

```bash
dedup() {
    local -n _out=$1; shift
    declare -A seen
    local e
    _out=()
    for e in "$@"; do
        [[ -v "seen[$e]" ]] && continue
        seen[$e]=1
        _out+=("$e")
    done
}
declare -a result
dedup result "b" "a" "b" "c" "a"
echo "${result[*]}"    # → b a c    保序去重
```

**示例 3：数组反转**

```bash
src=(1 2 3 4 5)
rev=()
for ((i=${#src[@]}-1; i>=0; i--)); do
    rev+=("${src[i]}")
done
echo "${rev[*]}"    # → 5 4 3 2 1
```

**示例 4：排序输出（保空格）**

```bash
mapfile -t sorted < <(printf '%s\n' "${arr[@]}" | sort)
```

#### 常见误区

| ❌ 误区 | ✅ 事实 |
|---------|---------|
| `mapfile` 不加 `-t` 也行 | 每行尾部会带 `\n`，后续字符串比较全部失配 |
| `cat f \| while read` 里改的变量外面能用 | **不能**，管道创建子 shell，改用 `< f` 或 `mapfile` |
| `while read` 能读到最后一行 | 末尾无换行符时**会丢**，需 `‖ [ -n "$l" ]` |
| `$(...)` 能接住排序结果 | 会把含空格元素切开，用 `mapfile < <(...)` |
| `arr+=$other` 追加整个数组 | 只追加第 0 个元素，要 `arr+=("${other[@]}")` |
| `mapfile` 适合任意大文件 | 一次性读入内存，超大文件应流式处理 |

#### 一句话记住

> **读行用 `mapfile -t`（记得 `-t`），从命令输出读用 `< <(...)`，排序去重后必须用 `mapfile` 读回数组，别用 `$(...)` 接。**
---

## 第四幕：实操验证

> 🎯 **任务**：把第一幕那个"服务名裂开"的脚本，从字符串拼逐步改到数组 + 关联数组 + 配置文件，每一步都实测验证。

### 版本 0：事故复现（字符串拼）

```bash
SERVICES="web api worker"
check_health() { echo "  检查 [$1] ... ok"; }
for s in $SERVICES; do check_health "$s"; done
```

输出（正常，看不出问题）：

```
  检查 [web] ... ok
  检查 [api] ... ok
  检查 [worker] ... ok
```

**问题潜伏**：这依赖"服务名不含空格"这个从未被写下来的假设。

### 版本 0b：事故升级

三个变体，暴露字符串方案的脆弱：

```bash
# 变体 1：意外的空值 → 静默跳过（不报错）
SERVICES=""
n=0; for s in $SERVICES; do n=$((n+1)); done; echo "n=$n"
```

实测：`n=0` —— 服务列表空了，脚本安静地什么都不做，退出码 0。

```bash
# 变体 2：服务名含空格 → 裂开
SERVICES=("web server" "api gateway" "worker")
for s in ${SERVICES[@]}; do check_health "$s"; done     # 数组但漏了引号
```

实测：

```
  检查 [web] ... ok
  检查 [server] ... ok       # ← web server 裂成两个
  检查 [api] ... ok
  检查 [gateway] ... ok      # ← api gateway 裂成两个
  检查 [worker] ... ok
```

三个服务变成五个，**零报错**。

```bash
# 变体 3：作为函数参数传递时
count_args() { echo "  收到 $# 个参数"; }
count_args $SERVICES        # → 收到 3 个参数（碰巧对了）
```

未加引号的 `$SERVICES` 会被单词分割，恰好"看起来能用"——这就是为什么这个 bug 能潜伏两年。

### 版本 1：改用索引数组 + 正确引号

```bash
declare -a SERVICES=("web" "api" "worker")
check_health() { echo "  检查 [$1] ... ok"; }
for s in "${SERVICES[@]}"; do check_health "$s"; done
deploy_count() { echo "  收到 $# 个服务"; }
deploy_count "${SERVICES[@]}"
```

实测：

```
  检查 [web] ... ok
  检查 [api] ... ok
  检查 [worker] ... ok
  收到 3 个服务
```

### 版本 2：含空格服务名也能扛

```bash
declare -a SERVICES=("web server" "api gateway" "worker")

# 正确
for s in "${SERVICES[@]}"; do check_health "$s"; done
# 错误（对照）
for s in ${SERVICES[@]}; do check_health "$s"; done
```

实测对比：

```
正确:  检查 [web server] ... ok
       检查 [api gateway] ... ok
       检查 [worker] ... ok

错误:  检查 [web] ... ok
       检查 [server] ... ok
       检查 [api] ... ok
       检查 [gateway] ... ok
       检查 [worker] ... ok
```

**差异只有一对引号**。

### 版本 3：关联数组存服务配置

服务不只是名字，还带端口、健康状态：

```bash
declare -A SVC_PORT=( [web]=80 [api]=8080 [worker]=9090 )
declare -A SVC_HEALTHY=()

probe() {
    local svc=$1
    local port=${SVC_PORT[$svc]:-0}
    if [ "$port" -eq 0 ]; then
        echo "  $svc: 未配置端口 -> 跳过"
        SVC_HEALTHY[$svc]="skip"
        return 1
    fi
    echo "  $svc: 探测 $port ... ok"
    SVC_HEALTHY[$svc]="ok"
}

for s in "${!SVC_PORT[@]}"; do probe "$s"; done
echo "--- 汇总 ---"
for k in "${!SVC_HEALTHY[@]}"; do printf "  %-8s %s\n" "$k" "${SVC_HEALTHY[$k]}"; done
```

实测：

```
  api: 探测 8080 ... ok
  web: 探测 80 ... ok
  worker: 探测 9090 ... ok
--- 汇总 ---
  api      ok
  web      ok
  worker   ok
```

注意 `${SVC_PORT[$svc]:-0}` 这个兜底——服务不在配置表里时拿到 0，而不是让 `set -u` 炸掉。

### 版本 4：从配置文件读入（mapfile / while read）

服务清单外置到文件，支持注释和空行：

```bash
# services.txt
web
api
# 这是注释
worker
```

```bash
declare -a SERVICES=()
load_services() {
    local -n _out=$1
    local line
    _out=()
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _out+=("$line")
    done < services.txt
}
load_services SERVICES
echo "  载入 ${#SERVICES[@]} 个服务:"
for s in "${SERVICES[@]}"; do echo "    [$s]"; done
```

实测：

```
  载入 3 个服务:
    [web]
    [api]
    [worker]
```

注释行被正确跳过，数组长度是 3 不是 4。

如果不需要过滤，`mapfile -t` 一行搞定：

```bash
mapfile -t SERVICES < services.txt
```

### 修复路径总结

| 版本 | 数据结构 | 含空格 | 空列表 | 附带配置 | 外置文件 |
|------|----------|--------|--------|----------|----------|
| 0 | 字符串拼 | ❌ 裂开 | ❌ 静默跳过 | ❌ | ❌ |
| 1 | 索引数组 + `"${arr[@]}"` | ✅ | ✅ 循环 0 次 | ❌ | ❌ |
| 2 | 索引数组（含空格验证） | ✅ | ✅ | ❌ | ❌ |
| 3 | 关联数组配置表 | ✅ | ✅ | ✅ | ❌ |
| 4 | + 文件读入 | ✅ | ✅ | ✅ | ✅ |

**诊断口诀**：看到 `for x in $SOMETHING` 或 `for x in ${arr[@]}`（无引号），立刻警觉——这是"元素裂开"的高发区。改成 `"${arr[@]}"` 只需要 4 个字符，能省掉两排查。

---

## 第五幕：体系收束

### 本课知识地图

```mermaid
graph TD
    A["要用数组存东西"] --> B{"按什么访问"}
    B -->|"数字下标"| C["索引数组<br/>declare -a"]
    B -->|"字符串键"| D["关联数组<br/>declare -A 必须写"]
    C --> E["遍历: \"\${arr\[@\]}\""]
    C --> F["取下标: \${!arr\[@\]}"]
    C --> G["长度: \${#arr\[@\]}"]
    D --> H["判存在: -v"]
    D --> I["遍历: \${!map\[@\]}"]
    D --> J["不保序, 需自排序"]
    A --> K["从哪来"]
    K -->|"文件"| L["mapfile -t arr < f"]
    K -->|"命令输出"| M["mapfile -t arr < <(cmd)"]
    K -->|"字符串"| N["IFS=x read -ra arr <<< s"]
    E --> O["含空格元素安全"]
    H --> P["set -u 下必须 -v 或 :-0"]
```

### 三个知识点的关系

```
索引数组（有序、按下标）  →  存"列表"
      ↓ 键换成字符串
关联数组（无序、按键）    →  存"映射"、做计数/去重
      ↓ 数据从哪来
mapfile / read -a        →  把外部数据装进上述两种结构
```

**索引数组管"顺序"**，**关联数组管"查找"**，**mapfile 管"输入"**。

### 与前后课程的连接

**向后接课 4（变量属性与作用域）**：课 4 给了 `-a` / `-A` 两个**属性**，本课展开**用法**。另外课 4 讲的 nameref 在本课的 `load_services` 里用上了——`local -n _out=$1` 让函数把数组写回调用者（记住 `_` 前缀，避免撞名静默失效）。

**向前接课 6（函数与调用约定）**：本课演示了 `"${arr[@]}"` 传参保持元素独立，但没展开 `"$@"` 与 `"$*"`、参数怎么穿过三层函数。那是课 6 的主题。

**悬念留到阶段 3**：本课反复出现"管道创建子 shell 导致变量丢失"。为什么管道会创建子 shell？子 shell 到底继承了什么？这是阶段 3 课 8《子 shell 与执行上下文》的核心内容。

### 三条可以立刻用上的规则

1. **遍历永远写 `"${arr[@]}"`**——漏引号是数组 bug 的头号来源，且不报错
2. **判断键存在只用 `[ -v "map[$k]" ]`**——`-n` 在值为空时误判
3. **读文件用 `mapfile -t`，读命令输出用 `mapfile -t arr < <(cmd)`**——避免子 shell 丢变量

---

## 🐞 常见误区

### 综合误区表

| # | ❌ 误区 | ✅ 事实 |
|---|---------|---------|
| 1 | `${arr[@]}` 不加引号也行 | 含空格元素会裂开，**必须** `"${arr[@]}"` |
| 2 | `${#arr}` 是数组长度 | 是第 0 个元素字符数，长度是 `${#arr[@]}` |
| 3 | `unset arr[1]` 后元素前移 | 不移动，留下空洞 |
| 4 | `${arr[@]:-2}` 取最后两个 | 冒号后必须空格 `${arr[@]: -2}` |
| 5 | 未声明数组在 `set -u` 下安全 | **报错**，先 `arr=()` 初始化 |
| 6 | `arr=([k]=v)` 建关联数组 | 必须 `declare -A`，否则退化成索引数组 |
| 7 | `[ -n "${m[k]}" ]` 判键存在 | 值为空时误判，用 `-v` |
| 8 | 关联数组保持插入顺序 | **不保序**，哈希序 |
| 9 | `set -u` 下 `((cnt[$k]++))` 安全 | 键不存在报错，用 `${cnt[$k]:-0}` |
| 10 | `cat f \| while read` 改的变量外面能用 | 不能，子 shell |
| 11 | `while read` 能读到最后一行 | 末尾无换行会丢，需 `‖ [ -n "$l" ]` |
| 12 | `$(...)` 接排序结果 | 切开含空格元素，用 `mapfile < <(...)` |
| 13 | `arr+=$other` 追加整个数组 | 只追加第 0 个，要 `arr+=("${other[@]}")` |
| 14 | `mapfile` 适合任意大文件 | 一次性读入内存 |

---

## 一图总结

```mermaid
graph LR
    subgraph 索引["索引数组"]
        A1["有序 / 数字下标"]
        A2["\"\${arr\[@\]}\" 遍历"]
        A3["\${!arr\[@\]} 下标"]
        A4["可稀疏 / unset 留洞"]
    end
    subgraph 关联["关联数组"]
        B1["必须 declare -A"]
        B2["-v 判存在"]
        B3["不保序"]
        B4["计数/去重/配置表"]
    end
    subgraph 输入["mapfile"]
        C1["-t 去换行"]
        C2["< <(cmd) 防子shell"]
        C3["末尾无换行也读入"]
    end
    A2 --> D["含空格安全"]
    B2 --> D
    C1 --> D
    B4 --> E["替代 eval 与字符串拼"]
    A1 --> E
```

**一句话记住**：

> **遍历加引号 `"${arr[@]}"`，判键用 `-v` 不用 `-n`，读入用 `mapfile -t` 配 `< <(...)`；数组的错误几乎都是静默的——不报错，只是做错。**

---

## 课后小测

### 基础题（6 题）

**1.** 下面代码输出什么？
```bash
arr=(a b c)
printf '"%s" ' "${arr[@]}"; echo
printf '"%s" ' "${arr[*]}"; echo
```

<details><summary>答案</summary>
<code>"a" "b" "c"</code> 然后 <code>"a b c"</code>。加引号时 @ 保持独立元素，* 合并成一个字符串。
</details>

**2.** 输出什么？
```bash
arr=(a b c)
echo "${#arr}"
echo "${#arr[@]}"
```

<details><summary>答案</summary><code>1</code> 然后 <code>3</code>。<code>${#arr}</code> 等价于 <code>${#arr[0]}</code>，是第 0 个元素的字符数。
</details>

**3.** 为什么这段代码在 `set -u` 下会崩？怎么修？
```bash
set -u
declare -A cnt
((cnt["apple"]++))
```

<details><summary>答案</summary>键 apple 不存在，<code>set -u</code> 判定为未绑定变量，报 <code>unbound variable</code> 并退出。修复三种：<code>((cnt[k] = ${cnt[k]:-0} + 1))</code>、先 <code>[ -v ] || cnt[k]=0</code>、或预先初始化所有键为 0。
</details>

**4.** 判断关联数组键是否存在，为什么 `-n` 不行？

<details><summary>答案</summary>键存在但值为空字符串时，<code>[ -n "${m[k]}" ]</code> 返回假，会误判为"不存在"。必须用 <code>[ -v "m[k]" ]</code>，它区分"键不存在"和"键存在但值为空"。
</details>

**5.** 为什么下面代码输出 0？怎么修？
```bash
cnt=0
printf 'a\nb\nc\n' | while read -r l; do cnt=$((cnt+1)); done
echo "cnt=$cnt"
```

<details><summary>答案</summary>管道创建子 shell，while 里的修改随子 shell 退出而丢弃。修复：改用 <code>while ... done < file</code>（重定向不建子 shell），或 <code>mapfile -t arr < file; echo ${#arr[@]}</code>。
</details>

**6.** 下面两段代码的区别？
```bash
mapfile -t a < f.txt
mapfile b < f.txt
```

<details><summary>答案</summary><code>-t</code> 去掉每行末尾的换行符。不加 <code>-t</code> 时，每个元素尾部带 <code>\n</code>（如 <code>a[0]</code> 是 <code>$'line1\n'</code>），后续字符串比较会全部失配。
</details>

### 进阶题（2 题）

**7.** 写一个 `dedup` 函数：接收任意个参数，返回**去重且保序**的结果数组。要求用 nameref 输出参数，且 nameref 变量名带前缀。

<details><summary>参考答案</summary>
<pre><code>dedup() {
    local -n _out=$1; shift
    declare -A seen
    local e
    _out=()
    for e in "$@"; do
        [[ -v "seen[$e]" ]] && continue
        seen[$e]=1
        _out+=("$e")
    done
}
declare -a r
dedup r "b" "a" "b" "c" "a"
echo "${r[*]}"    # → b a c
</code></pre>
关键点：关联数组做"已见过"集合、索引数组保序、<code>_out</code> 带前缀避免 nameref 撞名。
</details>

**8.** 有个文件每行一个服务名（可能含空格），要按字母序输出且不破坏含空格的元素。写出正确做法，并说明为什么 `$(...)` 不行。

<details><summary>参考答案</summary>
<pre><code>mapfile -t svcs &lt; services.txt
mapfile -t sorted &lt; &lt;(printf '%s\n' "${svcs[@]}" | sort)
for s in "${sorted[@]}"; do echo "[$s]"; done
</code></pre>

为什么 <code>$(...)</code> 不行：<code>sorted=$(printf '%s\n' "${svcs[@]}" | sort)</code> 会把所有行合并成一个字符串，含空格的元素（如 <code>web server</code>）在后续 <code>for s in $sorted</code> 时会被单词分割切开；而且命令替换会剥掉结尾的换行符。

> ⚠️ 注意：<code>mapfile</code> 是**纯读入、不过滤**——文件里的注释行和空行会原样进数组。上面用第四幕的 <code>services.txt</code>（含 <code># 注释</code> 行）做输入时，实测会输出 4 项，其中第一项是 <code>[# 注释]</code>。需要过滤就套用第四幕的 <code>load_services</code> 写法（<code>while IFS= read -r line ‖ [ -n "$line" ]</code> 逐行判断），或读入后追加一次过滤：
> <pre><code>mapfile -t raw &lt; services.txt
svcs=()
for line in "${raw[@]}"; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    svcs+=("$line")
done
</code></pre>
</details>

---

## 🚀 下一批接力提示词

> 学完本批后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Bash 编程。我的学习档案在 shell/00-学习档案.md，
刚学完阶段 2《语言内核》的课 5《数组与映射》知识点 索引数组、关联数组、mapfile 与数组操作，
请按大纲继续讲解课 6《函数与调用约定》的三个知识点。
```

---

## 📚 本课速览

| 知识点 | 一句话 | 最易踩的坑 |
|--------|--------|-----------|
| 索引数组 | 按下标访问，可稀疏 | 漏引号导致元素裂开；`${#arr}` 不是长度 |
| 关联数组 | 按键访问，必须 `declare -A` | `-n` 误判空值；`set -u` 下自增崩溃 |
| mapfile 与数组操作 | `mapfile -t` 安全读入行 | 管道子 shell 丢变量；末尾无换行丢行 |

**三条立刻用上的规则**：
1. 遍历永远写 `"${arr[@]}"`
2. 判键存在只用 `[ -v "map[$k]" ]`
3. 读文件 `mapfile -t`，读命令输出 `mapfile -t arr < <(cmd)`

---

## ✅ 评审结论

| 项目 | 结果 |
|------|------|
| 评审时间 | 2026-09-04 |
| 评审视角 | pedagogy（教学结构）+ learner（学员视角） |
| 复核项 | 75 项全通过（含学员视角照抄验证：讲义每个代码块原样落盘跑通） |
| P0 阻塞项 | 0 |
| P1 待修 | 2 项已修：① 小测第 8 题参考解直接 `mapfile` 读含注释文件，与第四幕过滤逻辑矛盾 → 补「mapfile 纯读入不过滤」警示 + 过滤代码（实测 4→3 项）；② 复核脚本 5 项失败均为脚本自身 bug（切片多元素未包成字符串、`set -u` 报错未被 `$( )` 捕获），非讲义错误，修正后 10 项全通过。另实测确认 3 处边界：`${arr[@]:-2}` 无空格退化为默认值语法、`set -u` 下未声明数组取长度报错但空数组安全、`((关联数组[缺键]++))` 报错而索引数组当 0 |

**本机环境**：WSL bash 5.2.21(1)-release (x86_64-pc-linux-gnu)，root 用户，nullglob=off，nocasematch=off，extglob=off。

---

**上一课**：[课 4 变量属性与作用域](./lesson-04-变量属性与作用域.md) ｜ **下一课**：[课 6 函数与调用约定](./lesson-06-函数与调用约定.md) ｜ **返回**：[阶段 2 概览](../overview.md) ｜ [课程目录](../../../02-课程目录.md)