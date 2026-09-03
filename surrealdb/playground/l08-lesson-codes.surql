// ============================================================
// 课 8《实时：LIVE 与 EVENT》练习参考答案
// ------------------------------------------------------------
// 用法（WS 连接，LIVE 在 HTTP /sql 上不支持）：
//   surreal sql --conn ws://127.0.0.1:8000 --user root --pass root \
//       --ns learn --db kp8 --pretty < l08-lesson-codes.surql
//
// ⚠️ 必须用 ws:// ：LIVE SELECT 走 HTTP 会报 LiveQueryNotSupported。
// ⚠️ 本文件是「答案」，建议先自己写一遍再来看。
// ⚠️ [1][2][6] 三节会 DEFINE EVENT / LIVE，会写脏 kp8 库；
//    反复练习前先跑第 [0] 节的清理语句。
// ============================================================

USE NS learn;
USE DB kp8;

// --- [0] 重来一次：清掉本课用到的表（事件随表一起删）---
REMOVE TABLE IF EXISTS product;
REMOVE TABLE IF EXISTS price_history;
REMOVE TABLE IF EXISTS post;
REMOVE TABLE IF EXISTS archive;
REMOVE TABLE IF EXISTS order;
REMOVE TABLE IF EXISTS audit;


// ============ 练习 1（8.1）：LIVE 的 WHERE 是「变更后」过滤 ============

// 建表与初始数据
DEFINE TABLE product SCHEMALESS;
CREATE product:p1 SET name = 'A', price = 120;
CREATE product:p2 SET name = 'B', price = 80;

// --- 订阅：只接收价格低于 100 的商品变更 ---
LIVE SELECT * FROM product WHERE price < 100;
// 返回的是一个订阅 UUID（不是结果集），后续变更由服务端主动推。
// 注意：订阅瞬间不会补发存量数据——p2 虽然满足 80 < 100，但不会推。

// --- 关键：WHERE 判断的是「变更之后」的那条记录 ---
UPDATE product:p1 SET price = 80;    // 120 → 80  推 ✅ （变更后 80 < 100，满足）
UPDATE product:p1 SET price = 150;   // 80  → 150 不推 ❌（变更后 150 不满足）
UPDATE product:p2 SET price = 90;    // 80  → 90  推 ✅ （变更后 90 仍满足）

// 三问三答：
//   120 → 80   推   变更后满足
//   80  → 150  不推 变更后不满足
//   80  → 90   推   两个状态都满足，是「区间内的更新」不是「跨阈值」
// 对应实测：l08-probe-81g.py 第 4、5、6 组（脚本里用的是 sensor / temp > 50，
//           语义完全相同，只是字段名不同）。

// ⚠️ 订阅开完必须关：连接断开前它会一直占着服务端资源
//    （3.2 只提供了孤儿 LIVE 计数器，没有自动回收）。
//    把上面 LIVE 返回的 UUID 填进下面这行执行；
//    若用 surreal sql 交互模式看不到 UUID，可改写为
//    `LET $uid = (LIVE SELECT ...)` 再 `KILL $uid;`。
KILL <填上面 LIVE 返回的 UUID>;

// 💡 这条练习的真正考点：如果你想做的是「价格跌破 100 就告警一次」，
//    LIVE 的 WHERE 做不到——它只能回答「现在还满足吗」。
//    「阈值跨越」是 EVENT 的活（见练习 5 与陷阱清单第 3 条）。

// 订阅用完记得 KILL，否则连接断开前它会一直占着（3.2 只提供计数器，不自动回收）：
//   KILL <上面返回的 UUID>;


// ============ 练习 2（8.1）：如何区分 CREATE 与 DELETE ============

// --- 先看原始通知长什么样（5 个字段）---
// 用原始 WebSocket JSON-RPC 订阅（推荐做法，参考 l08-probe-81d.py）：
//
//   {"id":"1","method":"subscribe_live","params":["<上面 LIVE 返回的 UUID>"]}
//
// 收到的推送形如：
//   {
//     "result": {
//       "id":      "f4a1...",                    // 订阅 UUID
//       "action":  "CREATE",                     // ← 区分动作靠这个字段
//       "record":  "product:p1",                 // 变化的记录 ID
//       "result":  { "id":"product:p1", ... },   // 变更后的完整内容
//       "session": "c2e1..."                     // 产生变更的会话（用来跳过自己的回环）
//     }
//   }
//
// --- 为什么 Python SDK 的 subscribe_live() 不行 ---
// SDK 只把 result.result 透传出来，action 被丢掉了，而且不报错。
// 这是本课 P0 级发现（陷阱清单第 1 条）。三条出路：
//   1. 改用原始 WS JSON-RPC，自己解析 5 个字段（推荐）
//   2. 设计上避开：只用 UPDATE，删除改成写 deleted: true 标记位
//   3. 订阅端维护本地快照，收到通知后比对 ID 是否存在（能推断，但很笨）


