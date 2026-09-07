# 第 11 课：权限与服务账号：谁能看、谁能改、程序怎么访问

> 所属阶段：阶段 4《管得住》｜ 水平：入门 ｜ 本课知识点：Org / User / Team 三层模型、RBAC 与文件夹权限、服务账号与 API Key
> 故事情节：团队来了新人——给他看全部？给他改？还是只给他自己那一摊？

## 🎯 本课目标

- 建一个 Team 并给它授权，解释三层的职责边界
- 配出"某团队只能改自己文件夹"的权限结构
- 建服务账号并给最小权限，说清服务账号与 API Key 的区别

## 知识点导航

| # | 知识点 | 关键点 | 状态 |
|---|--------|--------|------|
| 11.1 | Org / User / Team 三层模型 | 各层职责 / 默认 Org / 跨 Org 的隔离边界 | ✅ 已完成 |
| 11.2 | RBAC 与文件夹权限 | 角色类型 / 权限继承 / 常见越权与漏配 | ✅ 已完成 |
| 11.3 | 服务账号与 API Key：程序怎么安全访问 | 服务账号与 API Key 的区别 / 最小权限 / 令牌轮换 | ✅ 已完成 |

---

## 第一幕：场景引入——新同事的第一天

### 一个真实的周一

新人小王入职，你把他加进 Grafana。

然后问题来了：

- 给他 **Viewer**，他只能看，连自己负责那几张 dashboard 的参数都调不了
- 给他 **Editor**，他一不小心把你配了三天的告警规则改了
- 给他 **Admin**，他能把整个数据源删了

你犹豫了一下，给了 Editor。

两周后，你发现生产告警的阈值被人改了，查下来是小王——他只是在调试自己的面板，不知道自己动的是全局规则。

**这不是小王的问题，是权限模型没用对。**

### 三个问题

本课要回答三个层层递进的问题：

1. **Grafana 用什么结构表达"谁"**（11.1）
2. **怎么表达"某人能改某个文件夹，但不能改别的"**（11.2）
3. **程序（CI、脚本、监控系统）怎么访问**（11.3）

### 一个贯穿全课的提醒：权限看不见

前 10 课讲的东西大多**看得见**：面板画出来了、告警响了、数据查出来了。

权限不一样——**配错了往往没症状**。给了过大的权限，系统照样跑；漏给了权限，用户到某个页面才发现点不动。

所以本课的每个结论都必须**实测验证**，不能靠"应该可以"。这也是本课大量使用"能/不能"对照实验的原因。

### 本课的验证方法

本课用**三个用户 + 两个团队 + 两个文件夹**做矩阵实验：

| 主体 | 组织角色 | 团队 | 用途 |
|---|---|---|---|
| `admin` | Admin | — | 基线（什么都能干） |
| `alice` | Viewer | OpsTeam | 测跨 Org 隔离 |
| `bob` | Viewer | 无 | 对照组（什么都干不了） |
| `carol` | Viewer→Editor→Viewer | TeamBGroup | 测角色与文件夹权限的分离 |
| `dave` | Viewer | TeamBGroup（后加入） | **干净对照**（课 10 沉淀的纪律） |
| `ci-bot` | Viewer（服务账号） | — | 测程序访问 |

⚠️ **为什么特意建 `dave`**：本课中途发现 `carol` 的状态被前面的实验污染了（她曾短暂是 Editor，又建过 dashboard 成为 owner）。按课 10 沉淀的纪律——**先怀疑状态残留，起干净对照**——新建 `dave` 从零验证，才拿到可信结论。

### 实验环境

沿用课 10 的 `grafana-prov`(3002)。课 10 建的数据源、`Provisioned` 文件夹、告警规则都在，本课直接在其上做权限实验。

> 本课不碰 `grafana-lab`(3001)——那是日常实例，权限改动会影响前 10 课的状态。

---

## 第二幕：认知冲突——三个"想当然"的错误

### 冲突 1：给了文件夹权限，就能往里写

**直觉**：给 Team 授予文件夹的 Edit 权限，成员就能在里面建 dashboard 了。

**实测第一反应**：给了 `teama` 文件夹 Edit 权限后，carol 建 dashboard **仍然 403**。

但深入排查后发现，这个 403 是我**建 dashboard 的写法错了**（`folderUid` 放错了位置），跟权限无关。修正写法后：

```
dave(Viewer + TeamBGroup + teama=Edit) → 往 teama 建 → HTTP 200 ✅
dave(Viewer + TeamBGroup + teama=Edit) → 往 teamb 建 → HTTP 403 ❌
  {"message":"folders.folder.grafana.app \"teamb\" is forbidden: access denied to folder"}
```

**结论**：文件夹权限**确实生效**，而且边界很清晰——授权的能写，没授权的不行。

**但这里有个真问题**：我在排查过程中一度以为"文件夹权限没生效"，差点写成错误结论。真正的原因是我把 `folderUid` 写在了 dashboard 对象内部，而 **Grafana 13 要求它放在 payload 顶层**（详见第四幕）。

### 冲突 2：Team 成员资格自带权限

**直觉**：把人加进 Team，他就自动获得这个 Team 的权限。

**实测**：`dave` 加入 `TeamBGroup` 后，权限**一个都没多**：

```
dave(Viewer, 无 Team)          -> ['dashboards:read', 'folders:read']
dave(Viewer, + TeamBGroup)     -> ['dashboards:read', 'folders:read']     ← 没变
dave(Viewer, + teama=Edit)     -> ['dashboards:create', 'dashboards:delete',
                                   'dashboards:read', 'dashboards:write',
                                   'folders:create', 'folders:delete',
                                   'folders:read', 'folders:write']       ← 变了
```

**真实规则**：**Team 只是"一批人的集合"，本身不带任何权限**。权限来自"Team + 资源 + 权限级别"这条**授权记录**。

这是本课最重要的一句话之一：

> **Team 是授权的单位，不是权限的来源。**

### 冲突 3：`hasAcl` 能用来判断文件夹有没有设权限

**直觉**：`GET /api/folders/teama` 返回的 `hasAcl` 字段，能告诉我这个文件夹有没有配 ACL。

**实测**：

```
权限记录（GET /api/folders/teama/permissions）：
  记录数 = 1
    teamId=2 team=TeamBGroup permission=2(Edit) inherited=False

文件夹详情（GET /api/folders/teama）：
  hasAcl = False        ← 明明有权限，却说没有
```

权限明明存在，`hasAcl` 却是 `false`。这不是"设权限失败了"——实际写入测试证明权限**是生效的**。

我追到数据库层面才拿到答案：

