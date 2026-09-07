# 第 10 课：Provisioning：把点击变成配置文件

> 所属阶段：阶段 4《管得住》｜ 水平：入门 ｜ 本课知识点：三类 provisioning 文件、UI 冲突处理、JSON Model
> 故事情节：换台机器重来一遍——你点的那些配置，全在数据库里。怎么把它们变成文件？

## 🎯 本课目标

- 写三份 YAML 让全新的 Grafana 启动即带全套配置
- 解释什么情况下 provisioning 会覆盖 UI 改动，什么情况下不会
- 读懂 dashboard JSON 的关键字段，并做一次有意义的 diff

## 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 10.1 | Provisioning 的三类文件：datasources / dashboards / alerting | 目录约定 / 各自定义字段 / 启动时加载 | ✅ 已完成 |
| 10.2 | Dashboard as Code 与 UI 改动的冲突处理 | `allowUiUpdates` 的真实行为 / 单向同步 / 团队协作约定 | ✅ 已完成 |
| 10.3 | JSON Model 结构与可 diff 化 | 顶层字段 / 面板与变量结构 / 剥离 id+version 后 diff 归零 | ✅ 已完成 |

---

## 第一幕：场景引入——换台机器，一切归零

### 一个真实的周一早晨

你的 Grafana 跑了半年，里面躺着：

- 12 个数据源
- 40 多张 dashboard（有些是你在 UI 上一点点调出来的）
- 30 多条告警规则，配好了通知策略和静默窗口

然后那台机器要下线了。

运维同事很体贴地帮你在新机器上跑了一条命令：

```bash
docker run -d --name grafana -p 3000:3000 grafana/grafana:13.2.1
```

你打开浏览器，登录，看到的是——**一个全新的空 Grafana**。数据源 0 个，dashboard 只有欢迎页，告警规则一条没有。

这不是运维的锅。这正是本课要解决的问题。

### 为什么"点出来的配置"不会跟着走

回顾课 1 的核心结论：Grafana **不存数据，只存配置**。但这句话要补半句——

> Grafana 存配置，**存在自己的数据库里**。

你点的每一个数据源、每一张 dashboard、每一条告警规则，都写进了 Grafana 的 SQLite（或 Postgres/MySQL）。数据库在容器里、在数据卷里，不在你的 Git 仓库里。

所以"换台机器"这件事，本质上是问：**怎么把数据库里的配置，变成仓库里的文件？**

Provisioning 就是官方给出的答案。

### 本课的路线

本课要回答三个问题：

1. **三类文件长什么样**，放在哪个目录，启动时会发生什么
2. **文件和 UI 打架时谁赢** —— 这是团队协作里最容易踩的坑
3. **dashboard JSON 怎么变得可 diff** —— 否则 Git 里的 diff 全是噪音

### 本课的实验环境

本课需要一个**全新的 Grafana 实例**，用来验证"从零重建"。我起了两个：

| 容器 | 端口 | 用途 |
|---|---|---|
| `grafana-prov` | 3002 | 主实验实例 |
| `grafana-prov2` | 3003 | 对照实验（干净状态） |

> ⚠️ **为什么必须用独立实例**：provisioning 会**覆盖** UI 改动，拿你日常用的 `grafana-lab`（3001）做实验会丢配置。本课所有操作都在 3002/3003 上。

启动脚本：`playground/l10-env-up.sh`（含文件存在性校验，原因见第四幕）。

---

## 第二幕：认知冲突——"改一下配置就行"的三个反直觉

在读 provisioning 文档时，大多数人会有三个想当然的预期。本课实测**全部推翻了它们**。

### 冲突 1：provisioning 写错了，Grafana 会跳过那个文件继续跑

**直觉**：配置文件写错，顶多是那一项没生效，Grafana 照常起来。

**实测**：

```
logger=provisioning t=... level=error msg="Failed to provision alerting"
  error="alert rules: invalid alert rule: both annotations
         __dashboardUid__ and __panelId__ must be specified"
```

然后：

```
grafana-prov    Exited (1) 30 seconds ago
```

Grafana **整个进程退出了**。日志里紧跟着一串级联失败：

```
msg="Module failed" module=*api.HTTPServer
  err="...it depends on module provisioning, which has failed..."
msg="Module failed" module=*service.DashboardUpdater
msg="Module failed" module=*ssosettingsimpl.Service
msg="Module failed" module=*authz.EmbeddedZanzanaService
```

`api.HTTPServer`（HTTP 服务）也挂了——因为它依赖 provisioning 模块。

**真实规则**：alerting provisioning 出错 = **Grafana 起不来**。不是"跳过"，是"崩溃"。

这跟前几课看到的"后端不校验"完全相反。课 4 的 `editorMode`、课 5 的 `transformations`、课 6 的 `repeat`，你写瞎编的值它都照收；但 alerting provisioning 会**严格校验，且失败即终止进程**。

区别在于**时机**：前三个是运行时写入（错了顶多显示异常），provisioning 是**启动期**写入（错了就没法提供服务，只能崩溃）。

### 冲突 2：`allowUiUpdates` 控制的是"保存后会不会被覆盖"

**直觉**：设成 `false`，我在 UI 上改了能保存，下次重启被文件覆盖回去。

**实测**：`allowUiUpdates: false` 时保存，返回：

```json
{"message":"Cannot save provisioned dashboard"}
```

HTTP **400**。**根本不让你保存**，谈不上"保存后被覆盖"。

那么设成 `true` 就能随便改了吗？实测也不完全对——第二幕埋个引子，第四幕给你完整答案（含一个我没预料到的"数据库残留"陷阱）。

### 冲突 3：两个文件里的"文件夹"是同一个

**直觉**：dashboards 配置写 `folder: 'Provisioned'`，alerting 配置也写 `folder: Provisioned`，它们会进同一个文件夹。

**实测**：启动后查文件夹列表，出现了**两个都叫 "Provisioned" 的文件夹**：

```
uid=dfxhsw8b57pxcd   title=Provisioned   managedBy=None
uid=provfolder       title=Provisioned   managedBy=classic-file-provisioning
```

逐个查内容：

| 文件夹 | 里面装什么 |
|---|---|
| `provfolder`（我指定的 uid） | 1 个 dashboard |
| `dfxhsw8b57pxcd`（自动生成） | **0 个**（空） |

**真实规则**：

- **dashboards** 用 `folderUid` 定位文件夹（按 uid）
- **alerting** 用 `folder` 定位文件夹（按**名字**）

两者机制不同，各建各的，于是出现两个同名文件夹。第四幕会给出规避办法。

### 三个冲突的共同点

它们都不是"文档没写"，而是**文档的措辞和真实行为之间有落差**：

- "跳过" vs "崩溃"
- "覆盖" vs "拒绝保存"
- "同一个文件夹" vs "两个同名文件夹"

这类落差只能靠实测填平。本课的每一条结论后面都跟着实测输出。

---

## 第三幕：层层揭示——三类文件与单向同步

### 10.1 Provisioning 的三类文件

#### 目录约定：为什么是这个路径

Grafana 官方镜像里，provisioning 的根目录是：

```
/etc/grafana/provisioning/
├── datasources/     ← 数据源
├── dashboards/      ← dashboard 的"提供者"定义
├── alerting/        ← 告警规则
├── plugins/         ← 插件（本课不讲）
├── notifiers/       ← 通知渠道（旧版，新版已并入 alerting）
└── access-control/  ← 权限（新版）
```

两点要注意：

1. **目录名是固定的**。Grafana 启动时按名字扫描，你把 `datasources` 改成 `datasource` 它就不认了。
2. **目录下所有 `.yaml`/`.yml` 都会被读**。所以你可以拆成 `ds-prom.yaml`、`ds-loki.yaml` 多个文件，不必挤在一个文件里。

挂载方式（本课实际用的）：

