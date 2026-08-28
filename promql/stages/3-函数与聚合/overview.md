# 阶段 3：函数与聚合

> L8 - L10 | 掌握日常 80% 的查询套路

## 阶段目标

学完本阶段，你能回答：

- Counter 怎么正确变成速率：rate/irate/increase 三兄弟各管什么、为什么只对 Counter 有意义
- 几十行明细怎么压成几行汇总：sum/avg/topk 聚合与 by/without 的分组维度
- 「95% 的请求有多快」怎么从桶里算出来：histogram_quantile 与分位数

## 本阶段课程

| 课次 | 主题 | 状态 |
|------|------|------|
| L8 | rate/irate/increase：Counter 的正确打开方式 | ✅ |
| L9 | 聚合全家桶：sum/avg/topk 与 by/without | ✅ |
| L10 | histogram_quantile：算出 P95 延迟 | 🔄 |

## 阶段通关标准

独立完成：给定 Counter、Gauge、Histogram 各一个业务指标，能选出正确的函数查出「每秒速率、按维度聚合的汇总值、P95 延迟」，并能说清每个函数吃什么数据形态、吐什么结果。