// ============ 练习 3（8.2）：递归炸弹与守卫条件 ============

DEFINE TABLE post SCHEMALESS;
CREATE post:p1 SET title = 'T1';

// --- 错误写法：THEN 里改自己 → 无限递归 ---
// ⚠️ 下面这段不要直接跑进正式练习库，它会把主写入一起回滚。
//    想看效果请单独建表（如 post_bad）试，跑完 REMOVE TABLE post_bad;
//
// DEFINE EVENT ev_touch_bad ON TABLE post WHEN $event = "UPDATE"
//   THEN ( UPDATE $this SET updated_at = time::now() );
//
// 后果：UPDATE 又触发同一个事件，实测嵌套 23 层后报
//   Reached excessive computation depth
// 并且——原始 UPDATE 被整体回滚。不是「副作用失败」，是主写入一起没。

// --- 正确写法：加守卫条件 ---
// 守卫条件：只在 title 真的变了才打时间戳（第二次进入时 title 没变 → 递归终止）
DEFINE EVENT ev_touch ON TABLE post
  WHEN $event = "UPDATE" AND $after.title != $before.title
  THEN ( UPDATE $this SET updated_at = time::now() );

UPDATE post:p1 SET title = 'T2';
SELECT * FROM post;
// 实测输出（l08-probe-82g.py）：
//   UPD_TITLE:   [{"id":"post:p1","title":"T2"}]
//   POST_STATE:  [{"id":"post:p1","title":"T2","updated_at":"2026-09-02T11:44:58.429271191Z"}]
// updated_at 写入成功，无递归报错。

// --- 第二次更新（标题不变）应无副作用 ---
UPDATE post:p1 SET price = 9;    // 若表是 SCHEMALESS，这条不再触发 ev_touch

// 💡 更根本的思路：能用 COMPUTED 字段声明式表达，就别用事件去改。
//    事件是命令式的（有递归 + 回滚风险），COMPUTED 是声明式的。
//    ⚠️ 本课未实测 COMPUTED 方案（属课 9 知识点），课 9 会回来验证
//    「用 COMPUTED 自动维护 updated_at」是否真的可行。此处先按守卫条件写。


// ============ 练习 4（8.2）：DELETE 事件要读 $before ============

DEFINE TABLE order SCHEMALESS;
DEFINE TABLE archive SCHEMALESS;
CREATE order:o1 SET amt = 10;

// --- 错误写法：$after 在 DELETE 时是 NONE ---
DEFINE EVENT ev_del_bad ON TABLE order WHEN $event = "DELETE"
  THEN ( CREATE archive SET content = $after, tag = 'bad' );

DELETE order:o1;
SELECT * FROM archive;
// 结果：content 字段直接不出现（静默消失，不报错）。

// --- 正确写法：用 $before ---
CREATE order:o2 SET amt = 20;
REMOVE EVENT ev_del_bad ON TABLE order;

DEFINE EVENT ev_del ON TABLE order WHEN $event = "DELETE"
  THEN ( CREATE archive SET content = $before, tag = 'good' );

DELETE order:o2;
SELECT * FROM archive;
// 实测（l08-probe-82e.py）：日志写入 {"before": {"amt":10,"id":"order:o1"}, "ev":"DELETE"}，
//   after_is_none: true


// ============ 练习 5（8.3）：为什么不能用 LIVE 顶替消息队列 ============

