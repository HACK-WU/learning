# 阶段 2：采集层 Beats

> ELK 子教程 · 阶段 2 ｜ 课 4-6 ｜ 9 个知识点 ｜ 状态：⬜ 待填充正文（Phase 2）
>
> 前置要求：已完成 [ES 主课](..) 全 5 阶段；本阶段起接触 Logstash / Kibana / Beats 三件套，默认你几乎没用过它们。

## 🎯 阶段目标

一句话回答本阶段的核心问题：**日志怎么才能"拿得到"？**

上一阶段的结尾，你还是那个"线上报警就 ssh 到服务器上 grep 日志"的人。这个阶段，你要用 **Beats 家族**（主力是 **Filebeat**）把散落在各台机器、各条文件里的日志，**自动、断点续传地搬进统一管道**，从此告别手工翻日志。

学完本阶段你应该能：

- 看懂一条日志从"躺在磁盘文件里"到"进入消息管道"的完整路径
- 用 **Filebeat** 把本机日志文件读进来，并理解它为什么"至少投递一次"（可能重复、很少漏）
- 把 Java 异常那类**多行堆栈**正确合并成一条日志
- 用 **modules** 一键接入 nginx / mysql / system 等成熟采集场景
- 用 **processors** 做写入前的轻量字段加工，并把数据正确输出到 ES 或 Logstash
- 面对一个采集需求时，能在 Beats / Logstash / Fluentd / OTel Collector 之间**做出选型判断**，并知道何时该用 Beats、何时不该用

## 📚 必须掌握的知识点清单

| 课 | 知识点 | 一句话 | 状态 |
|----|--------|--------|------|
| [课4 把文件读进来](lessons/lesson-04-Filebeat把文件读进来.md) | harvester 与 input 机制 | 一个文件一个读取器，新版用 `filestream` 替代老 `log` | ⬜ |
| | registry 与 at-least-once | 记下读到哪，重启续读，可能重复、极少漏 | ⬜ |
| | 多行合并 | 用 `pattern`/`negate`/`match` 把异常堆栈拼回一条 | ⬜ |
| [课5 模块与处理器](lessons/lesson-05-模块与处理器.md) | modules 开箱即用 | nginx/mysql/system 一键采集，自带解析与看板 | ⬜ |
| | processors 轻量加工 | 就地增删字段、dissect 拆分、rename，带 `when` 条件 | ⬜ |
| | 输出与背压 | 直连 ES 还是走 Logstash，bulk 批量与失败重试、背压传导 | ⬜ |
| [课6 家族与采集选型](lessons/lesson-06-Beats家族与采集选型.md) | 家族成员各管什么 | Metricbeat/Packetbeat/Heartbeat/Auditbeat/Winlogbeat | ⬜ |
| | 采集端选型对比 | Beats vs Logstash vs Fluentd vs OTel Collector | ⬜ |
| | 什么时候不该用 Beats | 容器/K8s、应用直连 SDK、海量日志的取舍 | ⬜ |

## 🗺️ 本阶段路径图

![阶段 2 采集层 Beats 学习路径图](assets/stage-2-path.svg)

图中可见：本阶段在四阶段主线中的位置，以及课 4 → 课 5 → 课 6 的内部推进顺序。

## 📖 本阶段在故事主线中的章节定位

故事讲的是**一条日志的一生**，全教程分四幕：

1. **看得见全貌**（阶段 1 · 全景与起步）——把 ELK 这套东西摊开给你看，先不深究
2. **拿得到**（本阶段 · 采集层 Beats）——把日志从"躺在文件里"搬进"统一的管道"
3. **看得懂**（阶段 3 · 处理层 Logstash，待交付）——把原始日志解析成结构化、可搜索的字段
4. **留得住、用得上**（阶段 4 · 存储可视化与落地，待交付）——写进 ES、配上 Kibana、在运维中跑起来

本阶段就是**第 2 幕**。主角日志此刻还蜷缩在服务器的日志文件里，等着被 Filebeat 叫醒，开始它"被采集、被加工、被存储、被展示"的一生。

## 🧭 阶段导航

- **上一阶段**：阶段 1 · 全景与起步（待交付，位于 `stages/1-…/overview.md`）
- **下一阶段**：阶段 3 · 处理层 Logstash（待交付，位于 `stages/3-…/overview.md`）
- **阶段内课程**：[课 4](lessons/lesson-04-Filebeat把文件读进来.md) ｜ [课 5](lessons/lesson-05-模块与处理器.md) ｜ [课 6](lessons/lesson-06-Beats家族与采集选型.md)

## 🔧 实操环境速记

macOS arm64 / 18GB 内存 / Docker Compose 起全套容器。版本基线 **Elastic Stack 9.5.3**。

- 命令一律 `docker compose exec <服务> …`（如 `docker compose exec filebeat filebeat test config`）
- 涉及 ES 主课的知识点（如写入前加工用的 Ingest Pipeline）按需回看 ES 主课，避免重复展开