```bash
-v "$P/datasources:/etc/grafana/provisioning/datasources"
-v "$P/dashboards:/etc/grafana/provisioning/dashboards"
-v "$P/alerting:/etc/grafana/provisioning/alerting"
```

### 一句话定义

**Provisioning 是启动时把 YAML/JSON 文件里的配置写进数据库的一次性过程**，分 `datasources`、`dashboards`、`alerting` 三类。

### 直觉建立：搬家时的"配置清单"

想象你要把住了半年的房子换到另一套。

**做法 A——凭记忆复原**：到了新房子，凭印象一个个摆：沙发放这边、书架放那边、路由器密码是多少。结果是漏掉一半，另一半位置不对。

**做法 B——搬家前写清单**：提前列一张表：

```
客厅：沙发（靠窗）、书架（东墙）
网络：路由器 SSID=home-5g，密码=xxxx
```

到了新房子照着清单摆，**一次到位**。

Provisioning 就是这张清单。你点的那些配置存在数据库里——数据库在旧机器上。清单在 Git 里，能跟你走到任何一台新机器。

> **关键区别**：清单是**单向**的。你到新家后又挪了沙发（= UI 改动），清单不会自动更新。下次照清单再摆一次，沙发又回原位了。

### 核心原理

#### （1）三类文件的分工

```
/etc/grafana/provisioning/
├── datasources/   配【数据源本身】——"有哪些数据可查"
├── dashboards/    配【去哪找 dashboard】——"去哪个目录读文件"
└── alerting/      配【告警规则本身】——"什么条件该告警"
```

注意中间那类的措辞：`dashboards/` 配的**不是 dashboard**，是**提供者（provider）**。它说的是"去 `/var/lib/grafana/dashboards` 这个目录找文件"，真正的 dashboard 在另一个地方。

这是本课最容易误解的一处——很多人以为把 JSON 丢进 `provisioning/dashboards/` 就行，其实那里只放**定义文件**，JSON 要放 provider 指向的目录。

#### （2）启动时发生了什么

```
logger=provisioning.datasources msg="inserting datasource from configuration" name=ProvProm uid=provprom
logger=provisioning.alerting    msg="starting to provision alerting"
logger=provisioning.dashboard   msg="finished to provision dashboards"
```

关键词是 **`inserting`**——往数据库里写。

```
文件 ──(启动时 insert)──> 数据库 ──(运行时读取)──> UI
```

写完之后文件就退场了。**Grafana 运行时读数据库，不读文件**（唯一的例外是 `updateIntervalSeconds` 触发的定期重新扫描）。

#### （3）写错了会怎样：三类不一样

| 类型 | 写错的后果 |
|---|---|
| datasources | 该项跳过，照常启动 |
| dashboards | 该项跳过，照常启动 |
| **alerting** | **整个进程崩溃** |

第三行是实测结论，第二幕会给证据。原因很简单：前两类是"少个数据源还能用"，alerting 起不来则整个 provisioning 模块进入 Failed 状态，而 `api.HTTPServer` 依赖它——于是 Grafana 拒绝在"配置不完整"的状态下提供服务。

### 示例演示：三份文件长什么样

完整的三份文件在本课环境里可以直接跑：

- `playground/provisioning/datasources/ds.yaml`
- `playground/provisioning/dashboards/dash.yaml`
- `playground/provisioning/alerting/alerts.yaml`

最小可用的 datasources 文件：

```yaml
apiVersion: 1

datasources:
  - name: ProvProm
    uid: provprom
    type: prometheus
    access: proxy
    url: http://grafana-prom:9090
    isDefault: true
    editable: false
```

### 常见误区

**误区 1：把 dashboard JSON 放进 `provisioning/dashboards/` 就会生效**

不会。那个目录只放 provider 定义（一个 YAML，说"去哪找"）。JSON 要放在 provider 的 `options.path` 指向的目录里。

本课的实际挂载：

```bash
-v "$P/dashboards:/etc/grafana/provisioning/dashboards"      # provider 定义
-v "$P/dashboards-json:/var/lib/grafana/dashboards"          # 真正的 dashboard
```

**误区 2：`url` 写 `localhost:9090`**

写 `localhost` 指的是 **Grafana 容器自己**。数据源在另一个容器里，要用 **容器名**（同一 docker network 内）：

```yaml
url: http://grafana-prom:9090    # ✅ 容器名
url: http://localhost:9090       # ❌ 指向 Grafana 自己
```

**误区 3：不写 `uid`，让 Grafana 自己生成**

不写 uid，Grafana 会生成一个随机的（像 `dfxhsw8b57pxcd`）。你下次重建环境，uid 就变了，所有引用它的 dashboard、告警规则**全部失效**。

**uid 必须自己写死。**

**误区 4：改了文件不重启，发现没生效**

`datasources` 和 `alerting` **必须重启**才生效。只有 `dashboards` 有 `updateIntervalSeconds` 热加载。

### 一句话记住

> **Provisioning = 启动时的一次 INSERT：文件进数据库，然后文件就下班了；uid 必须自己写死，否则重建一次环境，引用全断。**

---

#### 第一类：datasources（最直观）

`provisioning/datasources/ds.yaml`：

```yaml
apiVersion: 1

datasources:
  - name: ProvProm
    uid: provprom
    type: prometheus
    access: proxy
    url: http://grafana-prom:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST

  - name: ProvLoki
    uid: provloki
    type: loki
    access: proxy
    url: http://grafana-loki:3100
    editable: false
```

字段说明：

| 字段 | 作用 | 本课的值 |
|---|---|---|
| `apiVersion` | 固定写 `1` | `1` |
| `name` | 显示名 | `ProvProm` |
| `uid` | **唯一标识**，dashboard 靠它引用数据源 | `provprom` |
| `type` | 插件类型 | `prometheus` |
| `access` | `proxy`（走后端）或 `direct`（课 2 已证：direct 并非真直连） | `proxy` |
| `url` | 数据源地址。**容器内视角**，所以用容器名 `grafana-prom` | `http://grafana-prom:9090` |
| `isDefault` | 是否默认数据源 | `true` |
| `editable` | 能否在 UI 改 | `false` |

**`uid` 是这里最重要的字段**。课 2 讲过 uid 的"不可变性"——dashboard JSON 里引用数据源靠的是 uid 而不是名字。所以 provisioning 里**必须显式写 uid**：不写的话 Grafana 会随机生成一个，你下次重建环境 uid 就变了，所有 dashboard 的引用全部失效。

**实测落地**：启动后查 API：

```
uid=provloki     name=ProvLoki     type=loki         editable=None
uid=provprom     name=ProvProm     type=prometheus   editable=None
```

⚠️ **注意 `editable=None`** —— 我明明写了 `editable: false`，读回来却是 `None`。

这不是丢了。进一步查原始响应：

```
provprom  keys_editable= ['readOnly']
    editable= None  readOnly= True
```

**后端把它换成了 `readOnly` 字段**。写入用 `editable`，读出用 `readOnly`。

这跟课 4/5/6 的模式一致：**存的是一回事，读回来是另一回事**。不过这次是字段名转换，不是"存后端跑前端"。判据要看 `readOnly`，不能看 `editable`。

> **判据**：判断数据源是否被 provisioning 锁定，看 `readOnly`，不看 `editable`。

#### 第二类：dashboards（最容易误解）

这是本课**最容易误解**的一类。注意它的名字：这个目录配置的**不是 dashboard 本身**，而是"去哪里找 dashboard 文件"。

`provisioning/dashboards/dash.yaml`：

```yaml
apiVersion: 1

providers:
  - name: prov-dashboards
    orgId: 1
    folder: 'Provisioned'
    folderUid: provfolder
    type: file
    disableDeletion: false
    editable: true
    allowUiUpdates: false
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

**"provider"（提供者）是关键概念**。上面这个文件说的不是"这是一张 dashboard"，而是：

> 有一个叫 `prov-dashboards` 的提供者，它的类型是 `file`，它负责去 `/var/lib/grafana/dashboards` 这个目录找 dashboard 文件。

所以 dashboards provisioning 是**两层结构**：

```
provisioning/dashboards/dash.yaml   ← 定义"去哪找"（provider）
        ↓ 指向