// 场景：「订单创建后通知库存服务扣减」。三条反对理由：
//
// 1. 消费者离线会丢消息。
//    l08-probe-83i.py 实测：离线期间写入 5 条，消费者上线后补发 0 条。
//    库存服务重启一次就少扣几单。LIVE 是「在线者广播」，不是队列。
//
// 2. 多个消费者会重复消费。
//    LIVE 是广播，实测两个订阅者各收一份。起两个库存服务实例，
//    同一笔订单会被扣两次库存（除非自己做幂等）。
//
// 3. 没有 ACK 与重试。
//    LIVE 推完就算完，不管你处理成功没有。处理到一半崩了，通知永久消失。
//
// 附加：LIVE 绑定数据库，库存服务必须直连同一个 SurrealDB，跨服务解耦性弱。
//
// ✅ 正确分工：
//    审计 / 派生数据      → EVENT（同步，强一致，失败会连带回滚主写入）
//    跨服务可靠任务        → 消息队列（ACK / 重试 / 死信 / 削峰）
//    让在线的人看到最新状态 → LIVE（丢了重新 SELECT 一次就好）

// --- 顺带复习正文 8.2 的审计示例（注意 $this.id 不能写成 $this）---
// 练习 1 已经用过 product 表，这里先清掉重来，否则 p1 已存在、
// 起始价格也不是 50，下面这条 UPDATE 的 before/after 就对不上正文。
REMOVE TABLE IF EXISTS product;
REMOVE TABLE IF EXISTS price_history;
DEFINE TABLE product SCHEMALESS;
DEFINE TABLE price_history SCHEMALESS;
CREATE product:p1 SET name = 'A', price = 50;

// ⚠️ 必须写 $after.id（或 $before.id），裸 $this 和 $this.id 都会静默丢字段。
//    这点比正文陷阱清单第 14 条说的更严重，见下方说明。
DEFINE EVENT ev_price_audit ON TABLE product
  WHEN $event = "UPDATE" AND $after.price != $before.price
  THEN ( CREATE price_history SET pid = $after.id,
                                    from = $before.price, to = $after.price );

UPDATE product:p1 SET price = 88;
SELECT * FROM price_history;
// ✅ 正确写法（$after.id）实测输出：
//   [{"from": 50, "id": "price_history:...", "pid": "product:p1", "to": 88}]
// ❌ 裸 $this 与 $this.id 实测输出：
//   [{"from": 50, "id": "price_history:...", "to": 88}]     ← pid 字段整个消失，无报错

// ⚠️⚠️ 比正文陷阱清单第 14 条更严重的一处更正（2026-09-03 复核发现）：
//    正文的对照表把 `$this.id` 列为「✅ 正常」，这是**误判**——
//    原探针 l08-probe-82h.py 在 5 个变体之间从不清空结果表 ph2，
//    判定逻辑又是「只要任意一行有 pid 就算这个变体成功」，
//    于是第一个成功变体（$after.id）的行被后面所有变体复用，全被判成成功。
//
//    逐变体清空结果表后重测（p86-fixed-probe-82h.py）的真实结果：
//      SET pid = $this              ❌ 字段不出现，无报错
//      SET pid = $this.id           ❌ 字段不出现，无报错   ← 正文本来判它为 ✅
//      SET pid = $after.id          ✅ pid = "product:p1"
//      SET pid = $before.id         ✅ pid = "product:p1"
//      SET pid = <字面量>           ✅ pid = "product:p1"
//      SET pid = type::string($this) ✅ 但值是字符串 "NONE"，不是 ID！
//
//    根因（p88-this-semantics.py）：**在 EVENT 的 THEN 里，$this 作「值」时恒为 NONE**
//    ——CREATE / UPDATE / DELETE 三种事件都测了，type::of($this) 一律返回 "none"。
//    但 $this 作「语句目标」时是有效的：实测 `UPDATE $this SET hits = 1` 真的改到了记录。
//    也就是说它只有位置之别，没有类型之别：
//      UPDATE $this SET ...        ✅ 目标位有效（这也是练习 3 递归的成因）
//      SET x = $this / $this.id    ❌ 值位恒为 NONE，静默丢字段
//
//    📌 结论：要拿记录 ID 就写 `$after.id`（DELETE 事件里用 `$before.id`）。
//       不要写裸 `$this`，也不要写 `$this.id`。


// ============ 收尾：清理本课定义的对象 ============
// 顺序：先 REMOVE TABLE（事件随表删），避免残留事件影响别的课。
REMOVE TABLE IF EXISTS product;
REMOVE TABLE IF EXISTS price_history;
REMOVE TABLE IF EXISTS post;
REMOVE TABLE IF EXISTS archive;
REMOVE TABLE IF EXISTS order;
REMOVE TABLE IF EXISTS audit;
// 若前面开了 LIVE 订阅，连接断开即自动销毁；也可用 KILL <uuid> 主动关闭。
