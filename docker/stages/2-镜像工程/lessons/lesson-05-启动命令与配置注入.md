# 第 5 课：启动命令与配置注入

> 所属阶段：阶段 2《镜像工程》｜ 水平：入门 ｜ 本课知识点：CMD 与 ENTRYPOINT、ENV 与 ARG、运行时配置覆盖与密钥
> 故事情节：`docker stop` 要等满 10 秒才退，改一个配置就要重新构建一次镜像

## 🎯 本课目标

- 正确使用 `CMD` 与 `ENTRYPOINT`，说清为什么 shell 形式会让 `docker stop` 等满 10 秒
- 分清 `ENV` 与 `ARG` 的生命周期差异，知道配置该放哪一层
- 掌握运行时配置的覆盖优先级，并做到**不把密钥打进镜像**

## 📌 知识点导航

| 知识点 | 关键点 | 状态 |
|--------|--------|------|
| CMD 与 ENTRYPOINT | exec 形式 vs shell 形式 / 谁是 PID 1、信号怎么传 / 两者组合的规则表 | ✅ 已完成 |
| ENV 与 ARG | ARG 只在构建期、ENV 进容器运行期 / `docker run -e` 覆盖 ENV / 密钥不能进 ENV 也不能进镜像层 | ✅ 已完成 |
| 运行时配置覆盖与密钥 | 镜像内 ENV → compose environment → `docker run -e` 的三层覆盖顺序 / env_file / 挂载配置文件覆盖 / 密钥应走 secret 或挂载而非 ENV | ✅ 已完成 |

---

## 第一幕：起源与场景引入

课 4 结束时，小杨的 `order-service` 已经构建得快、上下文也干净了。镜像推上去，服务跑起来。

然后运维找上门，一口气提了三个问题。

**问题一：`docker stop` 每次都要等满 10 秒。**

```bash
$ time docker stop order-service
order-service
real    0m10.19s          ← 每次发版都要为这一步多等 10 秒
```

**问题二：换个环境就要重新构建一次镜像。**

测试库和生产库地址不同，而他把地址写在了 Dockerfile 里。于是每换一个环境，就得改代码、重新构建、重新推送。

**问题三：数据库密码被人看见了。**

他在 Dockerfile 里写了这么一行：

```dockerfile
ENV DB_PASSWORD=hunter2
```

同事随手敲了一条 `docker history order-service`，密码就出现在了构建历史里。

> 🎬 **场景**：一个"停不下来"，一个"改不动"，一个"藏不住"。三件事分别对应本课的三个知识点。

---

## 第二幕：认知冲突

> ❓ **问题**：为什么 `docker stop` 不是"发个信号让它走"，而是要等满 10 秒？配置到底该写在 Dockerfile 里，还是别的地方？

第一个问题指向**启动命令的写法**。第二个和第三个都指向**配置注入的位置**。

先看启动命令——因为它的答案最反直觉：**同样的程序，只因为写法不同，停止行为就完全不同。**

---

## 第三幕：层层揭示

### 知识点 1：CMD 与 ENTRYPOINT

> 本知识点关键点：exec 形式 vs shell 形式 / 谁是 PID 1、信号怎么传 / 两者组合的规则表

#### 一句话定义

`CMD` 指定**容器启动时默认执行什么**；`ENTRYPOINT` 把容器**变成一个可执行程序**，此时 `CMD` 退化为它的**默认参数**。

#### 直觉建立（类比）

把容器想成一台**咖啡机**：

- `ENTRYPOINT` = 「这台设备是干嘛的」→ 咖啡机
- `CMD` = 「默认出哪一杯」→ 美式

你插上电就出一杯美式；想喝拿铁，就在后面加参数。设备本身没变，只是默认参数被覆盖了。

> 💡 **类比的边界**：咖啡机的类比到"信号"这里就断了。真实机制是**进程树**：shell 形式会给你的程序套一层 `/bin/sh -c`，让 **shell 变成 PID 1**；而 shell **不会把信号转发给子进程**。这就是为什么你的程序从头到尾不知道自己该退出了。

#### 核心原理

**两种写法**（`CMD` / `ENTRYPOINT` / `RUN` 都适用）：