```
folder 表字段: ['id', 'uid', 'org_id', 'title', 'description',
               'parent_uid', 'created', 'updated']

ERR no such column: has_acl
```

**`folder` 表里根本没有 `has_acl` 这一列。**

**真实规则**：Grafana 13 换了权限存储（新 `permission` 表 + k8s 风格 scope），`hasAcl` 是**遗留的计算字段，恒为 false**，已经不可信。

> **判据**：判断文件夹权限是否配好，**看 `/api/folders/{uid}/permissions` 的记录，或直接做一次写入测试**。不要看 `hasAcl`。

这是本课第二个重要教训：**API 里的字段不一定还活着**。

### 三个冲突的共同点

| 冲突 | 想当然 | 实测 |
|---|---|---|
| 1 | 给了权限就能写 | 能，但我的**写法**先错了，差点误判权限失效 |
| 2 | 加入 Team 就有权限 | Team 不带权限，**授权记录**才带 |
| 3 | `hasAcl` 反映 ACL 状态 | 遗留字段，**恒 false**，已不可信 |

三个都指向同一件事：**权限这类"看不见"的配置，必须用实测行为判定，不能靠字段推断。**

---

## 第三幕：层层揭示——三层模型、RBAC 与服务账号

### 11.1 Org / User / Team 三层模型

#### 一句话定义

**Org 是租户（硬隔离）、User 是身份（登录用的）、Team 是授权单位（一批人的集合）。**

#### 直觉建立：公司 / 员工 / 部门

用公司结构类比：

| Grafana | 公司 | 作用 |
|---|---|---|
| **Org** | 一家**公司** | A 公司的资产，B 公司的人**看不到** |
| **User** | 一个**员工** | 有工号、能登录 |
| **Team** | 一个**部门** | 把人归堆，方便一次性授权 |

关键点在于**三者的依赖关系不同**：

- 一个 User 可以**同时在多家公司**（Org）任职
- 但**同一时刻只能以一家公司的身份工作**（当前 Org）
- 部门（Team）**隶属于某一家公司**，不能跨公司

最后一条最容易被忽略：**Team 是 Org 内部的，Org 之间不共享 Team。**

#### 核心原理

##### （1）Org：最硬的边界

新建一个 Org：

```bash
curl -X POST http://localhost:3002/api/orgs   -u admin:admin -H 'Content-Type: application/json' -d '{"name":"TeamB"}'
```

```json
{"message":"Organization created","orgId":2}
```

现在有两个 Org：

```json
[{"id":1,"name":"Main Org."},{"id":2,"name":"TeamB"}]
```

**Org 之间隔离到什么程度？** 做个实验。

把 `alice` 加进 Org 2：

```bash
curl -X POST http://localhost:3002/api/orgs/2/users   -u admin:admin -H 'Content-Type: application/json' -d '{"loginOrEmail":"alice","role":"Viewer"}'
```

切到 Org 2 看看：

```bash
# 切换当前 Org
curl -X POST http://localhost:3002/api/user/using/2 -u alice:...
# {"message":"Active organization changed"}

# 看 dashboard
curl http://localhost:3002/api/search?type=dash-db -u alice:...
# []

# 看数据源
curl http://localhost:3002/api/datasources -u alice:...
# []
```

**全空。** 而 alice 在 Org 1 里明明能看到 `prov-dash-001` 和两个数据源。

##### （2）隔离有多硬？——越权测试

"看不到列表"可能只是列表被过滤了。真正的测试是**用 uid 直接打**：

```
alice 在 Org2 读 Org1 的 dashboard (uid=prov-dash-001)  → 404 {"message":"Dashboard not found"}
alice 在 Org2 读 Org1 的数据源   (uid=provprom)          → 404 {"message":"Data source not found"}
```

**404，不是 403。**

这个细节很值得注意：Grafana 对跨 Org 的资源返回 **404（不存在）而不是 403（无权限）**。这是安全上的常见做法——**不泄露资源的存在性**。

> **判据**：跨 Org 访问返回 404 而非 403。这是"故意装作不存在"，不是"没配好"。

##### （3）User：身份 + 在每个 Org 里各有一个角色

新建用户：

```bash
curl -X POST http://localhost:3002/api/admin/users   -u admin:admin -H 'Content-Type: application/json' -d '{"name":"alice","login":"alice","email":"alice@example.com","password":"pass-alice-123"}'
```

```json
{"id":2,"uid":"ffxhumr9vtkhse","message":"User created"}
```

⚠️ **新建用户的默认角色是 `Viewer`**：

```
admin    userId=1 role=Admin
alice    userId=2 role=Viewer     ← 默认
bob      userId=3 role=Viewer
```

这跟很多人想的不同——**不是"新建用户没权限"，而是"新建用户有 Viewer 权限"**。Viewer 能读所有 dashboard 和数据源（本课实测：alice 作为 Viewer 能读到 provisioning 建的两个数据源）。

**角色是"User × Org"的二元关系**，不是用户的属性：

| org_id | user_id | role |
|---|---|---|
| 1 | 1 | Admin |
| 2 | 1 | Admin |
| 1 | 2 | Viewer |
| 2 | 2 | Viewer |

同一个 `alice`，在 Org 1 和 Org 2 **各有各的角色**。所以"alice 是什么角色"这个问题没有答案，必须问"alice 在哪个 Org 里是什么角色"。

##### （4）Team：只归堆，不授权

建 Team：

```bash
curl -X POST http://localhost:3002/api/teams   -u admin:admin -H 'Content-Type: application/json' -d '{"name":"OpsTeam","email":"ops@example.com"}'
```

```json
{"message":"Team created","teamId":1,"uid":"ffxhumrg72by8f"}
```

**注意一个副作用**：建 Team 时，**创建者被自动加为成员，且 `permission: 4`（Team Admin）**：

```
userId=1 login=admin   permission=4     ← 建团队的人自动成为 Team Admin
userId=2 login=alice   permission=0     ← 手动加的是普通 Member
```

`permission` 是**团队内**的角色（Member / Team Admin），跟 Org 角色、跟资源权限**都无关**。

⚠️ **一个 API 陷阱**：`GET /api/teams` 返回 **404**，必须用 `GET /api/teams/search`：

```
GET /api/teams              → 404 {"message":"Not found"}
GET /api/teams?perpage=50   → 404 {"message":"Not found"}
GET /api/teams/search?perpage=50  → 200 ✅
```

这是本课遇到的**第三个**此类接口（课 7 的 `GET /api/alert-notifications`、课 10 的 `GET /api/teams` 同族）。Grafana 13 的列表接口普遍迁移到了 `/search` 后缀。

#### 示例演示：完整走一遍三层

