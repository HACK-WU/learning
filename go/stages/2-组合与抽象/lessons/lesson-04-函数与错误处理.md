# 课 4：函数与错误处理

> 所属阶段：组合与抽象 ｜ 故事章节：没有 class，怎么组织代码 ｜ 上一课：[课 3 · 数组、切片与 map](../../1-语言地基/lessons/lesson-03-数组、切片与map.md)
> **状态：✅ 已完成** ｜ 版本基线：**Go 1.27.1 darwin/arm64**（核查于 2026-09）
> 📌 本课所有命令与输出**均在本机真实跑通并实测**（macOS / arm64 / go1.27.1），不是纸面预期。

## 📌 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 1 | 函数：多返回值与一等公民 | ①多返回值 `(T, error)` 惯用法 ②变参 `...T`（本质是切片）③函数是一等公民：可赋值、可传参、可作返回值；闭包 ④**一切都是值传递**（切片/map 拷贝的是描述符，改元素生效但 `append` 不生效） | ✅ 已完成 |
| 2 | error 是值 | ①`error` 是只有一个 `Error() string` 方法的接口 ②`errors.New` 与 `fmt.Errorf` ③`%w` 包装 + `errors.Is`/`errors.As`（**不要用 `==` 比包装过的错误**）④`panic`/`recover` 只用于**不可恢复**的情况 | ✅ 已完成 |
| 3 | defer 的机制与坑 | ①LIFO（后进先出）②**参数在 defer 语句处立即求值** ③循环里的 defer 会攒到函数返回才执行 ④与命名返回值互动；`os.Exit` 会跳过 defer | ✅ 已完成 |

---

## 第一幕 · 🏛️ 起源与场景引入

### 故事的转折：从"能跑"到"能组织"

阶段 1 结束时，小谷能写像样的逻辑了 —— 变量、类型、循环、切片、map 全会。但他的 `main.go` 已经涨到三百行，所有逻辑挤在一起：**查库存、扣库存、写订单、发通知**。

这周他开始把下单流程拆成一个个函数。前两个拆得很顺利，第三个开始就崩了 —— 不是编译崩，是**思维习惯崩**。

他写了几年 Python，肌肉记忆是这样的：

```python
def place_order(n):
    stock = get_stock()
    if stock < n:
        raise InsufficientStock("库存不足")   # 抛出去，上面有人接
    deduct(n)
    return order_id

try:
    place_order(200)
except InsufficientStock as e:   # 集中在一处兜住
    print("下单失败:", e)
```

翻成 Go 时他发现三件事都对不上：

1. **Go 没有 `raise`** —— 错误不能"抛出去"，只能**当作返回值一路传回来**；
2. **Go 没有 `try/except`** —— 没有"集中兜底"的地方，每一层都得自己决定"是放行还是处理"；
3. 于是每个调用点都多出三行 `if err != nil { return nil, err }` —— **他觉得这啰嗦得荒谬。**

然后他踩了三个坑，才明白这套"啰嗦"在替他做什么。

> 这一课是**阶段 2 的开篇**，也是小谷编程习惯的真正转折点：**从"靠异常甩锅给上层"转向"把错误当数据，在每一层显式决定"**。

---

## 第二幕 · ❓ 认知冲突

小谷的三个真实撞墙（**本机实测**）：

**怪事一：想 `raise` 抛异常，Go 里根本没有 `throw`/`raise`**