```dockerfile
# exec 形式（JSON 数组，必须用双引号）
CMD ["python", "app.py"]

# shell 形式（普通字符串）
CMD python app.py
```

| | exec 形式 | shell 形式 |
|---|---|---|
| 样子 | `CMD ["python", "app.py"]` | `CMD python app.py` |
| 有没有 shell 介入 | 无，直接执行 | 有，包在 `/bin/sh -c` 里 |
| **谁是 PID 1** | **你的程序** | **shell** |
| 收得到 `docker stop` 的 SIGTERM | ✅ 直达 | ❌ shell 不转发 |
| 做不做变量替换 | ❌ 不做 | ✅ 做 |

**组合规则表**（官方给出，建议收藏）：

| | 无 ENTRYPOINT | `ENTRYPOINT exec_entry p1_entry`（shell） | `ENTRYPOINT ["exec_entry", "p1_entry"]`（exec） |
|---|---|---|---|
| **无 CMD** | ❌ 不允许，报错 | `/bin/sh -c exec_entry p1_entry` | `exec_entry p1_entry` |
| **`CMD ["exec_cmd", "p1_cmd"]`（exec）** | `exec_cmd p1_cmd` | `/bin/sh -c exec_entry p1_entry` | `exec_entry p1_entry exec_cmd p1_cmd` |
| **`CMD exec_cmd p1_cmd`（shell）** | `/bin/sh -c exec_cmd p1_cmd` | `/bin/sh -c exec_entry p1_entry` | `exec_entry p1_entry /bin/sh -c exec_cmd p1_cmd` |

> 表里最常用的其实是**右下角那一格**：`ENTRYPOINT`（exec）+ `CMD`（exec）→ CMD 的内容被**追加**成 ENTRYPOINT 的参数。这就是"把容器当成那个程序来用"的标准写法。

![exec 形式 vs shell 形式：谁是 PID 1](../assets/exec-vs-shell-form-pid1.svg)

**这张图解释了问题一**：官方自己做过这个对照实验——

- shell 形式忘了加 `exec`：`docker stop` 实测 `real 0m10.19s`（等满 10 秒宽限期后被 SIGKILL）
- 用 exec 形式：实测 `real 0m0.20s`（SIGTERM 直达，立刻退出）

官方对 shell 形式的说明原话是：它会把命令作为 `/bin/sh -c` 的子命令来启动，**"does not pass signals"**，因此你的可执行文件不是容器的 PID 1，也**收不到 `docker stop` 发来的 SIGTERM**。

**三条容易忘的补充规则**：

1. **`CMD` 只能有一个**。写多个，只有**最后一个**生效。
2. **设置 `ENTRYPOINT` 会重置 `CMD`**。官方 Note：如果 `CMD` 是从基础镜像继承来的，一旦你设了 `ENTRYPOINT`，那个 `CMD` 就被清空了——需要你在当前镜像里重新声明。
3. **`docker run` 的命令行参数覆盖 `CMD`，但保留 `ENTRYPOINT`**。想连 `ENTRYPOINT` 一起换，用 `docker run --entrypoint`（注意：它只能指定要执行的二进制，不会用 `sh -c` 包一层）。

最后别混淆这两个（官方专门提醒过）：**`RUN` 是构建时真的执行并提交结果；`CMD` 在构建时什么都不执行，只是写下一句"到时候该运行什么"。**

**如果非用 shell 形式不可，还有一招保命**：在命令开头加 `exec`。

```dockerfile
# 官方例子：既需要 shell 处理（变量替换 / 初始化），又想让目标程序当 PID 1
ENTRYPOINT exec top -b
```

`exec` 会让 shell **把自己替换成**目标程序——于是目标程序依然是 PID 1，信号照样能收到。官方的说法是：想让 `docker stop` 正确通知到一个长时间运行的 `ENTRYPOINT`，**记得用 `exec` 开头**。这个技巧在写"启动前要做点初始化"的包装脚本时特别有用。

#### 示例演示

亲手测出那个 10 秒：