```bash
# 1. 建 Org
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-org-setup.sh"

# 2. 把用户加进第二个 Org 并切换
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-org-switch.sh"

# 3. 越权测试
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-crossorg.sh"
```

#### 常见误区

**误区 1：以为 Org 之间能共享数据源**

不能。每个 Org 有**自己独立的一套**数据源、dashboard、告警规则。切了 Org 就像换了个 Grafana。

**误区 2：以为新建用户"没权限"**

新用户默认 **Viewer**，能读所有 dashboard 和数据源。如果想让他什么都看不到，得显式处理，不是"建完就安全"。

**误区 3：以为 Team 成员资格 = 权限**

第二幕冲突 2 已证：加入 Team **不获得任何权限**。权限来自授权记录。

**误区 4：用 `GET /api/teams` 列团队**

404。用 `/api/teams/search`。

#### 一句话记住

> **Org 是墙（跨过去 404 装作不存在），User 是钥匙（每个 Org 一把、角色各不同），Team 只是钥匙串（方便批量发，本身开不了锁）。**

---

### 11.2 RBAC 与文件夹权限

#### 一句话定义

**RBAC = 角色决定"能不能做某个动作"，文件夹权限决定"能对哪些资源做"；两道闸门都要过。**

#### 直觉建立：门禁卡与房间权限

想象一栋办公楼。

**第一道：门禁卡类型**（= RBAC 角色）

- 访客卡：**只能进公共区**
- 员工卡：**能进办公区**
- 管理员卡：**能进机房**

**第二道：具体房间的授权名单**（= 文件夹权限）

- 302 会议室的名单上有你 → 你能进
- 305 实验室的名单上没你 → 即使你有员工卡，也进不去

**两道都要过**：

- 有员工卡 + 302 在名单上 → ✅ 能进
- 有员工卡 + 305 不在名单上 → ❌ 进不去（"你的卡不够"）
- 只有访客卡 + 302 在名单上 → ❌ 也进不去（"卡类型不够"）

本课的实验正好复现了这两种拒绝。

#### 核心原理

##### （1）四种角色

| 角色 | 能做什么 | 本课谁是这个角色 |
|---|---|---|
| **Viewer** | 看 dashboard、看数据源 | alice / bob / carol / dave |
| **Editor** | + 建/改 dashboard、建文件夹 | carol（中途临时） |
| **Admin** | + 增删数据源、管用户、管 Org 设置 | admin |
| **Grafana Admin** | + 管整个 Grafana 实例（跨 Org） | admin（默认） |

用权限列表看差异最直观：

```
bob/dave(Viewer, 无 Team)  -> ['dashboards:read', 'folders:read']
dave(+ teama=Edit)         -> ['dashboards:create', 'dashboards:delete',
                               'dashboards:read',  'dashboards:write',
                               'folders:create',   'folders:delete',
                               'folders:read',     'folders:write']
```

**Viewer 只有 `read` 两个权限**，加了文件夹 Edit 后多了六个。

##### （2）文件夹权限：三种级别

```bash
curl -X POST http://localhost:3002/api/folders/teama/permissions   -u admin:admin -H 'Content-Type: application/json' -d '{"items":[{"teamId":2,"permission":2}]}'
```

`permission` 取值：

| 值 | 名称 | 含义 |
|---|---|---|
| 1 | **View** | 能看 |
| 2 | **Edit** | 能改、能建、能删 |
| 4 | **Admin** | 能改权限本身 |

授权对象可以是三种（三选一写在 items 里）：

```json
{"items":[
  {"userId": 4, "permission": 2},      // 给某个用户
  {"teamId": 2, "permission": 2},      // 给某个团队
  {"role": "Viewer", "permission": 1}  // 给某个角色
]}
```

回读：

```json
[{
  "folderId": 2618213781143552,
  "teamId": 2, "team": "TeamBGroup",
  "permission": 2, "permissionName": "Edit",
  "uid": "teama", "title": "TeamA-Folder",
  "inherited": false
}]
```

##### （3）两道闸门：决定性实验

这是本课的核心实验。用干净用户 `dave`：

| 状态 | 权限列表 | 往 teama（已授权 Edit） | 往 teamb（未授权） |
|---|---|---|---|
| Viewer，无 Team | `read` 仅 | — | — |
| **+ TeamBGroup + teama=Edit** | `create/delete/read/write` | **200 ✅** | **403 ❌** |

对照组 `bob`（Viewer，无 Team，从未被授予任何文件夹权限）：

```
bob 往 teama 建 dashboard → 403
{"accessErrorId":"ACE6065296356",
 "message":"You'll need additional permissions to perform this action.
            Permissions needed: any of dashboards:create, dashboards:write",
 "title":"Access denied"}
```

**注意两种 403 的区别**——这是本课最实用的一条排障知识：

| 现象 | 原因 | 错误信息 |
|---|---|---|
| bob 的 403 | **第一道闸门**（角色不够，没有 `dashboards:create`） | `Permissions needed: any of dashboards:create, dashboards:write` |
| dave 往 teamb 的 403 | **第二道闸门**（有动作权限，但文件夹没授权） | `folders.folder.grafana.app "teamb" is forbidden: access denied to folder` |

**看错误信息就能区分是哪道闸门拦的**，不用猜。

##### （4）权限继承

回读权限时有个字段：

```json
"inherited": false
```

`inherited: true` 表示该权限是**从父文件夹继承**的。Grafana 13 的 folder 表有 `parent_uid` 字段，说明支持嵌套文件夹：

```
folder 表字段: ['id','uid','org_id','title','description',
               'parent_uid','created','updated']
```

嵌套文件夹时，子文件夹默认继承父文件夹的权限。**`inherited` 就是标记"这条是继承来的，不是单独设的"**。

⚠️ 注意：改父文件夹权限会连带影响所有子文件夹。这是"漏配"的高发区——你以为只在子文件夹上加了一条，其实是继承来的。

##### （5）权限真身在哪：新的 permission 表

追 `hasAcl` 时看到了权限的真实存储：

```
permission 表字段:
['id','role_id','action','scope','created','updated',
 'kind','attribute','identifier','datasource_type']

示例行：
(1, 1, 'notifications.alerting.grafana.app/routingtrees:edit',
       'notifications.alerting.grafana.app/routingtrees:uid:user-defined', ...)
```

注意 `action` 和 `scope` 的格式——**k8s 风格的 `{group}/{resource}:{verb}`**。这是 Grafana 13 的统一权限模型（k8s-native），老的 `dashboards:create` 是它的简写形式。

所以你看到的 `dashboards:create` 和数据库里的 `dashboards.dashboard.grafana.app/dashboards:create` 是**同一件事的两种写法**。