他照 Python 的习惯写了句 `raise`，编译器直接不认识。查了才知道：**Go 没有异常机制**（这是官方明确的设计决定，见 [FAQ · Why does Go not have exceptions?](https://go.dev/doc/faq#exceptions)）。

于是他每个函数都得写成这样：

```go
func placeOrder(n int) (int, error) {
    if err := checkStock(n); err != nil {
        return 0, err     // 错误当返回值传回去
    }
    ...
    return orderID, nil   // 成功时 error 是 nil
}
```

**"为什么不能像 Python 那样，在一个地方集中兜住所有错误？"**

**怪事二：用 `==` 判断"是不是库存不足"，明明是同一个错却判不出来**

```console
err = 下单 200 件失败: 库存不足
== 比较   : false      ← 明明根因就是 ErrInsufficient！
errors.Is : true       ← 换这个就对了
```

他用 `err == ErrInsufficient` 判断库存不足，**永远返回 false**。他调试了半小时才明白：错误被中间层用 `fmt.Errorf` 包装过了，`==` 比的是最外层那个包装壳，不是里面的原因。

**怪事三：循环里写 `defer f.Close()`，上线后文件描述符耗尽**

```console
  ❌ 错误写法：循环里 defer
    处理 a.txt（此时 fd 还开着，已开 1 个）
    处理 b.txt（此时 fd 还开着，已开 2 个）
    处理 c.txt（此时 fd 还开着，已开 3 个）
  循环结束：共开 3 个，只关了 0 个     ← 一个都没关！
```

他以为 `defer` 是"用完就关"，实际是"**攒到函数返回才关**"。处理一万个文件，就有一万个 fd 同时开着 —— 直到撞上系统的 fd 上限。

这三个怪事，分别对应本课的三个知识点。**它们共同指向同一件事：Go 把"控制流"和"错误处理"都摆在了明面上，不允许你隐式地甩给别处。**

---

## 第三幕 · 层层揭示

### 知识点 1：函数：多返回值与一等公民

#### 一句话定义

Go 的函数可以返回**多个值**（惯例把 `error` 放最后一个）、支持**变参** `...T`、可以被当作**一等公民**（赋值给变量、当参数传、当返回值用，还能形成**闭包**）；而参数传递**一律是值传递** —— 传入函数的是副本，但切片与 map 的副本仍**共享底层数据**。

#### 直觉建立：函数是一张可以贴在任何地方的便签

Python 里函数也是一等公民，这点小谷不陌生。真正让他意外的是**多返回值 + 值传递**这两条的组合。

想象你在填一张**三联单据**：

- **单返回值**：只给你"结果"那一联，出事了你得另想办法知道（抛异常 / 返回 -1 / 返回 null）。
- **Go 的多返回值**：一次给你"结果"和"错误"两联 —— **错误就写在单据上，跟结果平级**。

**这个类比在哪失效**：真实的纸单据你可能会弄丢第二联，而 Go 里"第二联"是**类型系统强制的** —— 你不用 `err` 就编译不过（课 1 学过的"未使用变量是编译错误"）。**这就是"啰嗦"的真相：它不是重复劳动，是编译器逼你正视每一个错误。**

#### 核心原理

**① 多返回值与 `(T, error)` 惯用法（实测）**

```go
// 普通多返回值
func divmod(a, b int) (int, int) {
    return a / b, a % b
}

// (T, error) —— Go 最经典的签名
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, fmt.Errorf("除数不能为 0 (a=%g, b=%g)", a, b)
    }
    return a / b, nil
}
```

实测：

```console
divmod(17, 5) = q=3 r=2
divide(10, 4) = 2.5
divide(10, 0) err = 除数不能为 0 (a=10, b=0) (返回值 v=0 是零值)
```

**`(T, error)` 的三条铁律**：

1. **`error` 永远放最后一个**（这是全 Go 生态的约定，不是语法强制）；
2. **出错时结果返回零值**（`return 0, err`）—— 调用方不该去读那个结果；
3. **成功时 error 必须是 `nil`**（`return v, nil`）—— 不能"又成功又有错"。

**命名返回值**（`naked return`）：

```go
func rect(w, h int) (area int, perim int) {
    area = w * h
    perim = 2 * (w + h)
    return   // 裸返回：返回 area, perim
}
```

实测：`rect(3,4) 命名返回值: area=12 perim=14`。

> ⚠️ **命名返回值只在短函数里可读**。函数体超过十几行时，裸 `return` 会让读代码的人不知道到底返回了什么。**Go Code Review Comments 的建议：短函数可以用，长函数显式写返回值。**
> 另外，命名返回值跟 `defer` 有一处非常反直觉的互动 —— 见知识点 3 ④。

**用 `_` 丢弃不需要的返回值**：`q2, _ := divmod(17, 5)` → 实测 `只要商: 3`。

**② 变参 `...T`（本质就是切片，实测）**

```go
func sum(nums ...int) int {
    total := 0
    for _, n := range nums { total += n }
    return total
}
```

实测：

```console
sum() = 0
sum(1,2,3) = 6
sum(1,2,3,4,5) = 15
变参: 收到 3 个，类型是 []int，值 [1 2 3]
sum(ns...) = 60 (切片展开，必须加 ...)
```

两个要点：

- **变参在函数体内就是切片**（`%T` 实测 `[]int`）；
- 把已有切片传进去，**必须加 `...` 后缀**：`sum(ns...)`。不加会编译错（`cannot use ns (variable of type []int) as int value`）。

**③ 函数是一等公民（实测）**

```go
type BinOp func(int, int) int

func add(a, b int) int { return a + b }
func mul(a, b int) int { return a * b }

// 函数作参数
func apply(op BinOp, a, b int) int { return op(a, b) }

// 函数作返回值（工厂）
func makeMultiplier(k int) func(int) int {
    return func(x int) int { return x * k }
}
```

实测：

```console
f = add; f(3,4) = 7
f = mul; f(3,4) = 12
apply(add, 3, 4) = 7 (函数作参数)
apply(mul, 3, 4) = 12
double(7) = 14, triple(7) = 21 (闭包捕获了各自的 k)
```

**闭包**（closure）= 函数 + 它捕获的外部变量。实测计数器：

```console
c1: 1 2 3
c1 继续: 4 | 新 c2: 1 (两个计数器互不影响)
```

**每次调用 `counter()` 都创建一份新的 `n`**，所以 `c1` 和 `c2` 各数各的。

**④ 一切都是值传递（本课最容易误解的一条，实测）**

Go **没有引用传递**。传入函数的永远是副本。但对切片和 map 来说，"副本"里装的是**指向底层数据的指针** —— 所以行为看起来像"引用"。

实测四种情况：

```console
tryModifyInt(1) 后 x=1 (不变 — int 是值拷贝)
tryModifySliceAppend 后 s=[1 2 3] len=3 (append 不影响调用方)
modifySliceElement 后 s=[999 2 3] (改元素生效 — 共享底层数组)
modifyMap 后 m=map[k:999] (改 map 生效 — map 头是指针)
modifyViaPointer(&y) 后 y=999 (传指针才改得动)
```

| 操作 | 调用方看得见吗 | 原因 |
|------|--------------|------|
| 改 `int` 形参 | ❌ | 纯值拷贝 |
| `append` 到切片形参 | ❌ | `append` 返回的新长度只赋给了形参副本（课 3 学过） |
| **改切片元素** `s[0]=999` | ✅ | 副本的 data 指针指向同一块底层数组 |
| **改 map 键值** `m[k]=v` | ✅ | map 头本身是指针（8 字节） |
| 改 `*T` 指向的值 | ✅ | 显式传了地址 |

**一句话记**：*"一切都是值传递，但有的值里面装的是地址。"*

#### 示例演示

```go
package main

import "fmt"

func divide(a, b float64) (float64, error) {
	if b == 0 {
		return 0, fmt.Errorf("除数不能为 0")
	}
	return a / b, nil
}

func sumAll(nums ...int) int {
	t := 0
	for _, n := range nums {
		t += n
	}
	return t
}

func adder(k int) func(int) int {
	return func(x int) int { return x + k }
}

func touch(s []int) { s[0] = 999 }        // 改元素
func grow(s []int)  { s = append(s, 777) } // append

func main() {
	if v, err := divide(10, 4); err == nil {
		fmt.Printf("10/4 = %g\n", v)
	} else {
		fmt.Println("err:", err)
	}
	if _, err := divide(1, 0); err != nil {
		fmt.Println("divide(1,0) err:", err)
	}

	fmt.Println("sumAll(1,2,3) =", sumAll(1, 2, 3))
	ns := []int{4, 5, 6}
	fmt.Println("sumAll(ns...) =", sumAll(ns...))

	add10 := adder(10)
	fmt.Println("add10(5) =", add10(5))

	s := []int{1, 2, 3}
	touch(s)
	fmt.Println("touch 后 s =", s) // 改元素生效
	grow(s)
	fmt.Println("grow 后  s =", s) // append 无效
}
```

**输出（本机实测）**：

```console
10/4 = 2.5
divide(1,0) err: 除数不能为 0
sumAll(1,2,3) = 6
sumAll(ns...) = 15
add10(5) = 15
touch 后 s = [999 2 3]
grow 后  s = [999 2 3]
```

最后两行是本节的核心：`touch` 改元素生效了，而 `grow` 的 `append` **对调用方毫无影响**。

#### 常见误区

- ❌ **"Go 的函数支持引用传递。"** 没有。**一律值传递**，只是切片/map 的值里装的是指针。
- ❌ **"把切片传给函数，函数里 `append` 外面能看到。"** 不能。`append` 要返回新切片，调用方必须接收（课 3 已实测）。
- ❌ **"变参 `...T` 和切片 `[]T` 是两回事。"** 函数体内 `nums` 就是 `[]T`；区别只在调用方（传切片要加 `...`）。
- ❌ **"命名返回值就是好风格。"** 短函数可读，**长函数是坑**（裸 `return` 不知道返回了什么，还跟 `defer` 有反直觉互动）。
- ❌ **"闭包捕获的是值。"** 捕获的是**变量**（Go 1.22 起循环里每轮是新变量，之前是共享的 —— 课 3 已实测）。

#### 一句话记住

> **Go 函数返回 `(T, error)` 把错误当作普通返回值传、支持 `...T` 变参、可以当值传来传去（闭包）；参数一律值传递，但切片/map 的副本仍共享底层数据 —— 所以改元素生效、`append` 不生效。**

📚 官方文档
- [go.dev spec · Function declarations](https://go.dev/ref/spec#Function_declarations)
- [go.dev spec · Function types](https://go.dev/ref/spec#Function_types)
- [go.dev spec · Passing arguments to ... parameters](https://go.dev/ref/spec#Passing_arguments_to_..._parameters)
- [go.dev spec · Calls（值传递语义）](https://go.dev/ref/spec#Calls)
- [Effective Go · Functions（多返回值与命名结果）](https://go.dev/doc/effective_go#functions)

---

### 知识点 2：error 是值

#### 一句话定义

`error` 是 Go 内置的**接口类型**，只有一个方法 `Error() string` —— **任何实现了这个方法的类型都能当错误用**。错误不是异常、不打断控制流，而是**一个普通的值**：可以被创建、返回、包装、比较、放进结构体。判断错误用 `errors.Is` / `errors.As`（**不是 `==`**），加上下文用 `fmt.Errorf` 的 `%w`。

#### 直觉建立：错误不是"警报"，是"附在包裹上的一张纸条"

Python 的异常像**火警警报**：一响，整层楼的人都停下来，往出口跑，直到某个 `except` 接住。

Go 的错误像**快递包裹上贴的纸条**：包裹照常往下传，每个经手的人都能看到纸条、决定怎么办 —— 原样往下传、加一句自己的说明再传、或者拆开处理掉。

**这个类比在哪失效**：火警有"强制停下"的效果，你不可能忽略它；而 Go 的纸条**可以被完全忽略**（`_ = someFunc()` 就把 error 丢了）。所以 Go 用编译器兜底：**你不用 `err` 变量就编译不过**（课 1 学过的"未使用变量是编译错误"）。

#### 核心原理

**① `error` 就是一个接口（官方定义）**

```go
type error interface {
    Error() string
}
```

就这么一个方法。所以**自定义错误类型极其简单** —— 实现 `Error() string` 即可：

```go
type ParseError struct {
    Line int
    Msg  string
}

func (e *ParseError) Error() string {
    return fmt.Sprintf("第 %d 行解析失败: %s", e.Line, e.Msg)
}
```

实测：`pe.Error() = 第 7 行解析失败: 字段数不匹配`；赋给 `error` 变量后照常工作（**隐式实现接口**，课 6 展开）。

另外实测：`errors.New` 返回的底层类型是 `*errors.errorString`。

**② 两种造错误的方式**

| 方式 | 用途 | 特点 |
|------|------|------|
| `errors.New("...")` | 固定的、可比较的**哨兵错误** | 惯例：包级变量、命名 `ErrXxx` |
| `fmt.Errorf("...%d", x)` | 带动态信息的错误 | 每次调用都是新值，**不能**用 `==` 比 |

```go
var (
    ErrNotFound   = errors.New("记录不存在")
    ErrPermission = errors.New("权限不足")
)
```

实测：`errors.New: 写死了的错误`、`fmt.Errorf: 带格式的错误: abc-42`。

**③ `%w` 包装 + `errors.Is`/`errors.As`（Go 1.13 引入，已核实）**

官方 Go 1.13 Release Notes 原文：

> 为了支持包装，`fmt.Errorf` 现在有了用于创建包装错误的 `%w` 动词，并且 `errors` 包中有三个新函数（`errors.Unwrap`、`errors.Is` 和 `errors.As`）……

（核查于 2026-09，来源：[go.dev/doc/go1.13 · Error wrapping](https://go.dev/doc/go1.13)）

**三层包装链路实测**：

```console
最上层错误: 处理请求失败: 查询订单 -1 失败: 记录不存在
  errors.Is(err, ErrNotFound) = true ✅ (能穿透两层 %w 找到根因)
  errors.Is(err, ErrPermission) = false (不是这个错)
```

**`errors.Unwrap` 逐层剥开**（实测）：

```console
  第 0 层: *fmt.wrapError → 处理请求失败: 查询订单 -1 失败: 记录不存在
  第 1 层: *fmt.wrapError → 查询订单 -1 失败: 记录不存在
  第 2 层: *errors.errorString → 记录不存在
```

**④ ❌ 用 `==` 比较包装过的错误（本课第二大坑，实测）**

```console
  err == ErrNotFound          = false ❌ (明明根因就是这个，但 == 比不出来)
  errors.Is(err, ErrNotFound) = true  ✅
```

**原因**：`err` 是被 `fmt.Errorf("%w")` 包了两层的 `*fmt.wrapError`（链上共 3 个节点：2 个包装壳 + 最底层的哨兵错误）。**`==` 比的是"这个壳是不是那个对象"，而 `errors.Is` 会沿 `Unwrap` 链一层层剥开比对。**

官方 [Error Value FAQ](https://go.dev/wiki/ErrorValueFAQ) 的明确建议：

> 如果你当前用 `==` 比较错误，改用 `errors.Is`。例：`if err == io.ErrUnexpectedEOF` 变成 `if errors.Is(err, io.ErrUnexpectedEOF)`。……如果你用类型断言或 type switch 检查错误类型，改用 `errors.As`。

（核查于 2026-09）

> 📌 **一个有用的例外**：官方 FAQ 说 **`io.EOF` 不需要改** —— 因为 `io.EOF` 约定上从不被包装，直接 `==` 就行。

**⑤ `%v` 包装会永久丢失链路（实测）**

```console
  errBad = 查询订单 -1 失败: 记录不存在
  errors.Is(errBad, ErrNotFound) = false ❌ (%v 把错误转成了字符串，链断了)
```

**`%v` 把错误渲染成字符串塞进新错误，原始错误的身份信息就此消失** —— `errors.Is` 再也找不到它。**要保留链路就只能用 `%w`。**

**⑥ `errors.As`：从包装链里取出具体类型（实测）**

```go
var target *ParseError
if errors.As(wrapped, &target) {
    fmt.Printf("Line=%d Msg=%s\n", target.Line, target.Msg)
}
```

实测对比：

```console
  errors.As 成功: Line=7 Msg=字段数不匹配 ✅
  直接断言 wrapped.(*ParseError) 失败 ❌ (被包了一层，断言不到)
```

**`errors.As` 会沿链找第一个匹配的类型；直接类型断言只能剥一层。**

**⑦ 标准库里的真实例子（实测）**

```console
  os.Open 错误: open /definitely/not/exist.txt: no such file or directory
  errors.Is(serr, os.ErrNotExist) = true ✅
  serr == os.ErrNotExist          = false ❌
  errors.As 取出 *os.PathError: Op=open Path=/definitely/not/exist.txt ✅
```

这就是官方建议的实战形态：**永远用 `errors.Is` 判断"是不是某类错"，用 `errors.As` 取出结构化信息。**

**⑧ `panic` / `recover`：只用于不可恢复的情况**

官方立场（[FAQ · Why does Go not have exceptions?](https://go.dev/doc/faq#exceptions)）：

> `try-catch-finally` 惯用法会把代码缠成一团……并**鼓励把"打开文件失败"这类普通错误当成异常**。

**什么时候该用 `panic`**：

| 该用 `panic` | 该返回 `error` |
|-------------|---------------|
| 程序**逻辑上不可能**发生（如 `switch` 的 `default` 分支不该到达） | 文件打不开、网络超时、参数非法 |
| 启动时就失败（配置严重错误，继续跑只会更糟） | 用户输入错误 |
| 数组越界、nil 解引用（这些是 bug，不是"情况"） | 任何"调用方能合理处理"的情况 |

**未捕获的 panic 会让进程崩溃**（实测）：

```console
准备触发未捕获的 panic...
panic: boom from level3

goroutine 1 [running]:
main.level3(...)
	/tmp/go-l04/err_panic_uncaught.go:7
main.level2(...)
	/tmp/go-l04/err_panic_uncaught.go:11
main.level1(...)
	/tmp/go-l04/err_panic_uncaught.go:15
main.main()
	/tmp/go-l04/err_panic_uncaught.go:20 +0x6c
exit status 2
```

注意 **退出码是 2**，且打印了完整调用堆栈。**panic 不是"异常"，是"程序崩溃前的最后一句话"。**

**`recover` 的三条规则（实测）**：

1. **只能在被 `defer` 的函数里调用才有效** —— 直接调 `recover()` 返回 `nil`：

```console
  -- 直接调 recover()（不在 defer 里）--
  recover() 返回 nil —— 无效！recover 只在被 defer 的函数里才有意义
```

2. **`panic` 时 `defer` 仍会按 LIFO 执行**（这是 `defer` + `recover` 能配合的基础）：

```console
  准备 panic...
  defer 2：我也执行（LIFO）
  defer 1：panic 时我依然会执行
  外层 recover 到: boom
```

3. **典型用法：把 panic 转成普通 error 返回给调用方**：

```go
func safeCall() (err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("捕获到 panic: %v", r)
        }
    }()
    mayPanic()
    return nil
}
```

实测：`safeCall 返回: 捕获到 panic: 这是一个 panic 值 ✅`。

> ⚠️ **边界：`panic(nil)` 在 Go 1.21 起不再是 nil**（实测 + 官方核实）。
>
> ```console
>   准备 panic(nil)...
>   recover() 返回: runtime error: panic called with nil argument (类型 *runtime.PanicNilError)
> ```
>
> 官方 Go 1.21 Release Notes 原文：*"Go 1.21 now defines that if a goroutine is panicking and recover was called directly by a deferred function, the return value of recover is guaranteed not to be nil. To ensure this, calling panic with a nil interface value (or an untyped nil) causes a run-time panic of type `*runtime.PanicNilError`."*
> （核查于 2026-09，来源：[go.dev/doc/go1.21](https://go.dev/doc/go1.21)；可用 `GODEBUG=panicnil=1` 恢复旧行为）

#### 示例演示

```go
package main

import (
	"errors"
	"fmt"
)

// 哨兵错误：惯例命名 ErrXxx，包级变量
var ErrInsufficient = errors.New("库存不足")

// 底层：返回哨兵错误
func checkStock(n int) error {
	if n > 100 {
		return ErrInsufficient
	}
	return nil
}

// 中间层：用 %w 包装，保留原因
func placeOrder(n int) error {
	if err := checkStock(n); err != nil {
		return fmt.Errorf("下单 %d 件失败: %w", n, err)
	}
	return nil
}

func main() {
	err := placeOrder(200)
	fmt.Println("err =", err)

	fmt.Println("== 比较   :", err == ErrInsufficient)          // false
	fmt.Println("errors.Is :", errors.Is(err, ErrInsufficient)) // true

	// 逐层剥开
	for e := err; e != nil; e = errors.Unwrap(e) {
		fmt.Printf("  %T → %v\n", e, e)
	}
}
```

**输出（本机实测）**：

```console
err = 下单 200 件失败: 库存不足
== 比较   : false
errors.Is : true
  *fmt.wrapError → 下单 200 件失败: 库存不足
  *errors.errorString → 库存不足
```

这就是第二幕怪事二的完整复现与解法：**用 `errors.Is`，别用 `==`。**

#### 常见误区

- ❌ **"用 `==` 判断错误就行。"** **只对未包装的哨兵错误成立**。一旦中间层用 `%w` 加了上下文，`==` 就失效 —— 用 `errors.Is`。
- ❌ **"用 `%v` 包装也能保留错误链。"** 不能。**`%v` 会把它渲染成字符串，链路永久断裂** —— 要保留必须用 `%w`。
- ❌ **"直接 `err.(*MyError)` 断言就够了。"** 只剥得了一层。用 `errors.As` 才能穿透多层包装。
- ❌ **"Go 有异常，只是叫 panic。"** 不是。`panic` 是"程序无法继续"的终止信号（**不可 recover 时进程直接死，退出码 2**），不是控制流工具。
- ❌ **"每个 panic 都应该 recover。"** 错。**recover 的典型用途只有两个**：①在库边界把 panic 转成 error；②在 HTTP 服务器里防止单个请求搞崩整个进程（课 11 会讲中间件 recover）。**滥用 recover 会掩盖真正的 bug。**
- ❌ **"`error` 字符串拿来比较/匹配就行。"**  fragile —— 改个措辞就断。用哨兵错误 + `errors.Is`。

#### 一句话记住

> **`error` 只是个 `Error() string` 接口 —— 错误是值不是异常；加上下文用 `fmt.Errorf` 的 `%w`，判断用 `errors.Is`（比"是不是这个错"）和 `errors.As`（取具体类型），**绝不用 `==` 比包装过的错误**；`panic`/`recover` 只留给"程序无法继续"的场合。**

📚 官方文档
- [go.dev spec · error 接口（builtin）](https://pkg.go.dev/builtin#error)
- [pkg.go.dev · errors 包](https://pkg.go.dev/errors)
- [go.dev blog · Working with Errors in Go 1.13](https://go.dev/blog/go1.13-errors)
- [go.dev wiki · Error Value FAQ](https://go.dev/wiki/ErrorValueFAQ)
- [go.dev FAQ · Why does Go not have exceptions?](https://go.dev/doc/faq#exceptions)
- [go.dev doc · Go 1.13 Release Notes（Error wrapping）](https://go.dev/doc/go1.13)

---

### 知识点 3：defer 的机制与坑

#### 一句话定义

`defer f()` 把 `f()` 的调用**推迟到当前函数返回时**执行。四个关键机制：**①多个 defer 按 LIFO（后进先出）执行；②`defer` 的参数在写 `defer` 那一行就立即求值；③推迟的是"函数返回时"而不是"块结束时"，所以循环里的 defer 会攒到函数返回；④`os.Exit` 会跳过所有 defer。**

#### 直觉建立：defer 是"出门前必做的检查清单"

你出差住酒店，前台给你一张**退房清单**：关空调、还房卡、开发票。

`defer` 就是"把要做的事写在这张清单上"，**离开房间（函数返回）时按清单反着做一遍**。

**这个类比在哪失效**：真实清单上你可以写"退房时再看空调是几度"（延迟读取）；而 Go 的 `defer` **在写清单的那一刻就把参数定死了** —— 你写"关掉 26 度的空调"，退房时空调可能早就是 18 度了，它还是照着"26 度"去关。**这是 defer 最大的坑（下面 ②）。**

另一个失效点：真实清单在**你离开房间时**执行，而 Go 的 defer 在**函数返回时**执行 —— 如果你在循环里反复"进出房间"（每次迭代），清单不会每次都执行，而是攒到最后一次才一起做（下面 ③）。

#### 核心原理

**① LIFO（后进先出，实测）**

```go
func lifo() {
    defer fmt.Println("  第 1 个 defer（最后执行）")
    defer fmt.Println("  第 2 个 defer")
    defer fmt.Println("  第 3 个 defer（最先执行）")
    fmt.Println("  函数体执行中...")
}
```

```console
  函数体执行中...
  第 3 个 defer（最先执行）
  第 2 个 defer
  第 1 个 defer（最后执行）
```

**越晚注册的 defer 越先执行** —— 上面注册顺序是「关数据库 / 关文件 / 解锁」，执行顺序**恰好倒过来**（**想让谁最后执行，就得最先注册它**）。

这条规则正是资源管理想要的：写代码时你按**申请顺序**依次写 defer —— 先加锁就先写 `defer 解锁`，再开文件写 `defer 关文件`，最后连数据库写 `defer 关数据库`；LIFO 会让执行顺序自动变成**申请的逆序**（关数据库 → 关文件 → 解锁），也就是"后申请的先释放"。

**② 参数在 `defer` 语句处立即求值（本课第一大坑，实测）**

```go
func evalNow() {
    i := 0
    defer fmt.Println("  defer 打印 i =", i)   // ← i 的值在此刻(0)就定死了
    i = 999
    fmt.Println("  函数体里 i 改成了", i)
}
```

```console
  函数体里 i 改成了 999
  defer 打印 i = 0     ← 打印的是 0，不是 999！
```

**`defer` 语句执行时，参数表达式就被求值并保存起来了**，跟函数返回时变量是什么值无关。

**循环里的经典表现**（实测）：

```console
  -- 循环里 defer，参数是立即求值的 --
  循环结束
  defer#2（LIFO 所以倒着来）
  defer#1（LIFO 所以倒着来）
  defer#0（LIFO 所以倒着来）
```

每轮的 `i` 被快照下来，所以打印 `2/1/0`（LIFO 顺序 × 各轮的快照值）。

**对比：闭包形式捕获的是变量本身**（实测）：

```console
  -- 闭包形式 defer func(){...}()：捕获的是变量 --
  循环结束
  闭包 defer，i=2
  闭包 defer，i=1
  闭包 defer，i=0
```

- `defer fmt.Printf(i)`：**参数立即求值** → 快照各轮的 `i`（0/1/2），LIFO 打印 2/1/0；
- `defer func(){ fmt.Println(i) }()`：**闭包捕获变量** → Go 1.22 起每轮是新变量，结果恰好也是 2/1/0（但机制完全不同）。

> 📌 **Go 1.21 及之前**：闭包形式会打印 `3/3/3`（所有闭包共享同一个循环变量，循环结束时 `i=3`）。Go 1.22 起每轮迭代创建新变量，这个坑消失了（课 3 已实测）。

**③ 循环里的 defer 会一直攒到函数返回（第三大坑，实测）**

```console
  ❌ 错误写法：循环里 defer
    处理 a.txt（此时 fd 还开着，已开 1 个）
    处理 b.txt（此时 fd 还开着，已开 2 个）
    处理 c.txt（此时 fd 还开着，已开 3 个）
  循环结束：共开 3 个，只关了 0 个     ← 一个都没关
    [关闭文件 #2]
    [关闭文件 #1]
    [关闭文件 #0]
  → processAllBad 返回后：开 3 关 3

  ✅ 正确写法：抽成小函数，defer 在每轮结束就执行
    处理 a.txt（处理完立刻关）
    [关闭文件 #0]
    处理 b.txt（处理完立刻关）
    [关闭文件 #1]
    处理 c.txt（处理完立刻关）
    [关闭文件 #2]
  → processAllGood 结束后：开 0 关 3
```

**错误写法在整个循环期间一个文件都没关** —— 处理一万个文件就有一万个 fd 同时开着，直到撞上系统上限（`too many open files`）。

**两种正确写法**：

```go
// 写法 1（推荐）：把每轮的处理抽成小函数，defer 就在小函数返回时执行
for _, name := range names {
    processOne(name)   // processOne 内部 defer f.Close()
}

// 写法 2：用匿名函数把 defer 包起来，立即执行
for _, name := range names {
    func() {
        f, _ := os.Open(name)
        defer f.Close()
        // 处理
    }()   // 匿名函数立即调用，defer 在它返回时执行
}
```

**④ 与命名返回值的互动（最反直觉的一条，实测）**

```go
// 命名返回值：defer 能改它
func namedReturn() (result int) {
    defer func() { result++ }()   // 改的是"返回值变量本身"
    return 1
}

// 非命名返回值：defer 改不了
func unnamedReturn() int {
    var result int
    defer func() { result++ }()   // 改的是局部变量，返回值已拷贝走了
    result = 1
    return result
}
```

```console
  defer 里 result++ → result=2
  namedReturn()   = 2  ← 不是 1！
  defer 里 result++ → 局部 result=2（但返回值已拷贝走了）
  unnamedReturn() = 1  ← 就是 1
```

**机制**：`return 1` 实际是两步 —— ①把 1 赋给返回值变量；②执行 defer；③真正返回。命名返回值让 `defer` 能**看到并修改**那个返回值变量；非命名返回值时，`defer` 里的 `result` 是另一个局部变量。

> ⚠️ **实践建议**：这个特性主要用于 **统一改写返回值**（比如"出错时把 nil 换成默认错误"），**日常不要靠它"偷偷改返回值"** —— 会让读代码的人算错结果。

**⑤ `os.Exit` 会跳过所有 defer（实测）**

```console
  准备 os.Exit(1)...
exit status 1
（"这个 defer 永远不会执行" 那行没有打印 → defer 被跳过）
```

> `exit status 1` 是 `go run` 在子进程非 0 退出时打印的。

`os.Exit` 是**立即终止进程**，不等任何 defer。**所以"用 defer 做清理 + 用 os.Exit 退出"是矛盾的组合** —— 要清理就别用 `os.Exit`（或先显式清理再 Exit）。

**⑥ `defer` 关资源：Close 的错误会被静默丢弃（实测）**

```go
defer c.Close()   // ❌ 返回值被丢弃，编译器不报错、go vet 也不报
```

```console
  defer c.Close() —— 返回值被丢弃（编译器不报错）
  defer func(){ if err := c.Close(); ... }() —— 错误被处理
  捕获到 Close 错误: Close 失败：磁盘满了
```

**对只读的文件，忽略 `Close` 错误通常无害**；但**对写入类资源，`Close` 可能返回"数据没真正落盘"的错误**（比如磁盘满、缓冲区 flush 失败）。要严格处理就写：

```go
defer func() {
    if err := f.Close(); err != nil {
        log.Printf("关闭文件失败: %v", err)
    }
}()
```

**⑦ defer 的性能**（Go 1.13 起大幅优化）

官方 Go 1.13 Release Notes 原文：*"This release improves performance of most uses of defer by 30%."*（引入了 open-coded defer，把多数 defer 直接内联到函数返回路径）。

（核查于 2026-09，来源：[go.dev/doc/go1.13](https://go.dev/doc/go1.13)）

**所以现在不必为了性能回避 defer** —— 可读性优先。真正的性能顾虑只在**极热的循环内部**（每轮都注册 defer 有开销，那也正是上述 ③ 该重构的场景）。

#### 示例演示

```go
package main

import (
	"fmt"
	"os"
)

// ① LIFO
func order() {
	defer fmt.Println("  3. 关数据库连接")
	defer fmt.Println("  2. 关文件")
	defer fmt.Println("  1. 解锁")
	fmt.Println("  干活中...")
}

// ② 参数立即求值
func evalNow() {
	i := 0
	defer fmt.Println("  defer 打印 i =", i) // i 的值在此刻就定死了
	i = 999
	fmt.Println("  函数体里 i 改成了", i)
}

// ③ 命名返回值：defer 能改它
func named() (n int) {
	defer func() { n++ }()
	return 1
}

// ④ 非命名：改不了
func unnamed() int {
	n := 1
	defer func() { n++ }()
	return n
}

// ⑤ defer 关资源
func readFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close() // 紧跟 Open，任何 return 都会关
	buf := make([]byte, 32)
	n, _ := f.Read(buf)
	return string(buf[:n]), nil
}

func main() {
	fmt.Println("LIFO:")
	order()

	fmt.Println("\n参数立即求值:")
	evalNow()

	fmt.Printf("\nnamed()   = %d  ← 不是 1！\n", named())
	fmt.Printf("unnamed() = %d\n", unnamed())

	s, err := readFile("go.mod")
	fmt.Printf("\nreadFile: %q err=%v\n", s, err)
}
```

**输出（本机实测）**：

```console
LIFO:
  干活中...
  1. 解锁
  2. 关文件
  3. 关数据库连接

参数立即求值:
  函数体里 i 改成了 999
  defer 打印 i = 0

named()   = 2  ← 不是 1！
unnamed() = 1

readFile: "module example.com/l04\n\ngo 1.27." err=<nil>
```

#### 常见误区

- ❌ **"defer 的参数在执行时才求值。"** **立即求值**（写 defer 那一行就定死）—— 这是 defer 第一大坑。
- ❌ **"循环里写 `defer f.Close()` 是每轮都关。"** 不是，**攒到函数返回** —— 会耗尽 fd。
- ❌ **"defer 按注册顺序执行。"** 是 **LIFO**（后注册的先执行）。
- ❌ **"`os.Exit` 前 defer 会执行。"** **不会** —— `os.Exit` 直接终止进程。
- ❌ **"defer 里改局部变量能改变返回值。"** 只有**命名返回值**才行；非命名返回值在 `return` 时已拷贝走。
- ❌ **"`defer f.Close()` 会处理关闭错误。"** 静默丢弃返回值。写入类资源要显式处理。
- ❌ **"defer 很慢，要避免用。"** Go 1.13 起 open-coded defer 让常见用法快了约 30%，可读性优先。

#### 一句话记住

> **defer 按 LIFO 在函数返回时执行，参数在写 defer 那一行就立即求值；循环里的 defer 会攒到函数返回（要抽成小函数或用匿名函数包起来）；只有命名返回值能被 defer 修改；`os.Exit` 会跳过所有 defer。**

📚 官方文档
- [go.dev spec · Defer statements](https://go.dev/ref/spec#Defer_statements)
- [go.dev blog · Defer, Panic, and Recover](https://go.dev/blog/defer-panic-and-recover)
- [Effective Go · defer](https://go.dev/doc/effective_go#defer)
- [go.dev doc · Go 1.13 Release Notes（defer 性能 +30%）](https://go.dev/doc/go1.13)
- [go.dev doc · Go 1.21 Release Notes（panic(nil) → PanicNilError）](https://go.dev/doc/go1.21)

---

## 第四幕 · 🔬 实操验证

> 这一幕每一步都在本机真实跑过（macOS / arm64 / go1.27.1，2026-09-06）。照着敲得到一样的输出。
> 工作目录：`/tmp/go-l04/`，模块：`example.com/l04`。

### 步骤 0：环境与工作区

```console
$ /usr/local/bin/go version
go version go1.27.1 darwin/arm64

$ mkdir -p /tmp/go-l04 && cd /tmp/go-l04
$ /usr/local/bin/go mod init example.com/l04
go: creating new go.mod: module example.com/l04
```

### 步骤 1：函数三件套 + 值传递（知识点 1）

`funcs.go`（节选核心）：

```go
func main() {
	fmt.Println("\n-- 1. 多返回值 --")
	q, r := divmod(17, 5)
	fmt.Printf("divmod(17, 5) = q=%d r=%d\n", q, r)
	if v, err := divide(10, 0); err != nil {
		fmt.Printf("divide(10, 0) err = %v (返回值 v=%g 是零值)\n", err, v)
	}
	a, p := rect(3, 4)
	fmt.Printf("rect(3,4) 命名返回值: area=%d perim=%d\n", a, p)

	fmt.Println("\n-- 4. 一切都是值传递 --")
	x := 1
	tryModifyInt(x)
	fmt.Printf("tryModifyInt(%d) 后 x=%d (不变 — int 是值拷贝)\n", 1, x)

	s := []int{1, 2, 3}
	tryModifySliceAppend(s)
	fmt.Printf("tryModifySliceAppend 后 s=%v len=%d (append 不影响调用方)\n", s, len(s))

	modifySliceElement(s)
	fmt.Printf("modifySliceElement 后 s=%v (改元素生效 — 共享底层数组)\n", s)

	m := map[string]int{"k": 1}
	modifyMap(m)
	fmt.Printf("modifyMap 后 m=%v (改 map 生效 — map 头是指针)\n", m)
}
```

**运行**：

```console
$ /usr/local/bin/go run funcs.go
===== 知识点 1：函数：多返回值与一等公民 =====

-- 1. 多返回值 --
divmod(17, 5) = q=3 r=2
divide(10, 4) = 2.5
divide(10, 0) err = 除数不能为 0 (a=10, b=0) (返回值 v=0 是零值)
rect(3,4) 命名返回值: area=12 perim=14
只要商: 3

-- 2. 变参 ...T --
sum() = 0
sum(1,2,3) = 6
sum(1,2,3,4,5) = 15
变参: 收到 3 个，类型是 []int，值 [1 2 3]
sum(ns...) = 60 (切片展开，必须加 ...)

-- 3. 函数是一等公民 --
f = add; f(3,4) = 7
f = mul; f(3,4) = 12
apply(add, 3, 4) = 7 (函数作参数)
apply(mul, 3, 4) = 12
double(7) = 14, triple(7) = 21 (闭包捕获了各自的 k)

-- 闭包计数器（状态被记住）--
c1: 1 2 3
c1 继续: 4 | 新 c2: 1 (两个计数器互不影响)

-- 4. 一切都是值传递 --
tryModifyInt(1) 后 x=1 (不变 — int 是值拷贝)
tryModifySliceAppend 后 s=[1 2 3] len=3 (append 不影响调用方)
modifySliceElement 后 s=[999 2 3] (改元素生效 — 共享底层数组)
modifyMap 后 m=map[k:999] (改 map 生效 — map 头是指针)
modifyViaPointer(&y) 后 y=999 (传指针才改得动)
```

**回扣第二幕**：值传递那五行是本节核心 —— **`append` 对调用方无效，改元素/改 map 有效**。课 3 学的"切片是描述符"在这里得到了完整解释：拷进去的是那 24 字节的描述符，不是底层数组。

### 步骤 2：错误包装链与 `==` 失效（知识点 2）

`errors.go` 的关键片段：

```go
var (
	ErrNotFound   = errors.New("记录不存在")
	ErrPermission = errors.New("权限不足")
)

func queryDB(id int) error {
	if id <= 0 {
		return ErrNotFound        // 最底层：哨兵错误
	}
	return nil
}

func getOrder(id int) error {
	if err := queryDB(id); err != nil {
		return fmt.Errorf("查询订单 %d 失败: %w", id, err)   // %w 包装
	}
	return nil
}

func handleRequest(id int) error {
	if err := getOrder(id); err != nil {
		return fmt.Errorf("处理请求失败: %w", err)           // 再包一层
	}
	return nil
}
```

**运行**：

```console
$ /usr/local/bin/go run errors.go
===== 知识点 2：error 是值 =====

-- 1. error 就是一个接口值 --
e = 记录不存在 (类型 *errors.errorString, 底层类型 <nil>)
ErrNotFound 的类型: *errors.errorString
errors.New 返回 *errors.errorString，只实现了 Error() string

-- 2. errors.New vs fmt.Errorf --
errors.New: 写死了的错误
fmt.Errorf: 带格式的错误: abc-42

-- 3. 自定义错误类型（实现 Error() string 即可）--
pe.Error() = 第 7 行解析失败: 字段数不匹配
作为 error 用: 第 7 行解析失败: 字段数不匹配

-- 4. %w 包装 + errors.Is 判断（正确姿势）--
最上层错误: 处理请求失败: 查询订单 -1 失败: 记录不存在
  errors.Is(err, ErrNotFound) = true ✅ (能穿透两层 %w 找到根因)
  errors.Is(err, ErrPermission) = false (不是这个错)

-- 5. ❌ 用 == 比较包装过的错误（经典坑）--
  err == ErrNotFound          = false ❌ (明明根因就是这个，但 == 比不出来)
  errors.Is(err, ErrNotFound) = true ✅
  原因：err 是被 fmt.Errorf("%w") 包了 2 层的 *fmt.wrapError（链上共 3 个节点：2 个壳 + 底层哨兵），
        == 比的是指针/值本身，而 errors.Is 会沿 Unwrap 链逐层剥开比对

-- 6. %v 包装会丢失链路 --
  errBad = 查询订单 -1 失败: 记录不存在
  errors.Is(errBad, ErrNotFound) = false ❌ (%v 把错误转成了字符串，链断了)

-- 7. errors.Unwrap 逐层剥开 --
  第 0 层: *fmt.wrapError → 处理请求失败: 查询订单 -1 失败: 记录不存在
  第 1 层: *fmt.wrapError → 查询订单 -1 失败: 记录不存在
  第 2 层: *errors.errorString → 记录不存在

-- 8. errors.As：取出自定义错误类型 --
  errors.As 成功: Line=7 Msg=字段数不匹配 ✅
  直接断言 wrapped.(*ParseError) 失败 ❌ (被包了一层，断言不到)

-- 9. 标准库里的真实例子：os.ErrNotExist --
  os.Open 错误: open /definitely/not/exist.txt: no such file or directory
  errors.Is(serr, os.ErrNotExist) = true ✅
  serr == os.ErrNotExist          = false ❌
  errors.As 取出 *os.PathError: Op=open Path=/definitely/not/exist.txt ✅
```

**回扣第二幕怪事二**：`== false` / `errors.Is true` 这对输出就是答案。**标准库自己也这样** —— `os.Open` 返回的错误用 `==` 比 `os.ErrNotExist` 同样是 `false`。

### 步骤 3：defer 的四个机制（知识点 3）

`defer.go` 运行：

```console
$ /usr/local/bin/go run defer.go
===== 知识点 3：defer 的机制与坑 =====

-- 1. LIFO（后进先出）--
  函数体执行中...
  第 3 个 defer（最先执行）
  第 2 个 defer
  第 1 个 defer（最后执行）

-- 2. 参数立即求值 --
  -- defer 的参数在『写 defer 那一行』就求值了 --
  函数体结束，i=999
  defer fmt.Printf(i) → i=0 （此时 i 已被改成 999，但打印的还是 0）

-- 3. 循环里的 defer --
  -- 循环里 defer，参数是立即求值的 --
  循环结束
  defer#2（LIFO 所以倒着来）
  defer#1（LIFO 所以倒着来）
  defer#0（LIFO 所以倒着来）

-- 4. defer 与命名返回值 --
  defer 里 result++ → result=2
  namedReturn()   = 2  ← 不是 1！
  defer 里 result++ → 局部 result=2（但返回值已拷贝走了）
  unnamedReturn() = 1  ← 就是 1

-- 5. defer 关资源 --
  读取 go.mod: "module example.com/l04\n\ngo 1.27.1\n" (err=<nil>)

-- 6. panic / recover --
  mayPanic: 准备 panic
  safeCall 返回: 捕获到 panic: 这是一个 panic 值 ✅ (panic 被转成普通 error 了)
  -- 直接调 recover()（不在 defer 里）--
  recover() 返回 nil —— 无效！recover 只在被 defer 的函数里才有意义

  -- panic 时 defer 仍会执行 --
  准备 panic...
  defer 2：我也执行（LIFO）
  defer 1：panic 时我依然会执行
  外层 recover 到: boom

-- 7. 闭包形式的 defer 在循环里（Go 1.22+ 行为）--
  -- 闭包形式 defer func(){...}()：捕获的是变量 --
  循环结束
  闭包 defer，i=2
  闭包 defer，i=1
  闭包 defer，i=0
```

**四个机制一次看全**：LIFO（1）、参数立即求值（2）、循环攒着（3）、命名返回值（4）。

### 步骤 4：循环 defer 的 fd 堆积对照（第三大坑）

`err_defer_pileup.go` 用一个"假文件"计数，避免真的开一万个 fd：

```console
$ /usr/local/bin/go run err_defer_pileup.go
  ❌ 错误写法：循环里 defer
    处理 a.txt（此时 fd 还开着，已开 1 个）
    处理 b.txt（此时 fd 还开着，已开 2 个）
    处理 c.txt（此时 fd 还开着，已开 3 个）
  循环结束：共开 3 个，只关了 0 个
    [关闭文件 #2]
    [关闭文件 #1]
    [关闭文件 #0]
  → processAllBad 返回后：开 3 关 3

  ✅ 正确写法：抽成小函数，defer 在每轮结束就执行
    处理 a.txt（处理完立刻关）
    [关闭文件 #0]
    处理 b.txt（处理完立刻关）
    [关闭文件 #1]
    处理 c.txt（处理完立刻关）
    [关闭文件 #2]
  → processAllGood 结束后：开 0 关 3
```

**回扣第二幕怪事三**：错误写法在整个循环里"共开 3 个，只关了 0 个"。**文件数从 3 涨到 10000，就是 10000 个 fd 同时开着。**

### 步骤 5：三个 defer 边界（os.Exit / panic(nil) / Close 错误）

```console
# 坑 A：os.Exit 跳过 defer
$ /usr/local/bin/go run err_edge_split.go exit
  准备 os.Exit(1)...
exit status 1
（"这个 defer 永远不会执行" 那行没有打印 → defer 被跳过）
```

```console
# 坑 B：panic(nil) 在 Go 1.21+ 不再是 nil
$ /usr/local/bin/go run err_edge_split.go
===== 坑 B：panic(nil) =====
  准备 panic(nil)...
  recover() 返回: runtime error: panic called with nil argument (类型 *runtime.PanicNilError)
  → r 非 nil！Go 1.21 起 panic(nil) 被自动替换为 *runtime.PanicNilError

===== 坑 C：Close 的错误 =====
  defer c.Close() —— 返回值被丢弃（编译器不报错）
  defer func(){ if err := c.Close(); ... }() —— 错误被处理
  捕获到 Close 错误: Close 失败：磁盘满了
```

```console
# 另外：未捕获的 panic 会打印完整堆栈，退出码 2
$ /usr/local/bin/go run err_panic_uncaught.go
准备触发未捕获的 panic...
panic: boom from level3

goroutine 1 [running]:
main.level3(...)
	/tmp/go-l04/err_panic_uncaught.go:7
main.level2(...)
	/tmp/go-l04/err_panic_uncaught.go:11
main.level1(...)
	/tmp/go-l04/err_panic_uncaught.go:15
main.main()
	/tmp/go-l04/err_panic_uncaught.go:20 +0x6c
exit status 2
```

---

## 第五幕 · 体系收束

### 三个怪事，三个答案

| 怪事 | 答案 | 对应知识点 |
|------|------|-----------|
| 想 `raise` 抛异常，Go 里没有 | Go **没有异常**（官方设计决定）。错误是**值**，跟着返回值一路传；`if err != nil` 的"啰嗦"换来的是**每一层都能看见错误、决定放行还是处理** | 知识点 2 |
| `==` 判不出"库存不足" | 错误被 `%w` 包装后，`==` 比的是外层包装壳。用 **`errors.Is`**（沿 Unwrap 链找）或 **`errors.As`**（取类型） | 知识点 2 |
| 循环里 `defer f.Close()` 耗尽 fd | `defer` 推迟到**函数返回**才执行，不是"用完就关"。抽成小函数或用匿名函数包起来 | 知识点 3 |

### 小谷现在站在哪

他终于明白那句"啰嗦"在替他做什么了：

- **`error` 是值** → 错误不能"甩锅"，必须在每一层被看见。写起来多三行，但**线上出问题时，错误链上每一层的上下文都在**（`处理请求失败: 查询订单 200 失败: 库存不足`）。
- **`errors.Is` 而非 `==`** → 包装是安全的，因为判断方式不依赖包装层数。
- **`defer` 是清单不是即时动作** → 关资源的正确姿势是"紧跟 Open 写 defer"，循环里则必须抽函数。

他的 `main.go` 从三百行变成了几个函数 + 一条清晰的错误链。**但他还没解决"数据怎么建模"的问题** —— 订单还是一堆散落的 `map[string]int`。

### 本课在全局的位置

```mermaid
graph LR
    A["阶段 1<br/>语言地基"] --> B["课 4<br/>函数 · error · defer"]
    B --> C["课 5<br/>struct · 方法 · 包"]
    C --> D["课 6<br/>接口 · 泛型"]
    D --> E["阶段 3<br/>并发模型"]
    E --> F["阶段 4<br/>标准库与网络"]
    F --> G["阶段 5<br/>工程化与落地"]
    style B fill:#1565C0,color:#fff
```

- **已经会的**：把逻辑拆成函数、把错误当值传递与包装、用 `defer` 管资源、说清"值传递"对切片/map 的真实含义。
- **还不会的**：怎么把"一个订单"建模成一个类型（struct）、怎么给它加行为（方法）、怎么把代码分到多个包 —— **课 5 全揽**。
- **埋下的伏笔**：
  - 本课说"任何实现了 `Error() string` 的类型都能当错误用"，但没讲**为什么不需要写 `implements`** —— **课 6「接口：隐式实现」**揭晓。
  - 本课出现 `type BinOp func(int, int) int`，这是**函数类型**；课 6 会看到**接口类型**如何承担同样的"把行为抽象出来"的职责。
  - 本课的 `recover` 只讲了基本用法 —— **课 11 的 HTTP 中间件**会给出它最正当的生产场景（防止单个请求搞崩服务）。
  - 本课说"值传递" —— **课 5「值接收者 vs 指针接收者」**会把这条规则延伸到方法上。

---

## 🐞 常见误区（本课合订）

| # | 误区 | 真相 |
|---|------|------|
| 1 | Go 支持引用传递 | **一律值传递**；切片/map 的副本仍共享底层数据 |
| 2 | 传切片进函数，`append` 外面能看到 | 不能。`append` 要返回新切片，调用方必须接收 |
| 3 | 变参 `...T` 和切片 `[]T` 是两回事 | 函数体内就是切片；区别只在调用方（传切片要加 `...`） |
| 4 | 命名返回值是好风格 | 短函数可读；**长函数是坑**（裸 return + 与 defer 的反直觉互动） |
| 5 | 闭包捕获的是值 | 捕获的是**变量**（Go 1.22 起循环里每轮新变量） |
| 6 | 用 `==` 判断错误就行 | 只对**未包装**的哨兵错误成立；包装后必须 `errors.Is` |
| 7 | `%v` 包装也能保留错误链 | **不能** —— 渲染成字符串后链路永久断裂，必须用 `%w` |
| 8 | 直接 `err.(*MyError)` 断言就够了 | 只剥一层；`errors.As` 才能穿透多层 |
| 9 | Go 有异常，只是叫 panic | `panic` 是终止信号（未 recover 时**退出码 2**，进程死），不是控制流 |
| 10 | 每个 panic 都该 recover | 错。典型用途只有：库边界转 error、HTTP 服务防崩。**滥用会掩盖真 bug** |
| 11 | `defer` 参数在执行时才求值 | **立即求值**（写 defer 那一行就定死）—— defer 第一大坑 |
| 12 | 循环里 `defer f.Close()` 每轮都关 | 不是，**攒到函数返回** → 耗尽 fd |
| 13 | defer 按注册顺序执行 | 是 **LIFO**（后注册的先执行） |
| 14 | `os.Exit` 前 defer 会执行 | **不会** —— 直接终止进程 |
| 15 | defer 里改局部变量能改返回值 | 只有**命名返回值**才行 |
| 16 | `defer f.Close()` 处理了关闭错误 | 静默丢弃返回值；写入类资源要显式处理 |
| 17 | defer 很慢要避免用 | Go 1.13 起 open-coded defer 让常见用法快约 30%，可读性优先 |

---

## 🗺️ 一图总结

```mermaid
graph TD
    subgraph 函数
      F1["多返回值 (T, error)"]
      F2["变参 ...T（体内是切片）"]
      F3["一等公民：赋值/传参/返回"]
      F4["闭包 = 函数 + 捕获变量"]
      F5["一切都是值传递"]
    end
    subgraph error 是值
      E1["error = interface{ Error() string }"]
      E2["errors.New（哨兵 ErrXxx）"]
      E3["fmt.Errorf（%v 断链 / %w 保链）"]
      E4["errors.Is 比身份 / errors.As 取类型"]
      E5["panic：不可恢复才用<br/>未 recover → 退出码 2"]
    end
    subgraph defer
      D1["LIFO 后进先出"]
      D2["参数立即求值 ← 头号坑"]
      D3["循环里攒到函数返回 ← fd 耗尽"]
      D4["命名返回值可被改"]
      D5["os.Exit 跳过所有 defer"]
    end
    F1 --> E1
    E2 --> E3
    E3 --> E4
    E3 -. "%v 会断链" .-> E4
    E1 --> E5
    E5 -. "recover 只在 defer 里有效" .-> D1
    D1 --> D2
    D2 --> D3
    D1 --> D4
    D1 --> D5
    style E3 fill:#ffe0b2,color:#333
    style E4 fill:#ffe0b2,color:#333
    style E5 fill:#ffcdd2,color:#333
    style D2 fill:#ffe0b2,color:#333
    style D3 fill:#ffcdd2,color:#333
    style D5 fill:#ffcdd2,color:#333
```

> 橙色 = 高频踩坑点；红色 = 会让程序崩溃或资源耗尽（后果最重）。

---

## 📋 速查卡

| 语法 / API | 一句话 | 坑 |
|-----------|--------|-----|
| `func f() (T, error)` | 多返回值惯用法 | **`error` 永远放最后一个**；出错返回结果零值 |
| `return 0, err` / `return v, nil` | 出/成功的标准写法 | 不能"又成功又有错" |
| `func f() (n int, err error)` | 命名返回值 | 短函数可读；**长函数是坑**（还与 defer 互动） |
| `q, _ := divmod(a, b)` | 丢弃不需要的返回值 | `_` 是丢弃，不是"省略" |
| `func sum(nums ...int) int` | 变参 | 函数体内 `nums` 就是 `[]int`；调用传切片要 `sum(ns...)` |
| `type BinOp func(int,int) int` | 函数类型 | 可赋值、传参、返回 |
| `func() int { n++; return n }` | 闭包 | 捕获的是**变量**；每次调用外层工厂都新建一份状态 |
| 传 `int` / `struct` | 值拷贝 | 改形参不影响调用方 |
| 传 `[]T` 改元素 `s[0]=v` | ✅ 调用方可见 | 共享底层数组 |
| 传 `[]T` 后 `append` | ❌ 调用方不可见 | 要 `return` 新切片，调用方接收 |
| 传 `map[K]V` 改键值 | ✅ 调用方可见 | map 头是指针 |
| 传 `*T` | ✅ 改得动 | 显式取地址 |
| `errors.New("...")` | 造哨兵错误 | 惯例：包级 `var ErrXxx = ...`，供 `errors.Is` 比较 |
| `fmt.Errorf("...%v", err)` | 加上下文但**断链** | `errors.Is` 找不到根因 |
| `fmt.Errorf("...%w", err)` | 加上下文且**保留链** | **要保留链路就用 `%w`**（Go 1.13+） |
| `errors.Is(err, ErrX)` | "是不是这个错"（穿透包装链） | **不要用 `==`** |
| `errors.As(err, &target)` | 取出链上第一个匹配类型 | 直接断言只剥一层 |
| `errors.Unwrap(err)` | 剥一层 | 循环调用可遍历整条链 |
| `panic(v)` | 不可恢复时终止 | 未 recover → 打印堆栈，**退出码 2** |
| `recover()` | 捕获 panic | **只在被 defer 的函数里有效**；直接调用返回 nil |
| `panic(nil)` | Go 1.21+ 变 `*runtime.PanicNilError` | 旧行为需 `GODEBUG=panicnil=1` |
| `defer f()` | 推迟到函数返回时执行 | **参数立即求值** |
| 多个 `defer` | 按 **LIFO** 执行 | 后注册的先执行（后申请的先释放） |
| `defer f.Close()` | 关资源标配 | **紧跟 Open 写**；返回值被静默丢弃 |
| 循环里 `defer` | ⚠️ 攒到函数返回 | **会耗尽 fd** → 抽成小函数或用匿名函数 `func(){...}()` |
| `os.Exit(n)` | 立即终止 | **跳过所有 defer** |

---

## 📝 课后小测

<details>
<summary><b>第 1 题</b>：下面这段代码输出什么？为什么？

```go
func named() (n int) {
    defer func() { n++ }()
    return 1
}

func unnamed() int {
    n := 1
    defer func() { n++ }()
    return n
}

func main() {
    fmt.Println(named(), unnamed())
}
```</summary>

输出：

```console
2 1
```

**`named()` 返回 2 而不是 1** —— 它有**命名返回值** `n`。`return 1` 实际是：①把 1 赋给 `n`；②执行 defer（`n++` → 2）；③返回 `n`。所以 defer 改的就是返回值本身。

**`unnamed()` 返回 1** —— 它的 `n` 是普通局部变量。`return n` 时返回值已被**拷贝**出来，defer 里改 `n` 影响不到那个拷贝。

**实践提示**：这个特性适合"统一改写返回值"（如把 nil 换成默认错误），**但不要在日常代码里靠它偷偷改返回值** —— 读代码的人会算错。
</details>

<details>
<summary><b>第 2 题</b>：为什么 `err == ErrNotFound` 返回 `false`，而 `errors.Is(err, ErrNotFound)` 返回 `true`？</summary>

因为 `err` 被 `fmt.Errorf("...%w", err)` **包装过了**。

- `==` 比的是**值本身**：`err` 的类型是 `*fmt.wrapError`（最外层那个包装壳），而 `ErrNotFound` 是 `*errors.errorString` —— 两个不同的对象，所以 `false`。
- `errors.Is` 会沿 `Unwrap()` 链**一层层剥开**比对：

```
第 0 层: *fmt.wrapError      → 处理请求失败: 查询订单 -1 失败: 记录不存在
第 1 层: *fmt.wrapError      → 查询订单 -1 失败: 记录不存在
第 2 层: *errors.errorString → 记录不存在   ← 在这里匹配上 ErrNotFound
```

**规则**：只要错误可能被包装（现代 Go 代码基本都会），判断就一律用 `errors.Is` / `errors.As`，**不用 `==`**。

官方 [Error Value FAQ](https://go.dev/wiki/ErrorValueFAQ) 原文建议：*"If you currently compare errors using `==`, use `errors.Is` instead."*
</details>

<details>
<summary><b>第 3 题</b>：下面这段"看起来很规范"的代码有什么问题？怎么改？

```go
func processAll(filenames []string) error {
    for _, name := range filenames {
        f, err := os.Open(name)
        if err != nil {
            return err
        }
        defer f.Close()     // 紧跟 Open，很规范？
        // ... 处理文件
    }
    return nil
}
```</summary>

**问题：`defer` 在循环里会攒到函数返回才执行。**

处理 1 个文件时没问题；处理 10000 个文件时，**10000 个 fd 会同时开着**，直到 `processAll` 返回 —— 通常在那之前就会撞上 `too many open files`。

**两种改法**：

```go
// 改法 1（推荐）：把单文件处理抽成小函数
func processOne(name string) error {
    f, err := os.Open(name)
    if err != nil {
        return err
    }
    defer f.Close()   // 属于 processOne，每次调用返回时就关
    // ... 处理
    return nil
}

func processAll(filenames []string) error {
    for _, name := range filenames {
        if err := processOne(name); err != nil {
            return err
        }
    }
    return nil
}

// 改法 2：用匿名函数把 defer 包起来并立即调用
for _, name := range filenames {
    if err := func() error {
        f, err := os.Open(name)
        if err != nil {
            return err
        }
        defer f.Close()   // 匿名函数返回时执行
        // ... 处理
        return nil
    }(); err != nil {
        return err
    }
}
```

**另一个隐患**：`defer f.Close()` 会**静默丢弃 Close 的错误**。对写入类资源，Close 可能返回"数据没真正落盘"，要严格就写成：

```go
defer func() {
    if cerr := f.Close(); cerr != nil {
        log.Printf("关闭 %s 失败: %v", name, cerr)
    }
}()
```
</details>

<details>
<summary><b>第 4 题</b>：下面代码输出什么？为什么？

```go
func main() {
    i := 0
    defer fmt.Println("defer 里的 i =", i)
    i = 999
    fmt.Println("函数体里的 i =", i)
}
```</summary>

输出：

```console
函数体里的 i = 999
defer 里的 i = 0
```

**`defer` 的参数在写 `defer` 那一行就立即求值了** —— 那一刻 `i` 是 0，所以 0 被快照下来。后面 `i` 改成 999，跟已经保存好的 defer 参数无关。

**这是 defer 第一大坑。** 如果你想要"执行时才读最新值"，用闭包形式：

```go
defer func() { fmt.Println("defer 里的 i =", i) }()   // 闭包捕获变量 → 打印 999
```

**记忆口诀**：`defer f(x)` 里的 `x` 是**拍照**，`defer func(){ ...x... }()` 里的 `x` 是**直播**。
</details>

<details>
<summary><b>第 5 题</b>：什么时候该用 `panic`，什么时候该返回 `error`？`recover` 有哪些限制？</summary>

**返回 `error`（绝大多数情况）**：

- 文件打不开、网络超时、数据库查询失败、用户输入非法 —— **任何调用方能合理处理的情况**。

**用 `panic`（极少数）**：

- 程序**逻辑上不可能**到达的分支（如一个穷尽 switch 的 `default`）；
- 启动期就发现的致命配置错误（继续跑只会更糟）；
- 数组越界、nil 解引用 —— 这些是 **bug，不是"情况"**，让程序崩掉比带着错误状态继续跑更好。

官方立场（[FAQ · Why does Go not have exceptions?](https://go.dev/doc/faq#exceptions)）：`try-catch` 会"鼓励把'打开文件失败'这类普通错误当成异常"。

**`recover` 的三条限制**：

1. **只能在被 `defer` 的函数里调用才有效** —— 直接调 `recover()` 返回 `nil`（本课实测）。
2. **它捕获的是当前 goroutine 的 panic** —— 捕获不了别的 goroutine 的 panic（课 7 展开）。
3. **它让函数"正常返回"** —— 通常配合命名返回值，把 panic 转成 `error` 返回给调用方。

**未 recover 的 panic 会让进程崩溃**，打印完整调用堆栈，**退出码 2**（本课实测）。

**`recover` 的两条正当生产用途**：①库边界把 panic 转成 error；②HTTP 服务器中间件防止单个请求搞崩整个进程（课 11）。**除此之外滥用 recover 会掩盖真正的 bug。**
</details>

---

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Go。我的学习档案在 go/00-学习档案.md，
刚学完阶段 2《组合与抽象》的课 4《函数与错误处理》
（知识点：函数：多返回值与一等公民 / error 是值 / defer 的机制与坑），
请按大纲继续讲解课 5《结构体与方法》
（知识点：struct 与组合 / 方法与接收者 / 包与可见性），
第四幕的示例代码必须在本机真实跑通并贴实测输出。
```

---

## 🧭 课程导航

- ⬅️ 上一课：[阶段 1 · 课 3 · 数组、切片与 map](../../1-语言地基/lessons/lesson-03-数组、切片与map.md)
- ➡️ 下一课：[课 5 · 结构体与方法](lesson-05-结构体与方法.md)
- 📚 返回：[课程目录](../../../02-课程目录.md) ｜ [阶段概览](../overview.md) ｜ [学习路径总览](../../../01-学习路径总览.md)