```bash
# （alpine:3.20 只是示例；若该 tag 已下线，换成你本地 pull 得到的任意 alpine 版本即可）
mkdir -p stop-demo && cd stop-demo

cat > Dockerfile.shell <<'EOF'
FROM alpine:3.20
CMD sleep 600
EOF

cat > Dockerfile.exec <<'EOF'
FROM alpine:3.20
CMD ["sleep", "600"]
EOF

docker build -f Dockerfile.shell -t stop:shell .
docker build -f Dockerfile.exec  -t stop:exec  .

# ---- shell 形式 ----
docker run -d --name s1 stop:shell
time docker stop s1
# 预期：real 约 10 秒 —— 等满宽限期后被强杀
docker inspect s1 --format '退出码={{.State.ExitCode}}'
# 预期：退出码=137   ← 137 = SIGKILL（课 2 讲过）

# ---- exec 形式 ----
docker run -d --name s2 stop:exec
time docker stop s2
# 预期：real 远小于 1 秒
docker inspect s2 --format '退出码={{.State.ExitCode}}'
# 预期：退出码=143   ← 143 = SIGTERM，正常优雅退出

docker rm s1 s2
```

> 退出码 **137 vs 143**，一行命令就能判断上次容器是被"强杀"还是"优雅退出"——这是排查发布问题时很有用的一条线索。

#### 常见误区

1. **"shell 形式只是写法更省事，行为一样"** → 不一样。它让 shell 当了 PID 1，直接导致 `docker stop` 收不到优雅退出。默认请用 exec 形式。
2. **"exec 形式里能写 `$HOME` 这样的变量"** → 不能，exec 形式**不做变量替换**。要替换就用 shell 形式，或者显式写成 `CMD ["sh", "-c", "echo $HOME"]`。
3. **"ENTRYPOINT 和 CMD 选一个写就行"** → 多数情况是的；但当你想让容器"像一个命令一样被使用"（后面跟参数），`ENTRYPOINT` + `CMD` 的组合才对。

#### 一句话记住

> **默认用 exec 形式；shell 形式会让 shell 抢走 PID 1 的位置，导致 `docker stop` 等满 10 秒才被强杀。**

#### 官方文档

