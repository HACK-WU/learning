# 课 6 讲义骨架（待用户确认后填充）
# 五幕结构 + 六要素，与课 1-5 一致

## 课 6：多租户治理与成本

### 第一幕：场景引入
- 主角：集群养稳了（课 1-5），现在来了第二个团队要共用
- 冲突现场（本机实测）：
  - 没有任何 ResourceQuota / LimitRange（kubectl get -A 全空）
  - 40 个 Running Pod 中 18 个 BestEffort、26 个容器无 requests
  - 装箱率 2.77%（1.66核/60核）
- 问题：一个团队写死循环能把整个集群拖垮，且事后无法追责

### 第二幕：认知冲突
- 冲突1：namespace 只是"文件夹"，不是"围墙"（实测：默认无 NetworkPolicy，Pod 间全通）
- 冲突2：装箱率 2.77% 看着很浪费，但真加配额会先"锁死"自己
- 冲突3：requests 是"占座"不是"吃掉"（requests 1.66核 vs 实际 0.44核）

### 第三幕：层层揭示
- 知识点 1：租户隔离四层（namespace / RBAC / NetworkPolicy / ResourceQuota）
- 知识点 2：资源治理（ResourceQuota / LimitRange / QoS 与驱逐）
- 知识点 3：容量与成本（装箱率正确算法 / 请求vs实际 / 成本可见性）

### 第四幕：实操验证（演练 1-5）
- 演练1：建两个租户 namespace + RBAC，验证越权被拒
- 演练2：NetworkPolicy 默认拒绝前后对比（Calico 可真跑）
- 演练3：ResourceQuota 触发 403 的实测
- 演练4：LimitRange 自动注入默认值
- 演练5：装箱率计算与成本归因

### 第五幕：体系收束
- 知识地图（三知识点 + 与课 2/5 的呼应）
- 常见误区（5 条，全部基于实测）
- 一句话记住 / 自测 4 题 / 接力提示词