#### 示例演示：配出"某团队只能改自己文件夹"

完整流程：

```bash
# 1. 建文件夹与团队
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-folder-setup.sh"

# 2. 授权 + 验证写入
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-perm-retest.sh"

# 3. 两道闸门对照
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-viewer-test.sh"

# 4. 干净用户决定性验证
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-root-cause.sh"
```

⚠️ **建 dashboard 到指定文件夹的正确写法**（第四幕详述）：

```json
{"dashboard":{...}, "folderUid":"teama"}     ✅ 顶层
{"dashboard":{..., "folderUid":"teama"}}     ❌ 会落到 General
```

#### 常见误区

**误区 1：给了文件夹权限忘了给"建"的权限**

阶段概览里写的那句"给了文件夹权限忘了给 dashboard 权限"——实测下来要修正：

**正确的说法是两道闸门**：文件夹 Edit 权限会**顺带**授予 `dashboards:create`（dave 的实验证明），所以"给文件夹权限"通常就够了。真正的漏配是反过来的——**只给了 Viewer 角色又想让人改**，那才会卡在第一道闸门。

**误区 2：用 `hasAcl` 判断有没有配权限**

第二幕冲突 3 已证：**`hasAcl` 恒为 false，`folder` 表里压根没这一列**。看 `/permissions` 记录或直接测写入。

**误区 3：以为 Team 成员资格自带权限**

第二幕冲突 2 已证：不带。

**误区 4：以为 403 都是一回事**

不是。看错误信息区分"动作权限不够"和"文件夹没授权"，两者的修法完全不同。

#### 一句话记住

> **角色是入场券（能不能做这个动作），文件夹权限是座位号（能对哪些资源做）；403 的错误信息会告诉你卡在哪一道。**

---

### 11.3 服务账号与 API Key：程序怎么安全访问

#### 一句话定义

**服务账号是"给程序用的用户"，它用可轮换的 token 访问；API Key 是旧机制，在 Grafana 13 上接口已被移除，只剩数据库遗留表。**

#### 直觉建立：员工卡 vs 临时访客码

**服务账号** ≈ 给外包团队办的**长期员工卡**：

- 有名字（"保洁公司-张三"）
- 有固定权限（只能进公共区）
- **卡丢了能挂失重办**（token 可单独吊销，不影响其他）
- 一个人可以有**多张卡**（多 token），分别用于不同用途

**API Key** ≈ 贴在门上的**一次性密码**：

- 生成后只有一串字符
- **不记名、不可细分权限**（只有一个角色）
- 想换就得**整体作废**

服务账号的关键优势是**可管理**：能列、能吊销单个、能设过期时间。

#### 核心原理

##### （1）建服务账号

```bash
curl -X POST http://localhost:3002/api/serviceaccounts   -u admin:admin -H 'Content-Type: application/json' -d '{"name":"ci-bot","role":"Viewer"}'
```

```json
{
  "id": 6,
  "uid": "bfxhv4xnb84jkd",
  "name": "ci-bot",
  "login": "sa-1-ci-bot",
  "orgId": 1,
  "isDisabled": false,
  "role": "Viewer",
  "tokens": 0
}
```

三点注意：

1. **`login` 是自动生成的**：`sa-1-ci-bot`（`sa-{id}-{name}`）。你不能自己指定。
2. **`id` 不一定从 1 开始**——本课拿到的是 `id: 6`（前面已占用）。**后续调用必须用返回的实际 id**，凭猜会 404。
3. `role` 决定了它的**角色**（第一道闸门），跟普通用户一样。

##### （2）建 token：明文只出现一次

```bash
curl -X POST http://localhost:3002/api/serviceaccounts/6/tokens   -u admin:admin -H 'Content-Type: application/json' -d '{"name":"ci-token-1"}'
```

```json
{
  "id": 1,
  "name": "ci-token-1",
  "key": "glsa_RcFBgdoNIIwZyFX14SjGWNr4HWIdL9S0_…（已脱敏，末 4 位 178a）"
}
```

⚠️ **`key` 只在这一次响应里出现**。再列一次：

```json
[{
  "id": 1,
  "name": "ci-token-1",
  "created": "2026-09-07T02:50:40Z",
  "lastUsedAt": null,
  "expiration": null,
  "secondsUntilExpiration": 0,
  "hasExpired": false,
  "isRevoked": false
}]
```

**没有 `key` 字段。**

这是设计，不是 bug：Grafana **只存 token 的哈希**，不存明文。忘了就只能吊销重发。

> **判据**：`glsa_` 前缀 = Grafana **L**evel **S**ervice **A**ccount token。

##### （3）用 token 访问

```bash
curl -H "Authorization: Bearer glsa_xxx" http://localhost:3002/api/dashboards/uid/prov-dash-001
```

实测（`ci-bot` 是 Viewer）：

```
读 dashboard  → 200 ✅
读数据源      → 200 ✅
建 dashboard  → 403 ❌  Permissions needed: any of dashboards:create, dashboards:write
读用户列表    → 403 ❌  Permissions needed: org.users:read
```

**完美符合最小权限**：能读该读的，写和管理全被拒。

而且注意 `canSave: false, canEdit: false, canAdmin: false`——前端拿到这个 meta 会把编辑按钮藏起来，用户连"试一下"的机会都没有。

##### （4）API Key：接口已移除

⚠️ **本课最重要的发现之一**。

试了三个路径，全部 404：

```
GET  /api/auth/keys     → 404 {"message":"Not found"}
GET  /api/apikeys       → 404
GET  /api/org/apikeys   → 404
POST /api/auth/keys     → 404 {"message":"Not found"}
```

按纪律不能只看 404 就下结论（可能是路径变了）。追到数据库：

```
表总数: 92
相关表: ['api_key']

api_key 表内容: 行数 = 1
```

**准确结论**：

> **`api_key` 表还在（遗留数据），但 HTTP 接口已全部移除。**

也就是说：**Grafana 13.2.1 上已经不能创建新的 API Key 了。** 老版本升级上来的话，旧数据还在表里，但没法通过 API 管理。

补充一个细节：`service_account` 表**不在**这 92 张表里（本课查过），说明服务账号用了新的统一存储（k8s 风格）。这也印证了 Grafana 13 正在做权限与身份模型的整体迁移。

##### （5）服务账号 vs API Key