- [Dockerfile reference · CMD / ENTRYPOINT（Docker 官方）](https://docs.docker.com/reference/dockerfile/)——组合规则表、shell 形式不传信号的官方原话与实测、`--entrypoint` 说明

---

### 知识点 2：ENV 与 ARG

> 本知识点关键点：ARG 只在构建期、ENV 进容器运行期 / `docker run -e` 覆盖 ENV / 密钥不能进 ENV 也不能进镜像层

#### 一句话定义

`ARG` 是**构建期的变量**（镜像造完就消失，容器里读不到）；`ENV` 是**会持久化进镜像的环境变量**（容器启动后仍在，也可以被覆盖）。

#### 直觉建立（类比）

- `ARG` 像**施工图纸上的标注**：只在施工期间有用，房子交付后那些标注就不在了，住户也改不了。
- `ENV` 像**房子里装好的恒温器设置**：住户住进去还在，而且随时可以自己调。

> 💡 **类比的边界**：⚠️ 这个类比有个危险的误导——"图纸标注交付后不可见"。但 `ARG` 的值**会留在构建历史里**（`docker history` 能看到），还会写进构建产物的 provenance 证明里。所以 `ARG` 是"容器里看不见"，**不是没人看得见**。这就是为什么**绝不能用 `ARG` 传密钥**（知识点 3 展开）。

#### 核心原理

| | `ARG` | `ENV` |
|---|---|---|
| 作用范围 | 仅**构建期** | 构建期 **+ 运行期** |
| 容器里能读到吗 | ❌ 不能 | ✅ 能 |
| 怎么传值 | `docker build --build-arg K=V` | 写死在 Dockerfile，或运行时 `docker run -e` |
| 会不会持久化进镜像 | ❌ 不会 | ✅ 会 |
| `docker history` 里可见 | ⚠️ 可见 | ✅ 可见 |
| 典型用途 | 基础镜像版本、构建开关、代理地址 | 应用运行所需的默认配置 |

**一个官方点名的坑：`ENV` 总是覆盖同名的 `ARG`。**

```dockerfile
FROM ubuntu
ARG CONT_IMG_VER
ENV CONT_IMG_VER=v1.0.0
RUN echo $CONT_IMG_VER
```

```bash
docker build --build-arg CONT_IMG_VER=v2.0.1 .
```

你以为传进去的是 `v2.0.1`，但 `RUN echo` 打印的是 **`v1.0.0`**——因为 `ENV` 那行把它覆盖了。

官方给的**正确写法**是用变量展开做桥接，这样既能从命令行传值，又能持久化进镜像：

```dockerfile
FROM ubuntu
ARG CONT_IMG_VER
ENV CONT_IMG_VER=${CONT_IMG_VER:-v1.0.0}
RUN echo $CONT_IMG_VER
```

- 带 `--build-arg CONT_IMG_VER=v2.0.1` → 打印 `v2.0.1`
- 不带 → 打印默认的 `v1.0.0`

#### 示例演示

亲手证明 `ARG` 不进容器：

```bash
cat > Dockerfile <<'EOF'
FROM alpine:3.20
ARG BUILD_VERSION=1.0
ENV APP_VERSION=2.0
RUN echo "构建期看到 BUILD_VERSION=$BUILD_VERSION" > /stamp
CMD ["sh", "-c", "echo 容器里 BUILD_VERSION=[$BUILD_VERSION]; echo 容器里 APP_VERSION=[$APP_VERSION]; cat /stamp"]
EOF

docker build -t arg-demo .
docker run --rm arg-demo
# 预期输出：
#   容器里 BUILD_VERSION=[]        ← ARG 不进容器
#   容器里 APP_VERSION=[2.0]       ← ENV 进容器
#   构建期看到 BUILD_VERSION=1.0   ← ARG 构建期可见

# 传一个 --build-arg 再看
docker build --build-arg BUILD_VERSION=9.9 -t arg-demo .
docker run --rm arg-demo
# 预期：/stamp 里变成 9.9，但容器里 BUILD_VERSION 依然为空
```

#### 常见误区

1. **"`ARG` 传了值，容器里就能用"** → 不能。`ARG` 只在构建期存在，容器里读不到。要运行时可用，得用 `ENV`（或运行时 `-e`）。
2. **"`ARG` 是传密钥的安全方式"** → **恰恰相反**，这是最危险的做法之一。官方明确警告：`ARG` 的值会出现在 `docker history` 里，也会写进 `max` 模式的 provenance 证明（用 Buildx GitHub Actions 且仓库公开时默认附上）。
3. **"写了 `ENV` 还能用 `--build-arg` 覆盖它"** → 不能，`ENV` 会盖掉同名 `ARG`。要两者联动，用 `${VAR:-默认值}` 的写法。

#### 一句话记住

> **ARG 只在构建期存在且容器里读不到（但历史里看得到）；ENV 持久化进镜像且运行时可覆盖。要联动就用 `${VAR:-默认值}`。**

#### 官方文档

- [Dockerfile reference · ARG / ENV（Docker 官方）](https://docs.docker.com/reference/dockerfile/)——生命周期、`ENV` 覆盖 `ARG` 的官方示例与正确写法、`ARG` 传密钥的官方警告

---

### 知识点 3：运行时配置覆盖与密钥

> 本知识点关键点：镜像内 ENV → compose environment → `docker run -e` 的三层覆盖顺序 / env_file / 挂载配置文件覆盖 / 密钥应走 secret 或挂载而非 ENV

#### 一句话定义

配置应该**留在镜像外**，通过环境变量或挂载在**运行时注入**，这样一份镜像才能通吃所有环境；而**密钥连环境变量都不该用**，要走 secret 挂载或外部密钥管理。

#### 直觉建立（类比）

- **配置**像房间里的**家具**：换一批家具不需要重建房子。写成 `ENV DB_HOST=...` 等于把沙发钉死在地板上——换环境就得重建。
- **密钥**像**家门钥匙**：你不会把钥匙刻在大门外面。把密码写进 `ENV` 或镜像层，就等于刻在门上——因为 `docker history` 和 `docker inspect` 都能读到。

> 💡 **类比的边界**：家具换了不影响房子结构，但配置改错会让容器起不来——所以配置注入要有**默认值 + 校验**。密钥那条类比则比现实更乐观：刻在门上的钥匙你能擦掉，写进镜像层的密钥**擦不掉**（层是只读且累积的）。

#### 核心原理

**一、环境变量的覆盖优先级**（从低到高）：

```
镜像内的 ENV（Dockerfile）        ← 最低，相当于"默认值"
      ↓ 被覆盖
compose 的 environment / env_file  ← 课 9 展开
      ↓ 被覆盖
docker run -e K=V                 ← 最高，命令行说了算
```

官方对 `docker run -e` 的措辞是"set ... or **overwrite** variables defined in the Dockerfile of the image you're running"——确认了它会覆盖镜像里的 `ENV`。

**二、env_file**：把一批键值对写进文件，`--env-file` 批量注入。语法与 Dockerfile 不同，注意区分：

```bash
# env.list
# 这是注释
DB_HOST=db.internal
DB_PORT=5432
LOG_LEVEL          # 不带值 → 取宿主机同名环境变量的值
```

**三、挂载配置文件**：当配置项很多、或有嵌套结构（yaml / json / toml）时，别堆几十个 `-e`，直接挂文件进去：

```bash
docker run -v ./config/prod.yaml:/app/config.yaml:ro order-service:v2
```

> `:ro` 表示只读挂载，是个好习惯——容器不该改自己的配置。

**四、密钥的正确处理方式**（按场景分）：

| 场景 | 该怎么做 | 绝不能怎么做 |
|---|---|---|
| **构建期**需要密钥（拉私有包、连私有仓库） | `RUN --mount=type=secret` ——密钥只在构建那一步可见，**不进镜像也不进构建缓存** | ❌ `--build-arg` 传密钥 |
| **运行期**需要密钥 | 挂载密钥文件、编排器的 secret、或外部密钥管理服务 | ❌ 写进 `ENV` / `ARG` / 镜像层 |
| 本地开发图省事 | 挂载 `./.env` 文件，**并确保它被写进 `.dockerignore`** | ❌ `COPY . .` 把 `.env` 烤进镜像（课 4 讲过） |

构建期那个 `RUN --mount=type=secret` 值得展开一下，它是官方推荐的方案：

```dockerfile
# syntax=docker/dockerfile:1
FROM alpine:3.20
RUN --mount=type=secret,id=mytoken \
    sh -c 'echo "拿到 token，长度 $(wc -c < /run/secrets/mytoken) 字节"'
```

```bash
echo -n "super-secret-token" > ./token.txt
docker build --secret id=mytoken,src=./token.txt -t secret-demo .
# 预期：输出 token 的字节数

# 关键验证：镜像里查不到
docker run --rm secret-demo sh -c 'ls /run/secrets/ 2>/dev/null || echo "镜像里没有留下任何痕迹"'
# 预期：镜像里没有留下任何痕迹
docker history secret-demo    # 预期：看不到 token 的内容
```

> 它需要 BuildKit（现代 Docker 默认开启）和文件顶部的 `# syntax=docker/dockerfile:1` 解析器指令。若提示不支持 `--secret`，改用 `docker buildx build`。

**五、为什么"密钥绝不能进 ENV"**：

1. **`docker inspect` 能读到**：任何能执行 `docker inspect` 的人都能看到容器里的 `ENV`。
2. **会跟着镜像走**：写进 Dockerfile 的 `ENV` 会持久化到镜像层，**层是只读且累积的**，删不掉。
3. **会进日志与崩溃报告**：很多框架在报错时会把环境变量打印出来。
4. **`ARG` 更糟**：它还会出现在 `docker history` 与 provenance 证明里（官方警告）。

#### 示例演示

```bash
# 1) 命令行 -e 覆盖镜像里的 ENV
docker run --rm -e APP_VERSION=3.0 arg-demo
# 预期：容器里 APP_VERSION=[3.0] —— 命令行覆盖成功

# 2) -e 不带值 → 把宿主机的值透传进去
export LOG_LEVEL=debug
docker run --rm -e LOG_LEVEL alpine:3.20 sh -c 'echo $LOG_LEVEL'
# 预期：debug

# 3) 用 env_file 批量注入
printf 'DB_HOST=db.internal\nDB_PORT=5432\n' > env.list
docker run --rm --env-file env.list alpine:3.20 sh -c 'echo $DB_HOST:$DB_PORT'
# 预期：db.internal:5432

# 4) 看看密钥是怎么泄露的
docker run -d --name leaky -e DB_PASSWORD=hunter2 alpine:3.20 sleep 600
docker inspect leaky --format '{{json .Config.Env}}'
# 预期：明文看到 DB_PASSWORD=hunter2  ← 这就是"别把密钥放 ENV"的实锤
docker rm -f leaky
```

#### 常见误区

1. **"环境变量里放密钥，反正容器是隔离的"** → `docker inspect` 一眼看穿。而且密钥会跟着镜像层一起被推送到仓库。
2. **"用 `ARG` 传密钥比 `ENV` 安全"** → 更不安全，它还会出现在 `docker history` 与构建证明里（官方明确警告）。
3. **"配置就该写在 Dockerfile 里，这样最清楚"** → 那样一个镜像只能服务一个环境。正确做法是**镜像里放默认值，运行时覆盖**。

#### 一句话记住

> **配置放镜像外（镜像里只留默认值），密钥连环境变量都别用——构建期走 `--mount=type=secret`，运行期走挂载或 secret 管理。**

#### 官方文档

- [Dockerfile reference · RUN --mount=type=secret（Docker 官方）](https://docs.docker.com/reference/dockerfile/)——构建期密钥的官方推荐方案
- [docker run --env / --env-file（Docker 官方）](https://docs.docker.com/reference/cli/docker/container/run/)——`-e` 覆盖镜像 ENV、不带值时透传宿主机值、env_file 语法

---

## 第四幕：实操验证

现在把运维提的三个问题，一条条修掉。

> ⚠️ 本讲义的命令与预期输出为**纸面预期**（写作时本机 Docker 守护进程未运行）。具体数字与你实际运行会不同。

### 修复一：让 `docker stop` 从 10 秒变成 0.2 秒

```dockerfile
# ❌ 改之前
CMD python app.py

# ✅ 改之后
CMD ["python", "app.py"]
```

```bash
docker build -t order-service:v3 .
docker run -d --name os3 order-service:v3
time docker stop os3
# 预期：real 远小于 1 秒
docker inspect os3 --format '退出码={{.State.ExitCode}}'
# 预期：退出码=143（SIGTERM 优雅退出），而不是 137（被强杀）
docker rm os3
```

> ✅ **回扣场景**：问题一解决。滚动发布不再为每一步多等 10 秒，也不再有"在途请求被硬切断"的风险。

### 修复二：配置从镜像里拿出来

```dockerfile
# 镜像里只放「默认值」，运行环境负责覆盖
ENV DB_HOST=localhost
ENV DB_PORT=5432
ENV LOG_LEVEL=info
```

```bash
# 同一个镜像，跑在不同环境
docker run -d --name os-test  -e DB_HOST=test-db.internal  -e LOG_LEVEL=debug order-service:v3
docker run -d --name os-prod  -e DB_HOST=prod-db.internal  -e LOG_LEVEL=warn  order-service:v3

# 或者配置太多时，挂文件
docker run -d --name os-prod2 \
  -v ./config/prod.yaml:/app/config.yaml:ro \
  order-service:v3
```

> ✅ **回扣场景**：问题二解决。**一份镜像通吃所有环境**，换环境 = 换一组 `-e`，不再重新构建。

### 修复三：把密码从镜像里请出去

```dockerfile
# ❌ 改之前 —— 密码会永久留在镜像层里
ENV DB_PASSWORD=hunter2

# ✅ 改之后 —— 镜像里不留任何密钥，运行时注入
ENV DB_PASSWORD_FILE=/run/secrets/db_password   # 只指路径，不存值
```

```bash
docker run -d --name os-secure \
  -v ./secrets/db_password:/run/secrets/db_password:ro \
  -e DB_HOST=prod-db.internal \
  order-service:v3
```

```bash
# 自检：确认镜像里真的干净了
docker history order-service:v3 | grep -i password
# 预期：无输出

docker inspect order-service:v3 --format '{{json .Config.Env}}' | grep -i password
# 预期：只看到 DB_PASSWORD_FILE 这个「路径」，看不到任何密码值
```

> ✅ **回扣场景**：问题三解决。同事再敲 `docker history`，只剩一个路径，没有密码。

---

## 第五幕：体系收束

> 📍 **全局定位**：阶段 2 的第二课。到这儿，你的 Dockerfile 已经"能构建、构建得快、启动得对、配置得活"了。
>
> 回顾阶段 2 的三课分工：
>
> | 课 | 解决的问题 |
> |---|---|
> | 课 4 | 怎么写 Dockerfile、怎么让构建变快 |
> | **课 5** | **怎么启动、怎么注入配置、怎么不泄露密钥** |
> | 课 6 | 怎么把镜像瘦下来 |
>
> 还有一个遗留问题没解决：**镜像里仍然带着编译器、包管理器缓存和一堆构建期依赖**。

> 🔗 **下一步**：课 6《多阶段构建与镜像瘦身》——用多阶段构建只把运行时产物拷进最终镜像，顺带解决基础镜像选型（alpine / slim / distroless 怎么选）与"为什么删了文件镜像没变小"（课 3 埋的伏笔）这两件事。

---

## 🐞 常见误区

1. **"shell 形式和 exec 形式只是写法风格不同"** → 不是。它决定了**谁是 PID 1**，进而决定 `docker stop` 是 0.2 秒还是 10.19 秒，退出码是 143 还是 137。

2. **"`ARG` 传进来的值容器里能用"** → 不能。`ARG` 只在构建期存在。要运行时可用得用 `ENV` 或 `-e`。

3. **"`ARG` 是传密钥的隐蔽通道"** → 是最显眼的通道之一：它会写进 `docker history` 和构建证明。**构建期密钥请用 `RUN --mount=type=secret`。**

4. **"把配置写进 Dockerfile 最清楚"** → 那样一个镜像只能服务一个环境，而且改配置要重新构建。正确做法是镜像里只放**默认值**，运行时覆盖。

---

## 一图总结

```mermaid
graph TD
    A["容器启动：谁来当 PID 1？"] --> B{"用哪种写法？"}
    B -->|"shell 形式<br/>CMD python app.py"| C["PID 1 = /bin/sh -c<br/>你的程序是子进程"]
    B -->|"exec 形式<br/>CMD [\"python\", \"app.py\"]"| D["PID 1 = 你的程序"]

    C --> E["docker stop → SIGTERM 送给 shell<br/>❌ shell 不转发<br/>→ 等满 10 秒 → SIGKILL<br/>退出码 137"]
    D --> F["docker stop → SIGTERM 直达<br/>✅ 立即优雅退出<br/>退出码 143"]

    G["配置该放哪？"] --> H{"构建期还是运行期？"}
    H -->|"构建期"| I["ARG<br/>⚠️ 容器里读不到<br/>⚠️ docker history 可见 → 别放密钥"]
    H -->|"运行期"| J["ENV：持久化进镜像<br/>docker run -e：覆盖它"]

    J --> K["覆盖优先级（低 → 高）<br/>镜像 ENV ＜ compose environment/env_file ＜ docker run -e"]

    L["密钥该放哪？"] --> M["构建期 → RUN --mount=type=secret<br/>运行期 → 挂载文件 / 编排器 secret / 外部管理"]
    L --> N["❌ 绝不：ENV / ARG / 镜像层<br/>理由：inspect 与 history 都能读到，且层删不掉"]
```

---

## 📋 命令速查卡

| 命令 | 作用 | 本课出现在哪 |
|------|------|------------|
| `docker stop <容器>` | 发 SIGTERM → 等宽限期 → SIGKILL（默认 10 秒） | 知识点 1 / 修复一 |
| `docker stop -t <秒> <容器>` | 自定义宽限期 | 知识点 1 |
| `docker inspect --format '{{.State.ExitCode}}' <容器>` | **看退出码判死因**：143=优雅退出、137=被强杀 | 知识点 1 / 修复一 |
| `docker build --build-arg K=V .` | 给 `ARG` 传值（**不能用来传密钥**） | 知识点 2 |
| `docker run -e K=V <镜像>` | 注入环境变量，**覆盖镜像里的 `ENV`** | 知识点 3 / 修复二 |
| `docker run -e K <镜像>` | 不带值 → 透传宿主机同名环境变量的值 | 知识点 3 |
| `docker run --env-file <文件> <镜像>` | 从文件批量注入 | 知识点 3 |
| `docker run --entrypoint <命令> <镜像>` | 覆盖镜像的 ENTRYPOINT（只能指定二进制，不用 `sh -c`） | 知识点 1 |
| `docker build --secret id=<id>,src=<文件> .` | 配合 `RUN --mount=type=secret` 传构建期密钥 | 知识点 3 |
| `docker history <镜像>` | 看构建步骤——**也是检查密钥有无泄露的第一道关** | 知识点 2 / 修复三 |

---

## 课后小测

**Q1**：`docker stop` 每次要等满 10 秒才停，最可能的原因是？

- A. 容器里的程序有 bug，卡死了
- B. 用了 shell 形式，导致 `/bin/sh -c` 成了 PID 1，而 shell 不把 SIGTERM 转发给子进程
- C. `docker stop` 的默认宽限期就是 10 秒，跟写法无关
- D. 宿主机负载太高

<details><summary>答案与解析</summary>

**答案：B**。官方对 shell 形式的原话是它 "does not pass signals"，你的程序不是 PID 1 因此收不到 `docker stop` 的 SIGTERM，只能等宽限期到后被 SIGKILL。C 是半对——默认宽限期确实是 10 秒（Linux），但**正常情况下根本用不到**：exec 形式下官方实测 `docker stop` 只花 0.20 秒。判断依据：看退出码，**137 = 被强杀，143 = 优雅退出**。

</details>

**Q2**：关于 `ARG` 与 `ENV`，下列说法正确的是？

- A. `ARG` 传的值在容器运行时也能读到
- B. `ENV` 的值不会持久化进镜像
- C. `ARG` 只在构建期有效、容器里读不到；`ENV` 会持久化进镜像且可被 `docker run -e` 覆盖
- D. `ARG` 是传密钥的推荐方式，因为它不会进镜像

<details><summary>答案与解析</summary>

**答案：C**。A 错——`ARG` 不进容器。B 错——`ENV` 恰恰是会持久化的那个。D 错得最离谱：官方**明确警告**不要用 `ARG` 传密钥，因为它的值会出现在 `docker history` 和构建证明里；构建期密钥应该用 `RUN --mount=type=secret`。

</details>

**Q3**：环境变量的覆盖优先级，从低到高正确的是？

- A. `docker run -e` ＜ compose environment ＜ 镜像 ENV
- B. 镜像 ENV ＜ compose environment/env_file ＜ `docker run -e`
- C. 三者互不影响，各管各的
- D. 谁在 Dockerfile 里写在后面，谁优先

<details><summary>答案与解析</summary>

**答案：B**。官方对 `docker run -e` 的措辞是 "overwrite variables defined in the Dockerfile"——确认它覆盖镜像 `ENV`；而 compose 的 `environment` 也覆盖镜像默认值，自己又被命令行 `-e` 覆盖。这套优先级正是"一份镜像通吃多环境"的基础：镜像里只放默认值，具体值由运行环境给。

</details>

---

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一批（无需重新描述上下文）：

```
继续学 Docker。我的学习档案在 docker/00-学习档案.md，
刚学完阶段 2《镜像工程》的课《启动命令与配置注入》知识点 CMD 与 ENTRYPOINT、ENV 与 ARG、运行时配置覆盖与密钥，
请按大纲继续讲解下一批知识点。
```

## 🧭 课程导航

⬅️ **上一课**：[课 4：Dockerfile入门](lesson-04-Dockerfile入门.md)

➡️ **下一课**：[课 6：多阶段构建与镜像瘦身](lesson-06-多阶段构建与镜像瘦身.md)

📚 **返回目录**：[课程目录](../../../02-课程目录.md)
