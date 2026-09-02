# 实战项目：电商大促数据层

> 所属课程：Redis 系统学习 ｜ 学习目标：动手实操 + 决策参考 ｜ 预计耗时：3-4 小时
> 环境：WSL Ubuntu 24.04 + Redis 8.10.1 + Python 3.12（纯标准库，无需装包）

## 🎯 一句话需求

给一个电商网站搭一套能扛住大促流量的数据层：商品详情走缓存扛读、秒杀库存不超卖、销量实时排行，并且**出问题能查、不该看的看不到**。

## ✅ 目标与非功能约束

**功能目标**

1. 商品详情查询走缓存，把数据库压力降下来，并防住穿透 / 击穿 / 雪崩
2. 秒杀扣库存，500 并发抢 100 件不超卖，且支持一人一单限购
3. 实时销量排行榜与当日统计
4. 自带诊断能力：能查慢查询、大 key、命中率、内存

**非功能约束**（≥2 项，本项目做了 4 项）

| 约束 | 具体指标 | 怎么验证 |
|------|---------|---------|
| 性能 | 商品查询 P50 < 5ms（数据库 20ms） | `main.py` 第一幕：缓存侧实测约 0.12 ms；**提速倍数每次运行不同（本机实测 110 / 129 / 167 倍），看数量级即可** |
| 正确性 | 秒杀不超卖：成功数 + 剩余库存 = 初始库存 | `main.py` 第四幕账目对平校验 |
| 安全 | 应用账号无法执行 KEYS / FLUSHALL / DEBUG / SHUTDOWN，且只能碰业务 key 前缀 | `main.py` 第六幕逐条验证 |
| 可维护性 | 诊断不能比业务更耗资源（大 key 扫描带采样上限） | `diagnostics.py` 的 `sample` 参数 |

## 🗺️ 覆盖知识点地图

> 这是「跨阶段整合」的证据，逐个回指课时。

| # | 知识点 | 所属阶段 / 课 | 本项目用在何处 | 回指 |
|---|--------|--------------|---------------|------|
| 1 | key 设计与过期 | 阶段 1 · 课 2 | `cache_layer.py` 统一 `cache:good:{id}` 命名 | [lesson-02](../../stages/1-为什么需要Redis/lessons/lesson-02-跑起来第一个Redis.md) |
| 2 | Hash 存对象 vs String 存 JSON | 阶段 2 · 课 3 | 商品对象用 Hash 存，支持只改 price 字段 | [lesson-03](../../stages/2-数据结构与命令/lessons/lesson-03-List与Hash.md) |
| 3 | Hash 原子字段增减 | 阶段 2 · 课 3 | `inventory.py` 的 `DailyStats` 用 HINCRBY | [lesson-03](../../stages/2-数据结构与命令/lessons/lesson-03-List与Hash.md) |
| 4 | ZSet 跳表 + 哈希表双结构 | 阶段 2 · 课 4 | 销量排行榜 `rank:sales`，TopN 用 ZREVRANGE | [lesson-04](../../stages/2-数据结构与命令/lessons/lesson-04-Set、ZSet与特殊类型.md) |
| 5 | Set 去重 | 阶段 2 · 课 4 | 秒杀一人一单，用 `inventory:buyers:{gid}` Set | [lesson-04](../../stages/2-数据结构与命令/lessons/lesson-04-Set、ZSet与特殊类型.md) |
| 6 | 持久化选型 | 阶段 3 · 课 5 | 主库开 AOF everysec + RDB 快照 | [lesson-05](../../stages/3-持久化与高可用/lessons/lesson-05-RDB与AOF持久化.md) |
| 7 | 全量与增量复制 | 阶段 3 · 课 6 | 7201 主 + 7202 从，实测复制握手 | [lesson-06](../../stages/3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md) |
| 8 | 从库只读 | 阶段 3 · 课 6 | `main.py` 第七幕验证从库写入被拒 | [lesson-06](../../stages/3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md) |
| 9 | 集群下 Lua 的 key 限制 | 阶段 4 · 课 7 | 两个 Lua 脚本都只用 1-2 个 key，天然同槽 | [lesson-07](../../stages/4-分布式与生产实践/lessons/lesson-07-分片与集群.md) |
| 10 | Lua 原子性 | 阶段 4 · 课 7 | 扣库存「判断+扣减」一步完成，杜绝超卖 | [lesson-07](../../stages/4-分布式与生产实践/lessons/lesson-07-分片与集群.md) |
| 11 | 缓存穿透 | 阶段 4 · 课 8 | 空值标记 `cache:empty:{gid}` | [lesson-08](../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md) |
| 12 | 缓存击穿 | 阶段 4 · 课 8 | 互斥锁 `cache:lock:{gid}`，30 并发只回源 1 次 | [lesson-08](../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md) |
| 13 | 缓存雪崩 | 阶段 4 · 课 8 | TTL 加 0~120 秒随机抖动 | [lesson-08](../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md) |
| 14 | 缓存与数据库一致性 | 阶段 4 · 课 8 | Cache Aside：先更库再删缓存，并演示脏数据反面 | [lesson-08](../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md) |
| 15 | 内存淘汰策略 | 阶段 4 · 课 8 | 主库 `allkeys-lru` | [lesson-08](../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md) |
| 16 | 性能诊断四层模型 | 阶段 4 · 课 9 | `diagnostics.py` 整体→命令→慢查询→具体 key | [lesson-09](../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md) |
| 17 | 慢查询日志 | 阶段 4 · 课 9 | 5.3 节，并说明「慢查询为空 ≠ 用户不慢」 | [lesson-09](../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md) |
| 18 | 大 key / 热 key | 阶段 4 · 课 9 | 5.4 / 5.5 节，含 LFU 未启用时的正确应对 | [lesson-09](../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md) |
| 19 | 安全与运维基线（ACL） | 阶段 4 · 课 9 | 三个角色账号 + default off，第六幕逐条验证 | [lesson-09](../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md) |
| 20 | 生态与选型（含许可证变迁） | 阶段 4 · 课 9 | 本项目选型 Redis 8.10.1 的理由与替代方案权衡，见 [设计决策.md](设计决策.md) 决策 6 | [lesson-09](../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md) |