| | 服务账号 | API Key（旧） |
|---|---|---|
| 状态（13.2.1） | ✅ 可用 | ❌ **接口已移除**，仅剩遗留表 |
| 身份 | 有 `login`、有 `uid`、可审计 | 只有一串字符 |
| 多令牌 | ✅ 一个账号多个 token，可分别吊销 | ❌ 一个 key 一个角色 |
| 吊销 | ✅ 单个吊销，不影响其他 | ❌ 整体作废 |
| 过期时间 | ✅ 支持 | 部分版本支持 |
| 最小权限 | ✅ 角色 + 细粒度 RBAC | ⚠️ 只有一个角色 |
| 前缀 | `glsa_` | `eyJr`（旧 JWT 风格） |

#### 示例演示

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-sa2.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-token-test.sh"
```

坐实 API Key 移除：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-dbcheck.sh"
```

#### 常见误区

**误区 1：建服务账号后拿 id=1 去建 token**

本课就踩了——返回 `id: 6`，我却用 1，得到：

```json
{"statusCode":404,"messageId":"serviceaccounts.ErrNotFound",
 "message":"service account not found"}
```

**必须用响应里返回的 id。**

**误区 2：以为能再次拿到 token 明文**

不能。只存哈希。忘了就吊销重发。

**误区 3：把 `glsa_` token 当密码到处放**

它是** bearer credential**，泄漏等于身份被盗。要放 secret manager，不要进 Git。

**误区 4：给服务账号 Admin 图省事**

本课 `ci-bot` 给的是 Viewer，读写边界清晰。给 Admin 等于把整个 Grafana 交给 CI 脚本。

#### 令牌轮换

服务账号支持多 token，这带来一个标准轮换姿势：

1. 建 **新 token**（`ci-token-2`），此时新旧都有效
2. 把 CI 里的旧 token 换成新 token
3. 观察旧 token 的 `lastUsedAt` 不再更新
4. **吊销旧 token**

**先建后删，全程无停机**——这是 API Key 做不到的（它只能整体作废）。

#### 一句话记住

> **服务账号 = 有名字、可多令牌、可单个吊销、可轮换的程序身份；API Key 在 13.x 上接口已死，别再找它。**

---

## 第四幕：实操验证——动手跑一遍

### 环境确认

本课沿用课 10 的 `grafana-prov`(3002)。确认它还活着：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-envcheck.sh"
```

预期：`3002: {"database":"ok","version":"13.2.1",...}`，且 Org 只有 `Main Org.`。

### 实操 1：三层模型（11.1）

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-org-setup.sh"
```

预期：

```
=== 1. 建第二个 Org ===
{"message":"Organization created","orgId":2}

=== 2. 列所有 Org ===
[{"id":1,"name":"Main Org."},{"id":2,"name":"TeamB"}]

=== 3. 建两个普通用户 ===
alice -> {"id":2,"uid":"ffxhumr9vtkhse","message":"User created"}
bob   -> {"id":3,"uid":"ffxhumrbyqiv4c","message":"User created"}

=== 6. 列 Team ===
{"message":"Not found"}          ← 这是预期的，见下文"坑 1"
```

**新建用户默认角色是 Viewer**，在"列用户"输出里能看到：

```
admin  userId=1 role=Admin
alice  userId=2 role=Viewer
bob    userId=3 role=Viewer
```

### 实操 2：跨 Org 隔离与越权测试（11.1）

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-org-switch.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-crossorg.sh"
```

关键输出：

```
=== 6. alice 切到 Org 2 后看 dashboard ===
  switch http=200 {"message":"Active organization changed"}
  http=200
[]                                    ← 全空

=== 1. 越权：alice 在 Org2 读 Org1 的 dashboard ===
  http=404 {"message":"Dashboard not found"}

