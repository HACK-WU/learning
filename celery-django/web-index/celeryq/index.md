# Celery Docs（stable 5.6）网页索引

> 起始 URL：https://docs.celeryq.dev/en/stable/
> 生成日期：2026-09-10 · 范围（scope）：/en/stable（课程基线 Celery 5.6.3；sitemap 不含子页，清单来自 5 个导航页爬取；已排除 internals/ 49 条与 search/genindex/py-modindex 索引页） · 条目数：106 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：Celery + Django 异步任务课程；userguide/tasks、canvas、periodic-tasks 与 django 集成为课程主干

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_celeryq_web_index.py` / `web-index-celeryq-map.md`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 跑通第一个任务（worker+task+delay） | [first-steps-with-celery](https://docs.celeryq.dev/en/stable/getting-started/first-steps-with-celery.html) | getting-started |
| 选 broker 与 result backend（Redis/RabbitMQ） | [backends-and-brokers](https://docs.celeryq.dev/en/stable/getting-started/backends-and-brokers/index.html) | getting-started |
| 查任务定义全套（装饰器/重试/状态/限流） | [userguide/tasks](https://docs.celeryq.dev/en/stable/userguide/tasks.html) | userguide |
| 查调用语义（delay/apply_async/countdown/eta） | [userguide/calling](https://docs.celeryq.dev/en/stable/userguide/calling.html) | userguide |
| 工作流编排（chain/group/chord） | [userguide/canvas](https://docs.celeryq.dev/en/stable/userguide/canvas.html) | userguide |
| 配周期任务（beat/crontab） | [userguide/periodic-tasks](https://docs.celeryq.dev/en/stable/userguide/periodic-tasks.html) | userguide |
| Celery in Django 官方指南 | [django](https://docs.celeryq.dev/en/stable/django/index.html) | django |
| 查配置项权威参考（新旧名字对照） | [userguide/configuration](https://docs.celeryq.dev/en/stable/userguide/configuration.html) | userguide |
| Worker 运维（并发池/远程控制/优雅重启） | [userguide/workers](https://docs.celeryq.dev/en/stable/userguide/workers.html) | userguide |
| 查 FAQ（任务不执行/重复执行类问题） | [faq](https://docs.celeryq.dev/en/stable/faq.html) | about |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| getting-started | [topics/getting-started.md](./topics/getting-started.md) | 6 | 概念/第一步/broker 选型 |
| userguide | [topics/userguide.md](./topics/userguide.md) | 19 | 任务/调用/工作流/定时/路由/Worker/监控 |
| django | [topics/django.md](./topics/django.md) | 1 | Django 集成指南 |
| reference-app | [topics/reference-app.md](./topics/reference-app.md) | 52 | celery.app/result/schedules 等模块 API |
| reference-worker | [topics/reference-worker.md](./topics/reference-worker.md) | 15 | worker/consumer 内部模块 API |
| reference-cli | [topics/reference-cli.md](./topics/reference-cli.md) | 3 | CLI 总入口/pytest/Django Task 扩展 |
| about | [topics/about.md](./topics/about.md) | 10 | FAQ/术语/历史/社区/变更日志 |