**跨阶段校验**：覆盖 4 个阶段（门槛 ≥3）✅

## 🚀 运行方式

> 本项目在 **WSL** 里跑（Windows 侧无 Redis）。两个脚本都要执行，顺序不能反：
> 第一个负责起实例，第二个负责建 ACL 角色账号——**只跑第一个会因为权限不足而失败**。

**Windows（PowerShell）下执行**：

```powershell
$env:WSLENV=""; & "C:\Windows\System32\bash.exe" -c "bash /mnt/d/projects/learning/redis/playground/prep-final-project-start.sh"
$env:WSLENV=""; & "C:\Windows\System32\bash.exe" -c "bash /mnt/d/projects/learning/redis/playground/prep-final-project-rebuild.sh"
$env:WSLENV=""; & "C:\Windows\System32\bash.exe" -c "cd /mnt/d/projects/learning/redis/projects/电商大促数据层/实现 && python3 main.py"
```

**已在 WSL 内时**：

```bash
# 1) 启动三个实验实例（7201 主 / 7202 从 / 7203 反例）
bash playground/prep-final-project-start.sh
bash playground/prep-final-project-rebuild.sh   # 建 ACL 角色账号（必做）

# 2) 跑起来
cd projects/电商大促数据层/实现
python3 main.py
```

**预期耗时**：起实例约 5 秒；`main.py` 约 15 秒（第一幕要模拟 100 次 20ms 的数据库查询）。

> 💡 如果遇到 `NOAUTH Authentication required` → 说明第 2 个脚本没跑，回去执行 `prep-final-project-rebuild.sh`。
> 如果遇到 `Connection refused` → 实例没起来，检查 `/tmp/redis-final/7201/redis.log`。
> 如果看到 `master_link_status:down` → **等 5 秒再看**。rebuild 会重启主库，从库需要几秒完成重连与全量同步，
> 这是正常时序，不是故障。确认方法：`redis-cli -p 7202 INFO replication`，正常应为 `up`。

**预期结果**：七幕演示全部跑完，关键结论行如下

```
第一幕  >>> 提速约 110~170 倍（波动值，看数量级即可；稳定的指标是缓存侧单次约 0.12 ms）
第二幕  ✓ 穿透防护生效：数据库只被打了 1 次
        ✓ 击穿防护生效：30 个并发只回源 1 次
        ✓ TTL 已分散，不会在同一秒集体失效
第三幕  ✓ 一致：删除缓存后重新回源，读到新值
第四幕  ✓ 无超卖：成功数与剩余库存账目完全对平
第六幕  KEYS * / FLUSHALL / DEBUG SLEEP 全部被拒绝
第七幕  ✓ 从库只读，符合预期
```

> ⚠️ 环境说明：本项目跑在 **7201 / 7202 / 7203** 三个独立端口的临时实例上，
> 不碰你本机的 6379。实例数据与配置都在 `/tmp/redis-final/` 下，重启机器即清空。

## 📁 目录说明

| 路径 | 内容 |
|------|------|
| `设计决策.md` | 6 个权衡点的完整论证 + 本轮实测 7 个踩坑清单 |
| `反例对照.md` | 5 组"能跑但很糟"的写法 + 逐条对比 |
| `实现/redislib.py` | RESP2 客户端 + 安全基线连接入口 |
| `实现/cache_layer.py` | 缓存层：Cache Aside + 穿透/击穿/雪崩防护 |
| `实现/inventory.py` | 库存与排行榜：Lua 原子扣减 + ZSet |
| `实现/diagnostics.py` | 诊断层：四层模型的可观测工具 |
| `实现/main.py` | 主程序，串起七幕演示 |
| `验收清单.md` | 自测项，逐项勾选 |