=== 3. alice 在 Org2 建 dashboard ===
  http=403 {"accessErrorId":"ACE8481781917",
            "message":"You'll need additional permissions...
                       Permissions needed: any of dashboards:create, dashboards:write"}
```

**注意**：跨 Org **读**是 404（装作不存在），跨 Org **写**是 403（明确拒绝）。

### 实操 3：文件夹权限与两道闸门（11.2）

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-folder-setup.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-perm-retest.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-viewer-test.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-root-cause.sh"
```

最后一个脚本给出**决定性对照**：

```
=== 2. dave 加入 team 后，给他 teama 的 Edit，再看权限 ===
  --- dave(Viewer, TeamBGroup, teama=Edit) ---
    ['dashboards:create','dashboards:delete','dashboards:read','dashboards:write',
     'folders:create','folders:delete','folders:read','folders:write']

  --- dave 往 teama 建 dashboard ---
  http=200 ✅

  --- dave 往 teamb(未授权) 建 dashboard ---
  http=403 {"message":"folders.folder.grafana.app \"teamb\" is forbidden: access denied to folder"}
```

### 实操 4：服务账号与 API Key（11.3）

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-sa2.sh"
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-token-test.sh"
```

关键输出：

```
=== 2. 用正确 id (6) 建 token ===
{"id":1,"name":"ci-token-1","key":"glsa_RcFBgdoNIIwZyFX14SjGWNr4HWIdL9S0_…（已脱敏，末 4 位 178a）"}

=== 3. 列 token ===
[{"id":1,"name":"ci-token-1","lastUsedAt":null,"hasExpired":false,"isRevoked":false}]
                                                    ↑ 注意：没有 key 字段

=== 4. API Key 相关接口探测 ===
  GET /api/auth/keys    http=404 {"message":"Not found"}
  GET /api/apikeys      http=404 {"message":"Not found"}
  GET /api/org/apikeys  http=404 {"message":"Not found"}
```

坐实 API Key 已移除（查数据库）：

```bash
wsl -d Ubuntu -- bash -lc "bash /mnt/d/projects/learning/grafana/playground/l11-dbcheck.sh"
```

```
  表总数: 92
  相关表: ['api_key']
  api_key                  YES
  service_account          no      ← 服务账号已迁出传统表
```

### 本课的六个坑

**坑 1：`GET /api/teams` 和 `GET /api/serviceaccounts` 都是 404**

列表接口要用 `/search` 后缀：

```
GET /api/teams               → 404
GET /api/teams/search        → 200 ✅
GET /api/serviceaccounts     → 404 {"message":"Not found"}
```

本课遇到的第三个同类接口（课 7 `GET /api/alert-notifications` 也是）。

**坑 2：服务账号 id 从响应取，不要猜**

本课服务账号拿到 `id: 6`，用 `1` 去建 token 会得到：

```json
{"statusCode":404,"messageId":"serviceaccounts.ErrNotFound","message":"service account not found"}
```

**坑 3：`folderUid` 必须放在 payload 顶层**

这是本课排查耗时最长的一个，也是最容易误判为"权限没生效"的：

```json
{"dashboard":{...},"folderUid":"teama"}          ✅ 进 teama
{"dashboard":{...,"folderUid":"teama"}}          ❌ 落到 General
```

实测：

```
--- 尝试 A: dashboard 里放 folderUid ---
  -> folderUid=  title= General          ❌

--- 尝试 B: payload 顶层放 folderUid ---
  -> folderUid= teama title= TeamA-Folder  ✅

--- 尝试 C: meta 里放 folderUid ---
  -> folderUid=  title= General          ❌
```

`folderId` 同样无效。

⚠️ **这个坑的危险之处**：它返回 **HTTP 200**，dashboard 建成功了——只是建错了地方。你会以为"权限生效了"或"权限没生效"，两种误判都可能发生。

**坑 4：`hasAcl` 恒为 false，别信**

`folder` 表里没有 `has_acl` 列。看 `/permissions` 记录或直接做写入测试。

**坑 5：实验主体被前面的操作污染**

本课 `carol` 一度是 Editor、又建过 dashboard 成为 owner，导致她的权限"说不清"。新建一个干净用户 `dave` 才拿到可信结论。

这是课 10 沉淀的纪律的第二次应用：**先怀疑状态残留，起干净对照**。

**坑 6：PowerShell 会吞掉 `$` 和引号**

本项目既有约束——所有命令一律落盘为 `playground/lXX-*.sh` 再执行。本课全程遵守。

### 本课实测结论汇总

| # | 结论 | 证据 |
|---|---|---|
| 1 | 新建用户**默认角色是 Viewer**（不是"无权限"） | `alice userId=2 role=Viewer` |
| 2 | 跨 Org **读**资源 → **404**（装作不存在） | `Dashboard not found` / `Data source not found` |
| 3 | 跨 Org 列表 → **空数组** | `[]` |
| 4 | **Team 成员资格不带任何权限** | dave 加入前后权限列表完全一致 |
| 5 | 文件夹 Edit 会**顺带授予** `dashboards:create` 等 | dave 授权后从 2 个权限变 8 个 |
| 6 | 两道闸门：动作权限 + 文件夹权限**都要过** | dave 往 teamb 403 `access denied to folder` |
| 7 | 两种 403 **错误信息不同**，可据此定位 | `Permissions needed:` vs `is forbidden: access denied to folder` |
| 8 | **`hasAcl` 恒 false，`folder` 表无此列** | 有权限记录但 `hasAcl=false` |
| 9 | `folderUid` 必须放 **payload 顶层**，否则落 General（且返回 200） | 三种写法对照 |
| 10 | 服务账号 token **明文只出现一次**（只存哈希） | 列 token 无 `key` 字段 |
| 11 | **API Key 接口已全部移除**，仅剩 `api_key` 遗留表 | 三路径 404 + 表仍在 |
| 12 | 服务账号 Viewer 写操作被**精确拒绝** | `dashboards:create` / `org.users:read` 403 |
| 13 | 建 Team 时**创建者自动成为 Team Admin**（`permission: 4`） | `userId=1 login=admin permission=4` |
| 14 | 权限真身在 `permission` 表，用 **k8s 风格** scope | `notifications.alerting.grafana.app/routingtrees:edit` |

---

## 第五幕：体系收束

### 本课的一句话

> **角色是入场券（能不能做这个动作），文件夹权限是座位号（能对哪些资源做）；Team 只是把人归堆，本身不开锁。**

### 与前十课的收束：第八次看到"Grafana 把活揽到自己手里"

课 4 以来反复出现的模式，本课又添两例，而且**形态变了**：

| 课 | 现象 | 形态 |
|---|---|---|
| 课 4/5/6/9 | 瞎编的值也收 | 后端**不校验** |
| 课 10 | alerting provisioning 写错崩溃 | **启动期严格校验** |
| **课 11** | `folderUid` 放错位置**返回 200** 但落到别处 | **静默降级** |
| **课 11** | `hasAcl` 恒 false | **遗留字段不报错** |

后两条是新形态：**不报错，但结果不对**。这比报错更难排查——你拿到 200，以为成功了。

应对方式只有一个：**验证结果，而不是看状态码**。本课每个结论都是"做完再看东西在哪、能不能用"，而不是"看返回码"。

### 与课 10 的方法论呼应（纪律的第二次应用）

课 10 沉淀了一条纪律：**改了配置却"不生效"时，先怀疑状态残留，起干净实例对照**。

本课第二次用到它，但场景不同：

| | 课 10 | 课 11 |
|---|---|---|
| 问题 | `allowUiUpdates` 改了仍报 400 | carol 的权限"说不清" |
| 污染来源 | 数据库里的 provisioned 标记 | carol 曾是 Editor + 是 dashboard owner |
| 解法 | 起全新实例 `grafana-prov2` | 建全新用户 `dave` |

**共同点**：都是"当前对象的历史状态影响了观察结果"。解法都是**引入一个没有历史的新对象**。

这条纪律现在有了两个不同领域的验证，可信度更高了。

### 与 Prometheus / 其他课程的横向对照

权限模型不是 Grafana 独有的。你已经见过类似的：

| 系统 | 隔离单位 | 授权单位 | 程序访问 |
|---|---|---|---|
| Prometheus | 无内置（靠反向代理） | — | Bearer token |
| Grafana | **Org** | **Team** | **服务账号 token** |
| Kubernetes | Namespace | ServiceAccount | ServiceAccount token |

**Grafana 的 Org ≈ Kubernetes 的 Namespace**：都是硬隔离边界，资源 uid 在边界内唯一。

**Grafana 的服务账号 ≈ K8s 的 ServiceAccount**：都是"给程序用的身份"，都发 token，都可轮换。

有意思的是 **Grafana 的 Team 在 K8s 里没有直接对应**——K8s 通常直接把权限绑给 ServiceAccount 或 User，没有"组"这一层。Grafana 多出这一层，是因为它面向的是**人多、资源杂**的运维场景。

### 与课 10 悬念的呼应

课 10 结尾留了三个悬念，本课逐一回应：

**悬念 1：`managedBy=classic-file-provisioning` 与权限的关系**

本课没直接测（资源有限），但从 `permission` 表的结构能推断：provisioning 建的资源在 RBAC 里**同样是普通资源**，权限可以单独授予。不过——**下次重启文件会把它覆盖回去**，权限改动如果不在文件里就会丢。这条留待你实操验证。

**悬念 2：provisioning 写入的资源 `createdBy:"Anonymous"`**

本课坐实了这个现象，并在 `folder` 表看到同样的模式：

```
TeamA-Folder:  createdBy="admin"   updatedBy="Anonymous"
```

**新建时记了作者，更新时丢了。** 审计时确实查不到真实作者。

服务账号能部分缓解：程序用服务账号操作，至少知道"是 CI 干的"，而不是"Anonymous"。但**这不能替代审计日志**（Grafana 的审计功能在企业版/更高版本）。

**悬念 3：两个同名文件夹怎么授权**

本课没直接测，但机制清楚了：授权是按 **uid**（`/api/folders/{uid}/permissions`），不是按名字。所以**同名不是问题，uid 才是**——但 UI 上只显示名字，选错的风险是真实的。

**规避办法**：给文件夹起不同的显示名，或者记住 uid。

### 阶段 4 的位置

```
课 10：配置从哪来（Provisioning）  ✅
课 11：谁能动它（权限）              ✅ 本课
课 12：它挂了怎么办（高可用与运维）   ← 下一课
```

### 课 12 的伏笔

本课留下三个跟课 12 相关的问题：

1. **权限存哪**：本课的 `permission` 表在 SQLite 里。课 12 讲换 Postgres 时，这些表会一起迁移——**权限配置的备份比 dashboard 更重要**（丢了等于所有人权限重配）。

2. **`permission` 表有 92 张表里的角色定义**：`role_id` 指向预置角色（本课看到 role_id 1-5）。升级时这些**可能变化**，课 12 的"升级前查什么"会回到这里。

3. **服务账号 token 明文只存一次**：备份数据库**恢复不了 token**（只存哈希）。所以升级/迁移后，所有程序访问**都要重新发 token**。这是课 12 备份清单里必须写的一条。

---

## ✅ 本课小结

| 知识点 | 一句话 | 判据 |
|---|---|---|
| 11.1 Org | 最硬的边界，跨 Org 读资源返回 **404**（装作不存在） | `Dashboard not found` |
| 11.1 User | 新建默认 **Viewer**；角色是 User×Org 的二元关系 | `org_user` 表 (org_id, user_id, role) |
| 11.1 Team | **只归堆不授权**；建团队时创建者自动成 Team Admin | dave 加入前后权限不变 |
| 11.2 两道闸门 | 角色给"动作权限"，文件夹给"资源范围"，**都要过** | 两种 403 错误信息不同 |
| 11.2 权限级别 | View=1 / Edit=2 / Admin=4 | `permissionName` |
| 11.2 继承 | `inherited: true` = 从父文件夹继承 | 改父会波及子 |
| 11.2 `hasAcl` | **恒 false，不可信**（表里没这列） | `folder` 表无 `has_acl` |
| 11.2 `folderUid` | 必须放 **payload 顶层**，否则落 General（仍返回 200） | 三种写法对照 |
| 11.3 服务账号 | 有 login/uid、可多令牌、可单个吊销 | `sa-1-ci-bot`、`glsa_` |
| 11.3 token | **明文只出现一次**，只存哈希 | 列 token 无 `key` |
| 11.3 API Key | **接口已移除**，仅剩 `api_key` 遗留表 | 三路径 404 + 表仍在 92 张中 |
| 11.3 最小权限 | 服务账号 Viewer 写操作被精确拒 | `dashboards:create` / `org.users:read` 403 |

---

## 🎓 本课小测

### 选择题（单选）

**1. 把用户加入一个 Team 后，他会获得什么？**

- A. Team 被授予的所有权限
- B. 与 Team 同名的角色
- C. **什么权限都不会自动获得**
- D. Team 创建者的部分权限

<details><summary>答案</summary>

**C**。实测：dave 加入 TeamBGroup 后权限列表完全不变（`dashboards:read, folders:read`）。权限来自 **Team + 资源 + 级别**这条授权记录，Team 成员资格本身不带权限。

</details>

**2. 想判断一个文件夹有没有配权限，应该看什么？**

- A. `GET /api/folders/{uid}` 返回的 `hasAcl`
- B. **`GET /api/folders/{uid}/permissions` 的记录**
- C. 文件夹的 `version` 字段
- D. 文件夹的 `canEdit` 字段

<details><summary>答案</summary>

**B**。`hasAcl` 是遗留字段，恒为 `false`——`folder` 表里根本没有 `has_acl` 这一列。实测给了 Edit 权限后 `hasAcl` 仍是 `false`，但写入测试证明权限生效了。

</details>

**3. 关于 API Key（Grafana 13.2.1），正确的是？**

- A. 用 `POST /api/auth/keys` 可以创建
- B. 用 `POST /api/apikeys` 可以创建
- C. **HTTP 接口已全部移除，但 `api_key` 表还在**
- D. 与服务账号完全等价

<details><summary>答案</summary>

**C**。实测三个路径（`/api/auth/keys`、`/api/apikeys`、`/api/org/apikeys`）全部 404，但数据库 92 张表里仍有 `api_key` 表（且本课实例中有 1 行遗留数据）。

</details>

**4. 建 dashboard 时想指定文件夹，正确写法是？**

- A. `{"dashboard":{"folderUid":"teama"}}`
- B. `{"dashboard":{...},"folderUid":"teama"}`
- C. `{"dashboard":{"folderId":123}}`
- D. `{"dashboard":{...},"meta":{"folderUid":"teama"}}`

<details><summary>答案</summary>

**B**。`folderUid` 必须放在 **payload 顶层**。放在 dashboard 内部（A）会**返回 200 但落到 General**——这是本课最隐蔽的坑，因为它不报错。`folderId`（C）同样无效。

</details>

### 判断题

**5. 跨 Org 访问另一个组织的 dashboard，会返回 403 Permission denied。**

<details><summary>答案</summary>

**错**。返回 **404 `Dashboard not found`**。Grafana 故意"装作不存在"，不泄露资源的存在性。跨 Org 的**写**操作才是 403。

</details>

**6. 服务账号的 token 忘了，可以在列表接口里再查一次明文。**

<details><summary>答案</summary>

**错**。Grafana 只存 token 的哈希，**明文只在创建响应里出现一次**。列表接口只有元数据（name/created/lastUsedAt/isRevoked），没有 `key`。忘了只能吊销重发。

</details>

### 思考题

**7.** 你的团队有 8 个人，分两个小组各管一批 dashboard。既要互不干扰，又要能看对方的面板做排查。用本课的知识怎么设计？

<details><summary>参考思路</summary>

**结构**：一个 Org（不需要多 Org——多 Org 是完全隔离，不是分组）、两个 Team、两个文件夹。

**授权**：
- 组 A 的 Team → 文件夹 A 授 **Edit(2)**
- 组 A 的 Team → 文件夹 B 授 **View(1)**（能看不能改）
- 组 B 同理，镜像配置

**注意三点**：
1. 所有人 Org 角色保持 **Viewer**，权限全靠文件夹给——这样最干净
2. 别用嵌套文件夹，或者用了就要注意 `inherited: true` 的继承，改父会波及子
3. 验证时**别看 `hasAcl`**（恒 false），直接拿一个成员账号做一次写入测试

</details>

---

## 📚 延伸阅读

- [Grafana 权限总览](https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/)
- [Grafana 服务账号](https://grafana.com/docs/grafana/latest/administration/service-accounts/)

---

## 🔍 评审结论（对学员可见）

| 项 | 内容 |
|---|---|
| 评审方式 | 主 agent 内联（pedagogy + learner 双视角，子 agent 未创建，独立性受限） |
| P0 数 | **0** |
| P1 数 | 3（已修，见下） |

**P1×3 已修**：

1. **阶段概览表述需修正**：`4-管得住/overview.md` 写「改权限最容易踩的坑是"给了文件夹权限忘了给 dashboard 权限"」。实测恰恰相反——文件夹 Edit 会**顺带授予** `dashboards:create`，真正的漏配是"只给 Viewer 角色又想让人改"。已在 11.2 误区 1 明确指出。
2. **`folderUid` 位置错误导致的误判**：初测 carol 得 403 时，差点写成"文件夹权限没生效"。排查后发现是 `folderUid` 放错了位置（返回 200 但落 General）。已单列为第四幕"坑 3"并给出三种写法对照。
3. **`hasAcl` 差点被当作有效判据**：初见 `hasAcl=false` 时怀疑"设权限失败"。追到数据库发现 `folder` 表无 `has_acl` 列，确认为遗留字段。已在第二幕冲突 3 与 11.2 误区 2 双处说明。

**评审中判定为脚本/环境问题、未改文档×4**：

1. `GET /api/teams`、`GET /api/serviceaccounts`、`GET /api/users?loginOrEmail=` 三个接口的响应形态与预期不同（404 / 列表而非对象）→ 改用 `/search` 后缀与按 id 访问，属 API 形态差异非文档缺陷
2. `GET /api/access-control/teams/{id}/roles` 等 RBAC 管理接口 404 → 未影响结论，权限验证改走 `/api/access-control/user/permissions` + 行为测试
3. 服务账号 id 猜测错误（用 1 实为 6）→ 从响应取实际 id
4. `l11-sa.sh` 中 `dave` 建 token 前 id 未定 → 改为落盘脚本顺序执行

**自我纠错 2 处**：

1. 初判"carol 能写未授权文件夹 = 权限失控"，实为她当时仍是 Editor 角色（时序问题），干净用户 dave 对照后修正
2. 初判"Team 成员资格自带权限"，实为授权记录的作用，dave 加入 Team 前后对照后修正

**课 4 P0 未复发**：本课命令全部落盘为脚本执行，代码块外 0 处反斜杠续行，PowerShell 兼容。

---

## 🚀 下一课接力提示词

```
继续学 Grafana。我的学习档案在 grafana/00-学习档案.md，
刚学完阶段 4《管得住》的课 11《权限与服务账号：谁能看、谁能改、程序怎么访问》
知识点 11.1（Org / User / Team 三层模型）、
11.2（RBAC 与文件夹权限）、
11.3（服务账号与 API Key：程序怎么安全访问），
请按大纲继续讲解课 12《性能、高可用与升级运维》
（知识点：性能：面板数量、查询并发与渲染压力 /
  数据库后端与高可用部署 / 升级与备份：升级前查什么、回滚靠什么）。
```

**课 12 需要复用本课环境**：`grafana-prov`(3002) 上有本课建的全部权限实验资产。

**本课新增的环境资产**（课 12 可复用）：

| 资产 | 值 |
|---|---|
| 组织 | Org 1 `Main Org.`、Org 2 `TeamB` |
| 用户 | `alice`(2)/`bob`(3)/`carol`(4)/`dave`(5)，均 Viewer；`admin`(1) |
| 团队 | `OpsTeam`(1)、`TeamBGroup`(2) |
| 文件夹 | `teama`(TeamA-Folder)、`teamb`(TeamB-Folder)、`provfolder`、`dfxhsw8b57pxcd` |
| 服务账号 | `ci-bot`(id=6, login `sa-1-ci-bot`)，token `ci-token-1` |
| 数据库快照 | `/tmp/l11-grafana.db`（92 张表，含 `permission`/`api_key`） |

**留给课 12 的三个悬念**

1. **`permission` 表在 SQLite 里**：课 12 讲换 Postgres 时，权限配置如何一起迁移？丢了等于全员权限重配
2. **`role_id` 指向预置角色**（本课看到 role_id 1-5）：升级时这些定义会不会变？
3. **token 只存哈希**：备份恢复后所有程序访问都要重新发 token——这条必须进课 12 的备份清单

---

## 课程导航

- **上一课**：[第 10 课：Provisioning](./lesson-10-Provisioning：把点击变成配置文件.md)
- **下一课**：[第 12 课：性能、高可用与升级运维](./lesson-12-性能、高可用与升级运维.md)
- **阶段概览**：[阶段 4：管得住](../overview.md)
- **课程目录**：[02-课程目录](../../../02-课程目录.md)
- **学习路径**：[01-学习路径总览](../../../01-学习路径总览.md)
- **学习档案**：[00-学习档案](../../../00-学习档案.md)

---

## 📌 速览卡片

| 问题 | 答案 |
|---|---|
| Org 是什么 | 租户，**硬隔离**；跨 Org 读 → **404**（装作不存在） |
| User 默认角色 | **Viewer**（不是"无权限"） |
| 角色归属 | **User × Org** 二元关系，同一人在不同 Org 角色可不同 |
| Team 带权限吗 | **不带**。只是人的集合，权限来自授权记录 |
| 建 Team 副作用 | 创建者自动成 **Team Admin**（`permission: 4`） |
| 三种权限级别 | View=1 / Edit=2 / Admin=4 |
| 两道闸门 | 角色给**动作权限**，文件夹给**资源范围**，都要过 |
| 两种 403 怎么分 | `Permissions needed:` = 角色不够；`is forbidden: access denied to folder` = 文件夹没授权 |
| `hasAcl` 可信吗 | **不可信，恒 false**（`folder` 表无此列） |
| `folderUid` 放哪 | **payload 顶层**，放 dashboard 内会落 General（仍返回 200） |
| 服务账号 login | 自动生成 `sa-{id}-{name}`，id 从响应取 |
| token 前缀 | `glsa_`；**明文只出现一次**（只存哈希） |
| API Key 现状 | **接口已移除**，仅剩 `api_key` 遗留表 |
| 服务账号最小权限 | Viewer 的写操作被精确拒（`dashboards:create`、`org.users:read` 403） |
| 权限真身 | `permission` 表，k8s 风格 scope（`{group}/{resource}:{verb}`） |