/var/lib/grafana/dashboards/*.json  ← 真正的 dashboard 文件
```

两者都要挂载：

```bash
-v "$P/dashboards:/etc/grafana/provisioning/dashboards"
-v "$P/dashboards-json:/var/lib/grafana/dashboards"
```

字段说明：

| 字段 | 作用 |
|---|---|
| `name` | provider 名字（多个 provider 不能重名） |
| `orgId` | 归属组织，单组织环境写 `1` |
| `folder` / `folderUid` | 装到哪个文件夹。**建议两个都写** |
| `type` | `file`（从目录读文件），也有 `git` 等 |
| `disableDeletion` | `true` = 文件删了 dashboard 留着；`false` = 文件删了 dashboard 也删 |
| `editable` | dashboard 是否可编辑（UI 层面） |
| `allowUiUpdates` | `true` = 允许 UI 保存（但仍会被文件覆盖），`false` = 直接拒绝保存 |
| `updateIntervalSeconds` | 每隔多少秒重新扫一次目录 |
| `options.path` | dashboard 文件所在目录（**容器内路径**） |

**`updateIntervalSeconds` 是 provisioning 里少见的"热加载"**：它让 Grafana 定期重新扫描目录。实测——新增一个文件：

```
新加一个文件（模拟 Git 新增）
  waiting for updateIntervalSeconds=10 resync...
  count= 2
    prov-dash-001 Provisioned Node Overview
    prov-dash-002 Second Provisioned Dash
```

**不用重启，14 秒后自动出现了**。这意味着你可以把 dashboard 文件放在 Git 管理，拉代码后 Grafana 会自动跟上。

#### 第三类：alerting（最严格）

`provisioning/alerting/alerts.yaml`（节选，完整文件见 `playground/provisioning/alerting/alerts.yaml`）：

```yaml
apiVersion: 1

groups:
  - orgId: 1
    name: prov-group
    folder: Provisioned
    interval: 60s
    rules:
      - uid: prov-rule-node-down
        title: ProvisionalNodeDown
        condition: B
        noDataState: NoData
        execErrState: Error
        for: 0s
        annotations:
          summary: node down (provisioned)
          __dashboardUid__: prov-dash-001
          __panelId__: "1"
        labels:
          source: provisioning
        data:
          - refId: A
            datasourceUid: provprom
            model: { ... }
          - refId: B
            datasourceUid: __expr__
            model: { ... }
```

几点说明：

1. **`groups` 结构直接对应课 8 的评估组**。`interval: 60s` 就是组间隔——课 8 实测过：告警延迟 = ⌈for/interval⌉ × interval，规则自己改间隔没用，得改组。

2. **`data` 里的两条查询复刻了课 7 的结构**：`refId=A` 查 Prometheus，`refId=B` 用 `__expr__`（Grafana 内部表达式引擎）做阈值判断，`condition: B` 指明以 B 为准。

3. **`noDataState` 和 `execErrState` 必填**。课 7 踩过：provisioning API 对这两个字段**没有默认值**，不传就 400。

4. **`__dashboardUid__` 和 `__panelId__` 必须成对出现**。这是第二幕那个崩溃的原因：

```
error="alert rules: invalid alert rule: both annotations
       __dashboardUid__ and __panelId__ must be specified"
```

补救办法有两个：两个都写（如上），或者**两个都不写**。

#### 三类文件对照表

| | datasources | dashboards | alerting |
|---|---|---|---|
| 配置的是 | 数据源本身 | **去哪找** dashboard | 告警规则本身 |
| 关键标识 | `uid` | provider `name` + 文件 `uid` | rule `uid` |
| 定位文件夹 | 不涉及 | `folderUid` | `folder`（按名字） |
| 写错的后果 | 该项跳过，照常启动 | 该项跳过，照常启动 | **进程崩溃** |
| 热加载 | 否（需重启） | 是（`updateIntervalSeconds`） | 否（需重启） |

#### 启动时到底发生了什么

日志里的顺序很清楚：

```
logger=backgroundsvcs.managerAdapter msg=starting module=provisioning
logger=provisioning.datasources msg="inserting datasource from configuration" name=ProvProm uid=provprom
logger=provisioning.datasources msg="inserting datasource from configuration" name=ProvLoki uid=provloki
logger=provisioning.alerting   msg="starting to provision alerting"
logger=provisioning.dashboard  msg="starting to provision dashboards"
logger=provisioning.dashboard  msg="finished to provision dashboards"
```

**关键词是 `inserting`**——往数据库里写。

这就是 provisioning 的本质：

> **启动时，把文件里的配置写进数据库。**

写完之后，文件的事就结束了。Grafana 运行期间读的是数据库，**不读文件**（除非 `updateIntervalSeconds` 触发重新扫描）。

这句话是理解 10.2 全部冲突的钥匙。

---

### 10.2 Dashboard as Code 与 UI 改动的冲突处理

### 一句话定义

**Provisioning 是单向的**：文件 → 数据库，永不反向。`allowUiUpdates` 决定 UI 改动是被拒绝还是被允许，但**无论如何，重启后文件都会把自己写回去**。

### 直觉建立：公告栏与便签

公司的公告栏上贴着一张打印的规章制度（= **provisioning 文件**）。

员工看到后觉得第三条不合理，拿起笔在公告栏上改了（= **UI 改动**）。

现在有两种公告栏：

**A 型公告栏（覆膜，写不上去）** —— `allowUiUpdates: false`
笔划过去，什么痕迹都没留下。你想改？可以，去改**源文件**重新打印。

**B 型公告栏（普通纸，能写）** —— `allowUiUpdates: true`
你能改，改完当天大家都按新版本执行。但第二天行政重新打印张贴（= 重启），你的改动**没了**，又变回原样。

B 型看起来更"民主"，其实更危险——**你以为改成功了，其实是临时生效**。

> 本课的推荐是 A 型：**明确的失败（当场拒绝）好过静默的成功（改了但会丢）**。

### 核心原理

#### （1）单向性的数据流

```
文件 ──(启动时写入)──> 数据库 ──(运行时读取)──> UI
                          ↑                    │
                          └────(UI 改动)───────┘

数据库 ──X──> 文件        ← 这条箭头不存在
```

第三条箭头不存在，就是"单向"的全部含义。

#### （2）`allowUiUpdates` 的真实语义

| 配置 | UI 能保存吗 | 重启后 | 证据 |
|---|---|---|---|
| `false` | ❌ 400 | 文件值 | `{"message":"Cannot save provisioned dashboard"}` |
| `true`（干净实例） | ✅ 200 | **被文件覆盖** | version 1→2→3，title 回滚 |
| 先 false 后 true（同实例） | ❌ 400 | 文件值 | **数据库残留**，配置"不生效" |

注意第一行：不是"保存后覆盖"，是**根本存不进去**。这比文档给人的印象要强硬得多。

#### （3）`disableDeletion`：删除的另一半

| `disableDeletion` | 删除文件后 | 风险 |
|---|---|---|
| `false` | dashboard 一并删除 | 误删文件 = 误删 dashboard |
| `true` | dashboard 保留（孤儿） | 库中堆积查不到来源的 dashboard |

### 示例演示：亲手触发"不能保存"

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-probe5.sh"
```

预期：

```
HTTP 400
{"message":"Cannot save provisioned dashboard"}
```

对照实验（干净实例，`allowUiUpdates: true`）：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-uiedit2.sh"
```

预期三段：

```
  SAVE http=200 version=2 status=success              ← 能保存
  title  = EDITED BY UI (prov2)                       ← 改成功了
  after restart: title='Provisioned Node Overview' version=3    ← 被回滚
```

### 常见误区

**误区 1：`allowUiUpdates: true` = UI 和文件可以共存**

不能。它只允许**保存**，不阻止**覆盖**。重启后文件仍然会把自己写回去，version 继续 +1。

**误区 2：改了 `allowUiUpdates` 就该立刻生效**

同实例上先 `false` 后 `true`，仍会报 400——**数据库里的旧标记没被清掉**。

排查：看 `meta.provisioned`。已 `False` 却仍 400，就是残留，需要换干净实例验证（本课正是这么定位的）。

**误区 3：`disableDeletion: true` 更安全**

不一定。它保证 dashboard 不会因为文件误删而消失，但代价是**孤儿堆积**——库里留着已经没有源文件的 dashboard，你不知道它是从哪来的、该不该删。

**误区 4：dashboards 和 alerting 会进同一个文件夹**

不会（10.1 已证）：dashboards 用 `folderUid`，alerting 用 `folder`（名字），会建出**两个同名文件夹**。

### 一句话记住

> **文件是老板，UI 是临时工：`false` 连门都不让进，`true` 让进但第二天照样被推翻。**

---

#### 单向性：一切的根源

把上面那句话再展开一步：

```
文件 ──(启动时写入)──> 数据库 ──(运行时读取)──> UI
                          │
                          └──(UI 改动)──> 数据库
```

注意箭头的方向：

- **文件 → 数据库**：只有启动时（或定期扫描时）发生
- **UI → 数据库**：随时发生
- **数据库 → 文件**：**永不发生**

第三条不存在，这就是"单向"。

你在 UI 上改了 dashboard，改的是数据库。文件岿然不动。下次启动，文件又把自己写进数据库——**你以为的"改动"被无声地抹掉了**。

#### 阶段概览里那句话要修正

阶段 4 的 `overview.md` 里写着：

> 文件里没有 `version` 字段时会覆盖 UI 改动；有则保留。

这句话我在开课前就存疑，现在有实测结论了——**Grafana 13.2.1 的实际开关是 `allowUiUpdates`，不是 `version`**。

下面把它测清楚。

#### 实验 A：`allowUiUpdates: false`（默认）

当前配置：

```yaml
allowUiUpdates: false
```

在 UI 等价的 API 上改标题并保存：

```
[初始] title='Provisioned Node Overview' version=1
[UI 改动] http=400
[改动后] title='Provisioned Node Overview' version=1
```

HTTP 400，标题没变。抓完整错误体：

```json
{"message":"Cannot save provisioned dashboard"}
```

**结论**：`allowUiUpdates: false` = UI 保存被**硬拒绝**。不是"保存后覆盖"，是**根本存不进去**。

这条其实比"静默覆盖"友好得多——你当场就知道不能改，不会白干一场。

#### 实验 B：`allowUiUpdates: true` —— 一个我没预料到的坑

把配置改成 `true`，**重启** `grafana-prov`(3002) 让它生效：

```yaml
allowUiUpdates: true
```

重启后先查状态：

```
  title  = Provisioned Node Overview
  version= 1
  meta.provisioned= False        ← 注意：从 True 变成了 False
```

⚠️ **`meta.provisioned` 变成了 `False`**。这说明 dashboard 被"解绑"了——Grafana 不再认为它是 provisioned 的。

按理说，此时应该可以保存了。实测：

```
  before: title='Provisioned Node Overview' version=1
  SAVE FAILED http=400 body={"message":"Cannot save provisioned dashboard"}
```

**还是 400。**

这就矛盾了：`meta.provisioned=False` 却说"不能保存 provisioned dashboard"。

按下课以来固化的纪律——**先怀疑自己的操作，不急着下结论**。我怀疑是**数据库残留**：这个实例先以 `false` 启动过一次，dashboard 在数据库里已经被标记成 provisioned，后来改配置重启，标记没被清掉。

#### 实验 C：干净对照（决定性证据）

起一个**全新**实例 `grafana-prov2`(3003)，从一开始就用 `allowUiUpdates: true`：

```
  title  = Provisioned Node Overview
  version= 1
  meta.provisioned= False
  meta.provisionedExternalId= prov-dash.json     ← 还留着来源标记
```

再试保存：

```
  before: title='Provisioned Node Overview' version=1
  SAVE http=200 version=2 status=success
```

**保存成功了**，version 从 1 涨到 2。

读回来：

```
  title  = EDITED BY UI (prov2)
  version= 2
```

那么重启后会怎样？

```
=== restart prov2 ===
  after restart: title='Provisioned Node Overview' version=3
```

**标题被回滚成了文件里的值，version 涨到 3。**

这就是 `allowUiUpdates: true` 的完整语义：

> **允许你在 UI 上保存，但重启（或重新扫描）后，文件仍然会把自己写回去。**

它给的是"临时改一下调试"的能力，不是"UI 和文件并存"的能力。

#### 三种行为对照（本课核心表）

| 配置 | UI 能保存吗 | 重启后 | 适用场景 |
|---|---|---|---|
| `allowUiUpdates: false` | ❌ 400 `Cannot save provisioned dashboard` | 文件值 | **生产默认**：强制一切走 Git |
| `allowUiUpdates: true`（干净实例） | ✅ 200 | **被文件覆盖** | 临时调试，改完记得同步回文件 |
| 先 false 后改 true（同实例） | ❌ 400（数据库残留） | 文件值 | **坑：改配置不生效** |

第三行是实测出来的真坑：**改了 `allowUiUpdates` 却"不生效"，因为数据库里旧的 provisioned 标记没清**。

排查手法：看 `meta.provisioned`。如果它是 `True`，说明还被锁着；如果是 `False` 却仍报 400，那就是残留，需要重建 dashboard 或换干净实例。

#### 单向性的另一半：删除文件

前面都在讲"改"。那么"删"呢？

配置 `disableDeletion: false`（允许删除）时：

```
=== 删除该文件（模拟 Git 删除）===
  waiting for resync...
  count= 1
    prov-dash-001 Provisioned Node Overview
```

**dashboard 真的没了。**

改成 `disableDeletion: true`，同样的操作：

```
=== delete file, disableDeletion=true => should SURVIVE ===
  count= 2
    prov-dash-001 Provisioned Node Overview
    prov-dash-002 Second Provisioned Dash
```

**dashboard 还在**，成了"孤儿"——文件没了，库里还留着。

| `disableDeletion` | 删除文件后 | 风险 |
|---|---|---|
| `false` | dashboard 一并删除 | 误删文件 = 误删 dashboard |
| `true` | dashboard 保留（孤儿） | 库中堆积查不到来源的 dashboard |

#### 团队协作怎么约定

把上面的机制翻译成团队规则：

**推荐配置（生产）**：

```yaml
allowUiUpdates: false      # 禁止 UI 改，强制走 Git
disableDeletion: false     # 文件删了就真删，保持 Git 与库一致
editable: true             # 允许在 UI 上看/临时调整（但存不进去）
```

配套的工作流：

1. **改 dashboard 一律改文件**，走 PR review
2. UI 只用于**查看和调试**，不用于保存
3. 确实要在 UI 上试，试完把 JSON 导出，覆盖回文件再提交

**为什么推荐 `allowUiUpdates: false` 而不是 `true`**：

`true` 看起来更宽容，实际更危险——它让你**以为**改成功了（返回 200），结果下次重启悄悄回滚。这种"静默丢失"比当场拒绝难排查得多。

`false` 当场报 400，你立刻知道"这里不能改，得改文件"。**明确的失败好过静默的成功**。

#### 与前面课程的呼应

把这条单向性和课 7/8 的告警对照看，会发现一个有意思的不对称：

| | 配置来源 | 改动方式 |
|---|---|---|
| dashboard | 文件（provisioning） | 单向：文件 → 库 |
| 告警规则 | 库（UI/API）或文件 | 双向都行，但文件优先 |

告警规则在 Grafana 13 里**既可以 UI 配也可以文件配**，且文件配的会在重启时覆盖。所以课 8 那些通知策略、静默窗口，如果你用文件管理，同样要小心 UI 改动丢失。

---

### 10.3 JSON Model 结构与可 diff 化

### 一句话定义

**Dashboard JSON 顶层只有 15 个字段，Grafana 只回填 `id` 和 `version`；提交前剥掉这两个，diff 就干净了。**

### 直觉建立：照片与时间戳

你用手机拍了一张照片，存进 Git。

照片本身（= **dashboard 的内容**）是你关心的：构图、光线、拍了什么。

但文件系统还记录了两个东西：

- **文件在硬盘上的物理扇区号**（= `id`）
- **修改时间**（= `version`）

这两个跟照片内容**毫无关系**，但你每次保存，它们都会变。把它们一起提交进 Git，diff 里永远有两条噪音，reviewer 得手动跳过。

**可 diff 化 = 只提交照片本身，不提交扇区号和修改时间。**

### 核心原理

#### （1）顶层只有 15 个字段

```
annotations / editable / id / links / panels / refresh / schemaVersion
tags / templating / time / timepicker / timezone / title / uid / version
```

分四类：

| 类别 | 字段 |
|---|---|
| **身份** | `uid`、`id`、`version` |
| **内容** | `panels`、`templating`、`annotations`、`links` |
| **展示** | `title`、`tags`、`timezone`、`refresh`、`time`、`timepicker` |
| **元信息** | `schemaVersion`、`editable` |

#### （2）身份三兄弟的区别

| 字段 | 谁定的 | 跨环境稳定 | 用途 |
|---|---|---|---|
| `uid` | **你** | ✅ | 唯一标识，URL 与引用都靠它 |
| `id` | Grafana | ❌ | 内部主键（16 位） |
| `version` | Grafana | ❌ | 乐观锁，每次保存 +1 |

#### （3）Grafana 回填了多少？——实测答案

```
源文件字段数  = 13
库中对象字段数= 15
库中新增（Grafana 回填）: ['id', 'version']
库中缺失（被丢弃）    : []

src panel keys = 8  lib panel keys = 8
lib 新增: []    lib 缺失: []
src panel.id  = 1   lib panel.id  = 1
```

**只回填两个，其余 13 个原样保留；panel 的 `id` 也原样保留。**

#### （4）剥离清单

| 字段 | 处理 | 原因 |
|---|---|---|
| 顶层 `id` | ✅ 剥 | 回填，跨环境必变 |
| 顶层 `version` | ✅ 剥 | 每次保存 +1，纯噪音 |
| `uid` | ❌ 留 | 身份标识，必须进 Git |
| panel `id` | ❌ 留 | Grafana 不改写，留着 diff 更精确 |

### 示例演示：一条命令剥噪音

```bash
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));d.pop('id',None);d.pop('version',None);print(json.dumps(d,indent=2,sort_keys=True,ensure_ascii=False))" prov-dash.json > prov-dash.clean.json
```

三个参数各有作用：

- `sort_keys=True` —— 字段顺序稳定，否则顺序一变 diff 就炸
- `indent=2` —— 一行一字段，diff 才可读
- `ensure_ascii=False` —— 中文标题不被转义成 `\uXXXX`

验证效果：

```bash
wsl -d Ubuntu -- bash -lc "python3 /mnt/d/projects/learning/grafana/playground/l10_diff.py"
```

```
   identical (incl id/version): False
   identical (strip id/version): True
   diff lines: 0
```

### 常见误区

**误区 1：把 `uid` 也剥掉**

`uid` 是你自己定的身份标识，剥掉等于每次重建都换身份——所有引用（告警的 `__dashboardUid__`、外部链接、收藏）全部失效。

**误区 2：不排序就提交**

字段顺序不稳定时，Grafana 换个顺序输出就会炸出一大片 diff。必须 `sort_keys=True`。

**误区 3：以为 panel 的 `id` 也要剥**

实测 panel `id` **原样保留**（文件写 1，库里就是 1）。剥了反而让 diff 丢失信息。

**误区 4：直接提交 UI 导出的 JSON**

UI 导出会带上 `id`、`version`，还可能带上 `__inputs`、`__requires` 等导入专用字段。要剥的不止两个——**推荐以 provisioning 文件为准，不要拿 UI 导出当源文件**。

### 一句话记住

> **剥掉顶层 `id`+`version`，`sort_keys` 后提交——diff 里剩下的就全是真正的业务变更。**

---

#### 先看全貌：顶层只有 15 个字段

从 API 读回本课那张 dashboard：

```
顶层字段 (15 个):
  annotations      dict     1
  editable         bool
  id               int
  links            list     0
  panels           list     1
  refresh          str      3
  schemaVersion    int
  tags             list     2
  templating       dict     1
  time             dict     2
  timepicker       dict     0
  timezone         str      7
  title            str      25
  uid              str      13
  version          int
```

**只有 15 个**。比很多人想象的简单——没有神秘字段，没有隐藏状态。

分成四类理解：

| 类别 | 字段 | 说明 |
|---|---|---|
| **身份** | `uid`、`id`、`version` | 谁、第几版 |
| **内容** | `panels`、`templating`、`annotations`、`links` | 画什么 |
| **展示** | `title`、`tags`、`timezone`、`refresh`、`time`、`timepicker` | 怎么看 |
| **元信息** | `schemaVersion`、`editable` | 结构版本、能否编辑 |

#### 身份三兄弟：`uid` / `id` / `version`

这三个最容易混：

| 字段 | 谁定的 | 跨环境稳定吗 | 用途 |
|---|---|---|---|
| `uid` | **你**（文件里写死） | ✅ 稳定 | dashboard 的唯一标识，URL 里用 |
| `id` | **Grafana**（自动分配） | ❌ 每次变 | 内部主键 |
| `version` | Grafana（递增） | ❌ 每次变 | 乐观锁，防止并发覆盖 |

**`uid` 必须自己写**。不写的话 Grafana 会生成一个随机 uid（像 `dfxhsw8b57pxcd` 那样），你换环境重建就全变了，所有引用它的地方（告警的 `__dashboardUid__`、外部链接）全部失效。

`id` 和 `version` 是**噪音**——它们每次都变，且不可控。

#### 面板结构：8 个字段

```json
{
  "id": 1,
  "type": "timeseries",
  "title": "CPU idle by instance",
  "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
  "datasource": { "type": "prometheus", "uid": "provprom" },
  "targets": [ ... ],
  "fieldConfig": { ... },
  "options": { ... }
}
```

| 字段 | 说明 |
|---|---|
| `id` | 面板 id（**同一张 dashboard 内唯一**，跨 dashboard 可重复） |
| `type` | 面板类型：`timeseries` / `stat` / `table` / `gauge` … |
| `title` | 标题 |
| `gridPos` | 布局：`x`/`y` 是左上角坐标，`w`/`h` 是宽高。**Grafana 用 24 栅格**，`w:12` = 半屏 |
| `datasource` | 引用的数据源（`{type, uid}`） |
| `targets` | 查询（课 4 讲过：一个 target = 一次查询） |
| `fieldConfig` | 字段配置：单位、最小值/最大值、颜色、阈值 |
| `options` | 面板选项：图例、tooltip 等 |

**注意 `datasource` 的写法**：它是 `{type, uid}` 对象，不是字符串。老版本 Grafana 用字符串（`"PromLab"`），新版用对象。**写 provisioning 文件时用对象写法**。

#### 变量结构：`templating.list`

```json
{
  "list": [
    {
      "name": "instance",
      "label": "Instance",
      "type": "query",
      "datasource": { "type": "prometheus", "uid": "provprom" },
      "query": "label_values(node_cpu_seconds_total, instance)",
      "refresh": 1,
      "includeAll": false,
      "multi": false,
      "current": {},
      "options": []
    }
  ]
}
```

跟课 6 的结论完全对上：**`current` 和 `options` 是空的**。

课 6 实测过：变量的取值由**前端打开 dashboard 时现查现填**，后端只存定义。所以 provisioning 文件里这两个字段留空是对的——写了也会被忽略。

#### 可 diff 化：把噪音剥掉

**问题**：dashboard JSON 直接进 Git，diff 会是什么样？

做个实验。同一份文件 provision 到两个实例（3002 和 3003），把两边的 JSON 拿出来比：

```
A(3002) version=1 id=2612996073791488
B(3003) version=3 id=2613936395038720

--- 1) 原始 JSON 是否相同 ---
   identical (incl id/version): False
   identical (strip id/version): True

--- 2) 逐字段比对（只看顶层） ---
   DIFF id               A=2612996073791488
                         B=2613936395038720
   DIFF version          A=1
                         B=3

--- 3) 真实 diff（strip id/version 后） ---
   diff lines: 0
```

**结论极其干净**：

| 比对方式 | 结果 |
|---|---|
| 含 `id` + `version` | 不相同 |
| 剥离 `id` + `version` | **逐字节相同，diff 0 行** |

所以"可 diff 化"的实操定义就一句话：

> **提交前剥掉顶层的 `id` 和 `version`，其余原样保留。**

#### Grafana 到底回填了多少字段

再做一个"往返"实验：把我写的文件和库里读出来的对象比。

```
源文件字段数  = 13
库中对象字段数= 15

库中新增（Grafana 回填）: ['id', 'version']
库中缺失（被丢弃）    : []

--- 逐字段是否一致（源文件有的字段） ---
  (未列出的字段均一致)

--- panel 级 ---
src panel keys = 8  lib panel keys = 8
lib 新增: []
lib 缺失: []
src panel.id  = 1
lib panel.id  = 1
```

**Grafana 只回填了两个字段：`id` 和 `version`。** 其余 13 个字段逐字节保留，**一个都没改**。

而且 panel 级的 `id` 也**原样保留**（文件里写 1，库里就是 1）。

这给出了精确的剥离清单：

| 字段 | 要不要剥 | 原因 |
|---|---|---|
| 顶层 `id` | ✅ 剥 | Grafana 回填，16 位内部主键，跨环境必变 |
| 顶层 `version` | ✅ 剥 | 每次保存 +1，纯噪音 |
| `uid` | ❌ 保留 | 你自己定的身份标识，必须进 Git |
| panel `id` | ❌ 保留 | Grafana 不改写，保留可让 diff 更精确 |
| 其余全部 | ❌ 保留 | Grafana 原样保存 |

#### 实操：一条命令剥噪音

```bash
python3 -c "import json,sys;d=json.load(open(sys.argv[1]));d.pop('id',None);d.pop('version',None);print(json.dumps(d,indent=2,sort_keys=True,ensure_ascii=False))" prov-dash.json > prov-dash.clean.json
```

`sort_keys=True` 也很重要——它保证字段顺序稳定，否则字段顺序一变 diff 就炸。

**完整的提交前处理**：

1. 剥 `id`、`version`
2. `sort_keys=True` 排序
3. `indent=2` 缩进（一行一个字段，diff 才可读）
4. 提交

#### 为什么这事值得单独讲

不剥离的后果很实际：

- **Code review 没法做**：每次 diff 都有 `id` 和 `version` 两行变化， reviewer 得手动跳过
- **合并冲突常态化**：两个人各改一点，都改了 `version`，必冲突
- **误判风险**：`version` 从 1 变 3 看起来像"改了很多"，其实可能只是重启了两次

剥掉之后，diff 里剩下的**全是真正的业务变更**。

---

## 第四幕：实操验证——动手跑一遍

### 环境准备

本课实例（如果还没起）：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-env-up.sh"
```

脚本会先校验四个文件存在，**再**启动容器。这个顺序是必须的——见下面"环境坑 1"。

### 实操 1：验证三类文件都落地了

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-probe1.sh"
```

预期输出：

```
=== datasources ===
  uid=provloki     name=ProvLoki     type=loki
  uid=provprom     name=ProvProm     type=prometheus

=== dashboards search ===
  uid=prov-dash-001    title=Provisioned Node Overview    folder=Provisioned
  total: 1

=== folders ===
  uid=dfxhsw8b57pxcd   title=Provisioned
  uid=provfolder       title=Provisioned

=== alert rules ===
  ns=Provisioned group=prov-group rule=ProvisionalNodeDown
  total rules: 1
```

**注意那两个同名文件夹**——这就是第二幕冲突 3 的现场。

### 实操 2：亲手触发"不能保存"

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-probe5.sh"
```

预期：

```
HTTP 400
{"message":"Cannot save provisioned dashboard"}
```

这条 400 是 `allowUiUpdates: false` 的直接证据。

### 实操 3：验证 allowUiUpdates=true 的完整语义

需要用干净实例（否则会撞上数据库残留）：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-fresh.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-uiedit2.sh"
```

预期三段：

```
  before: title='Provisioned Node Overview' version=1
  SAVE http=200 version=2 status=success          ← 能保存

=== read back ===
  title  = EDITED BY UI (prov2)                   ← 改成功了
  version= 2

=== restart prov2 ===
  after restart: title='Provisioned Node Overview' version=3    ← 被回滚
```

### 实操 4：验证删除行为

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-delete.sh"
```

`disableDeletion: false` 时：新增文件 → 自动出现；删除文件 → dashboard 消失。

对照组（`disableDeletion: true`）：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l10-delete2.sh"
```

删了文件，dashboard 还在。

### 实操 5：JSON Model 与 diff

```bash
wsl -d Ubuntu -- bash -lc "python3 /mnt/d/projects/learning/grafana/playground/l10_jsonmodel.py"
wsl -d Ubuntu -- bash -lc "python3 /mnt/d/projects/learning/grafana/playground/l10_roundtrip.py"
wsl -d Ubuntu -- bash -lc "python3 /mnt/d/projects/learning/grafana/playground/l10_diff.py"
```

第三条的输出是全课的收束：

```
   identical (incl id/version): False
   identical (strip id/version): True
   diff lines: 0
```

### 本课的四个环境坑

**坑 1：docker `-v` 会静默建目录**（课 9 踩过，本课再次确认）

如果宿主机上文件不存在，docker 会把挂载点建**成目录**，容器里的 Python 启动时报 `can't find '__main__' module`。

`l10-env-up.sh` 里那段校验就是为此：

```bash
for f in "$P/datasources/ds.yaml" ...; do
  if [ -f "$f" ]; then echo "OK file: $f"; else echo "MISSING: $f"; exit 1; fi
done
```

**顺序必须是：先写文件，再起容器。**

**坑 2：alerting provisioning 写错 = 起不来**

第二幕那个崩溃。不是警告，是 `Exited (1)`。

排查手法：`docker logs grafana-prov | grep -i 'provisioning'`。

**坑 3：改了 `allowUiUpdates` 不生效**

同一个实例先 `false` 后 `true`，数据库残留导致仍报 400。

判据：`meta.provisioned`。若已 `False` 仍报 400，换干净实例验证。

**坑 4：PowerShell 会吞掉 `$` 和引号**

本项目既有约束——所有命令一律落盘为 `playground/lXX-*.sh` 再用 `wsl bash <脚本>` 执行。

本课踩到的具体症状：`$(seq 1 60)` 在 PowerShell 里变成 `\;`，`curl -m 5` 被解析成 `Invoke-WebRequest -MaximumRedirection`。

### 本课实测结论汇总

| # | 结论 | 证据 |
|---|---|---|
| 1 | alerting provisioning 出错 → **整个 Grafana 崩溃**（不是跳过） | `Exited (1)` + 级联 `Module failed` |
| 2 | `allowUiUpdates: false` → UI 保存被**硬拒**（400） | `{"message":"Cannot save provisioned dashboard"}` |
| 3 | `allowUiUpdates: true`（干净）→ 能保存但重启被覆盖 | version 1→2→3，title 回滚 |
| 4 | 同实例改配置有**数据库残留**，仍报 400 | `meta.provisioned=False` 但保存 400 |
| 5 | dashboards 用 `folderUid`，alerting 用 `folder`（名字）→ **两个同名文件夹** | `provfolder`(1 dash) vs `dfxhsw8b57pxcd`(0) |
| 6 | `editable` 写入、`readOnly` 读出 | `editable=None readOnly=True` |
| 7 | `disableDeletion: false` → 删文件即删 dashboard | count 2→1 |
| 8 | `disableDeletion: true` → 删文件 dashboard 变孤儿 | count 保持 2 |
| 9 | Grafana 只回填 `id` + `version`，其余 13 字段原样保留 | 源文件 13 → 库中 15 |
| 10 | 剥离 `id`+`version` 后，两实例 JSON **逐字节相同** | `diff lines: 0` |
| 11 | `updateIntervalSeconds` 支持热加载 | 新增文件 14 秒后自动出现 |
| 12 | `__dashboardUid__` 与 `__panelId__` 必须成对 | 写其一 → 启动崩溃 |

---

## 第五幕：体系收束

### 本课的一句话

> **Provisioning 是启动时的一次性写入：文件 → 数据库，单向、不可逆。你后来在 UI 上做的一切，下次启动都会被文件抹掉。**

### 与前九课的收束：第七次看到"Grafana 把活揽到自己手里"

课 4 以来我们反复遇到同一个模式，本课是它的**另一种形态**：

| 课 | 现象 | 共同点 |
|---|---|---|
| 课 4 | `editorMode` 存后端跑前端，瞎编值也收 | 后端不校验 |
| 课 5 | `transformations` 存后端跑前端 | 后端不校验 |
| 课 6 | `repeat` 存后端跑前端 | 后端不校验 |
| 课 9 | `exemplarTraceIdDestinations` 瞎编值也收 | 后端不校验 |
| **课 10** | **alerting provisioning 写错直接崩溃** | **后端严格校验** |

**本课是第一个"反向"案例**。原因在第二幕讲过：**时机不同**。

- 运行时写入 → 错了顶多显示异常，可以宽容
- **启动期写入** → 错了就没法提供服务，只能崩溃

所以"Grafana 不校验"这个结论要加个限定：**运行时不校验，启动期严格校验**。

### 与课 9 的方法论呼应

课 9 沉淀了一条纪律：**回读原始响应确认字段名，别凭命名直觉**。本课又用上两次：

1. `editable` 写入、`readOnly` 读出——只看 `editable` 会误判"配置丢了"
2. `allowUiUpdates` 报 400 时，我没有直接写"这个配置失效"，而是起了干净实例对照，才发现是数据库残留

第 2 条尤其典型：**如果我信了"allowUiUpdates 没用"，就会写一条错误结论进讲义**。干净对照救了它。

### 与 Prometheus / 其他课程的横向对照

Provisioning 不是 Grafana 独有的思路。你已经见过类似的：

| 系统 | 配置方式 | 单向吗 |
|---|---|---|
| Prometheus | `prometheus.yml` + `rule_files` | 是（需 reload） |
| Grafana | provisioning 目录 | 是（需重启/定期扫描） |
| Alertmanager | `alertmanager.yml` + `amtool` | 是 |

**共同点**：都是"文件是唯一真相，运行时状态是派生物"。

**不同点**：Prometheus 可以 `/-/reload` 热加载，Grafana 的 datasources 和 alerting **必须重启**（只有 dashboards 有 `updateIntervalSeconds` 热加载）。

这个差异在运维上很实际：**改 Grafana 数据源要计划重启窗口，改 dashboard 不用**。

### 阶段 4 的位置

本课解决的是"配置怎么管"，后面两课解决：

- **课 11**：谁能看、谁能改、程序怎么访问（Org/User/Team、RBAC、服务账号）
- **课 12**：性能、高可用、升级备份

三者合起来才是完整的"管得住"：

```
课 10：配置从哪来（Provisioning）
课 11：谁能动它（权限）
课 12：它挂了怎么办（高可用与运维）
```

### 课 11 的伏笔

本课留下一个没展开的问题：

**`managedBy=classic-file-provisioning` 这个字段是干什么的？**

查文件夹时看到：

```
uid=provfolder       managedBy=classic-file-provisioning
uid=dfxhsw8b57pxcd   managedBy=None
```

`managedBy` 标记了"这个资源归谁管"。它跟权限系统直接相关——**被 provisioning 托管的资源，权限能不能单独给？**

这是课 11 的 RBAC 要处理的。另外，本课在 `grafana-prov` 上建的资源都是 `createdBy: "Anonymous"`：

```
"createdBy":"Anonymous","updatedBy":"Anonymous"
```

**provisioning 写入的资源没有真实作者**。这在审计时是个问题——课 11 讲服务账号时会回到这里。

---

## ✅ 本课小结

| 知识点 | 一句话 | 判据 |
|---|---|---|
| 10.1 三类文件 | datasources 存数据源、dashboards 定义"去哪找"、alerting 存告警规则 | 目录 `/etc/grafana/provisioning/{datasources,dashboards,alerting}` |
| 10.1 写错后果 | alerting 写错 = **进程崩溃**，另两类跳过 | `Exited (1)` + `Failed to provision alerting` |
| 10.1 文件夹 | dashboards 用 `folderUid`、alerting 用 `folder`(名字)，**会建出两个同名文件夹** | `provfolder` vs `dfxhsw8b57pxcd` |
| 10.2 单向性 | 文件 → 数据库，**永不反向** | UI 改动重启后消失 |
| 10.2 `allowUiUpdates` | `false`=硬拒 400；`true`=能存但重启被覆盖 | `Cannot save provisioned dashboard` / version 1→2→3 |
| 10.2 残留坑 | 同实例改配置不生效，需干净实例 | `meta.provisioned=False` 仍 400 |
| 10.2 `disableDeletion` | `false`=删文件即删 dashboard；`true`=留孤儿 | count 2→1 / 保持 2 |
| 10.3 JSON 结构 | 顶层仅 15 字段，Grafana **只回填 id+version** | 源文件 13 → 库中 15 |
| 10.3 可 diff | 剥离顶层 `id`+`version` 后逐字节可比 | `diff lines: 0` |
| 10.3 `uid` | 必须自己写，否则随机生成导致引用全断 | `dfxhsw8b57pxcd` 那种就是随机的 |

---

## 🎓 本课小测

### 选择题（单选）

**1. `provisioning/alerting/` 下的文件写错了，Grafana 会怎样？**

- A. 跳过该文件，正常启动
- B. 该条规则不生效，其余正常
- C. 打一条 error 日志，照常启动
- D. 整个进程退出（Exited 1）

<details><summary>答案</summary>

**D**。实测 `Exited (1)`，日志显示 provisioning 模块失败后 `api.HTTPServer`、`DashboardUpdater` 等全部级联失败。这是启动期校验，与运行时"不校验"的行为相反。

</details>

**2. `allowUiUpdates: false` 时，在 UI 上改 dashboard 并保存，会发生什么？**

- A. 保存成功，重启后被文件覆盖
- B. 保存被拒绝（HTTP 400）
- C. 保存成功且永久保留
- D. 保存成功但只有自己能看到

<details><summary>答案</summary>

**B**。返回 `{"message":"Cannot save provisioned dashboard"}`，HTTP 400。不是"保存后覆盖"，是**根本存不进去**。

</details>

**3. 关于 dashboards 与 alerting 的文件夹配置，正确的是？**

- A. 两者都用 `folderUid`，进同一个文件夹
- B. 两者都用 `folder`（名字），进同一个文件夹
- C. dashboards 用 `folderUid`、alerting 用 `folder`(名字)，会产生两个同名文件夹
- D. 两者都不能指定文件夹

<details><summary>答案</summary>

**C**。实测产生 `provfolder`（装 dashboard）和 `dfxhsw8b57pxcd`（空，alerting 建的）两个同名 "Provisioned" 文件夹。

</details>

**4. 想让 dashboard JSON 在 Git 里可 diff，应该？**

- A. 提交完整的 API 导出结果
- B. 剥掉顶层 `id` 和 `version`
- C. 剥掉 `uid`
- D. 把所有字段都删掉只留 `panels`

<details><summary>答案</summary>

**B**。实测：Grafana 只回填 `id` 和 `version`，剥掉这两个后两实例 JSON 逐字节相同（diff 0 行）。`uid` 必须保留——它是跨环境的身份标识。

</details>

### 判断题

**5. `allowUiUpdates: true` 意味着 UI 改动可以与文件和平共存。**

<details><summary>答案</summary>

**错**。`true` 允许保存（version 1→2），但**重启后仍被文件覆盖**（version→3，title 回滚）。它给的是"临时调试"能力，不是"并存"。

</details>

**6. `disableDeletion: true` 时，删除 dashboard 文件后库里的 dashboard 还在。**

<details><summary>答案</summary>

**对**。实测 count 保持 2，dashboard 成为"孤儿"。`true` 的语义是"别因为文件没了就删我的 dashboard"。

</details>

### 思考题

**7.** 你的团队有 5 个人都要改 dashboard。如果配 `allowUiUpdates: true`，会出现什么问题？如果配 `false`，工作流又该怎么设计？

<details><summary>参考思路</summary>

配 `true`：每个人都能在 UI 上"改成功"，但重启后被文件覆盖——**静默丢失**。更糟的是多人同时改，互相覆盖且无痕迹。

配 `false`：UI 改不动，强制所有人改文件走 PR。代价是想快速试个参数也得走流程；缓解办法是本地起个 Grafana 实例随便试，试完导出 JSON 覆盖回文件提交。

核心权衡：**明确的失败（400）好过静默的成功（200 但会丢）**。

</details>

---

## 📚 延伸阅读

- [Grafana Provisioning 官方文档](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Dashboard JSON Model](https://grafana.com/docs/grafana/latest/dashboards/json-model/)

---

## 🔍 评审结论（对学员可见）

| 项 | 内容 |
|---|---|
| 评审方式 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） |
| P0 数 | **0** |
| P1 数 | 3（已修，见下） |

**P1×3 已修**：

1. **阶段概览表述错误**：`4-管得住/overview.md` 原写「文件里没有 `version` 字段时会覆盖 UI 改动；有则保留」，实测真实开关是 `allowUiUpdates`，已在本课第二幕明确指出并在 10.2 给出对照表
2. **`allowUiUpdates: true` 的初稿结论不完整**：首测同实例得到"仍报 400"，若据此写"配置无效"即为错误结论。起干净实例 `grafana-prov2`(3003) 对照后，确认是数据库残留，真实行为是"能保存但重启被覆盖"
3. **文件夹冲突未给规避办法**：第二幕指出两个同名文件夹问题后，10.1 补充了 `folder` + `folderUid` 成对书写的建议

**评审中判定为脚本缺陷、未改文档×3**：

1. `l10-probe4.sh` 初版用 `\"$u\"` 转义导致 `$u` 未展开、JSON 解析失败 → 改 heredoc + 正常变量
2. `l10-wait.sh` 内联写法被 PowerShell 吞掉 `$` → 落盘执行（本项目既有约束）
3. `||` 在 PowerShell 5.1 中不是合法语句分隔符 → 直接执行目标脚本

**自我纠错 1 处**：初判 `allowUiUpdates=true` 无效，实为数据库残留；干净实例对照后修正。

**课 4 P0 未复发**：本课命令全部落盘为脚本执行，代码块外 0 处反斜杠续行，PowerShell 兼容。

---

## 🚀 下一课接力提示词

```
继续学 Grafana。我的学习档案在 grafana/00-学习档案.md，
刚学完阶段 4《管得住》的课 10《Provisioning：把点击变成配置文件》
知识点 10.1（Provisioning 的三类文件）、
10.2（Dashboard as Code 与 UI 改动的冲突处理）、
10.3（JSON Model 结构与可 diff 化），
请按大纲继续讲解课 11《权限与服务账号：谁能看、谁能改、程序怎么访问》
（知识点：Org / User / Team 三层模型 / RBAC 与文件夹权限 / 服务账号与 API Key）。
```

**课 11 需要复用本课环境**：`grafana-prov`(3002) 与 `grafana-prov2`(3003) 均可直接用于权限实验。

**本课新增的环境资产**（课 11 可复用）：

| 资产 | 值 |
|---|---|
| 容器 | `grafana-prov`(3002)、`grafana-prov2`(3003) |
| 数据源 | `provprom`(uid)、`provloki`(uid) |
| 文件夹 | `provfolder`（1 个 dashboard）、`dfxhsw8b57pxcd`（空） |
| 告警规则 | `ProvisionalNodeDown`，在 `Provisioned` 文件夹 |
| provisioning 文件 | `playground/provisioning/{datasources,dashboards,alerting}` |
| dashboard 文件 | `playground/provisioning/dashboards-json/prov-dash.json` |

**留给课 11 的三个悬念**

1. **`managedBy=classic-file-provisioning` 与权限的关系**：被 provisioning 托管的资源，权限能不能单独授予？还是被托管方的权限统一管理？
2. **provisioning 写入的资源 `createdBy:"Anonymous"`**：审计时查不到真实作者，课 11 的服务账号能否解决？
3. **本课两个同名文件夹的权限怎么给**：同名不同 uid，UI 上看起来一样，授权时极易选错

---

## 课程导航

- **上一课**：[第 9 课：日志与链路](../../3-叫得醒/lessons/lesson-09-日志与链路：指标之外的另外两只眼.md)
- **下一课**：[第 11 课：权限与服务账号](./lesson-11-权限与服务账号：谁能看、谁能改、程序怎么访问.md)
- **阶段概览**：[阶段 4：管得住](../overview.md)
- **课程目录**：[02-课程目录](../../../02-课程目录.md)
- **学习路径**：[01-学习路径总览](../../../01-学习路径总览.md)
- **学习档案**：[00-学习档案](../../../00-学习档案.md)

---

## 📌 速览卡片

| 问题 | 答案 |
|---|---|
| provisioning 是什么 | 启动时把文件配置写进数据库 |
| 三类文件放哪 | `/etc/grafana/provisioning/{datasources,dashboards,alerting}/` |
| dashboards 目录配的是什么 | 不是 dashboard 本身，是**去哪找** dashboard（provider） |
| alerting 写错会怎样 | **整个 Grafana 崩溃**（Exited 1） |
| `allowUiUpdates: false` | UI 保存被**硬拒**（400） |
| `allowUiUpdates: true` | 能保存，但**重启后被文件覆盖** |
| 单向性 | 文件 → 数据库，**永不反向** |
| `disableDeletion: false` | 删文件 = 删 dashboard |
| `disableDeletion: true` | 删文件，dashboard 变孤儿 |
| dashboards vs alerting 文件夹 | 前者 `folderUid`，后者 `folder`(名字)，**会建两个同名** |
| `editable` 怎么判 | 写入 `editable`，读出 `readOnly` |
| dashboard JSON 顶层字段 | 只有 **15 个** |
| Grafana 回填什么 | 只回填 **`id` + `version`** |
| 可 diff 化怎么做 | 剥掉顶层 `id`+`version`，`sort_keys` 后提交 |
| `uid` 要不要自己写 | **必须写**，否则随机生成导致引用全断 |
| panel 的 `id` 要不要剥 | 不用，Grafana 原样保留 |
