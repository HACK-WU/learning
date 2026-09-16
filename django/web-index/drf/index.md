# DRF（Django REST Framework）网页索引

> 起始 URL：https://www.django-rest-framework.org/
> 生成日期：2026-09-16 · 范围（scope）：全站，排除 `/community/` 版本公告 · 条目数：44 · 一次性快照
> 版本基线：本机课程环境实测 **DRF 3.18.0**（该站文档不分版本，滚动更新）
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| api-guide | [topics/api-guide.md](./topics/api-guide.md) | 28 | 序列化器、视图/视图集、认证、权限、限流、过滤、分页、路由、异常、测试 |
| topics-tutorial | [topics/topics-tutorial.md](./topics/topics-tutorial.md) | 16 | DRF 官方快速上手、6 篇循序渐进教程、文档生成、可浏览 API |

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 写序列化器、字段校验与嵌套 | [Serializers](https://www.django-rest-framework.org/api-guide/serializers/) | api-guide |
| 查序列化器字段类型与参数 | [Fields](https://www.django-rest-framework.org/api-guide/fields/) | api-guide |
| 用 ModelViewSet 快速写 CRUD | [Viewsets](https://www.django-rest-framework.org/api-guide/viewsets/) | api-guide |
| 用 router 自动生成 URL | [Routers](https://www.django-rest-framework.org/api-guide/routers/) | api-guide |
| 配置认证方式（JWT/Session/Token） | [Authentication](https://www.django-rest-framework.org/api-guide/authentication/) | api-guide |
| 配置权限（IsAuthenticated 等） | [Permissions](https://www.django-rest-framework.org/api-guide/permissions/) | api-guide |
| 配置限流（防刷） | [Throttling](https://www.django-rest-framework.org/api-guide/throttling/) | api-guide |
| 做过滤、搜索与排序 | [Filtering](https://www.django-rest-framework.org/api-guide/filtering/) | api-guide |
| 做分页 | [Pagination](https://www.django-rest-framework.org/api-guide/pagination/) | api-guide |
| 查 DRF 的 settings 配置项 | [Settings](https://www.django-rest-framework.org/api-guide/settings/) | api-guide |
| 自定义错误响应与异常码 | [Exceptions](https://www.django-rest-framework.org/api-guide/exceptions/) | api-guide |
| 写 API 测试（APIClient） | [Testing](https://www.django-rest-framework.org/api-guide/testing/) | api-guide |

## 相关站点

- Django 官方索引（同课程）：[../django/index.md](../django/index.md)

## 采集说明

- 来源：sitemap.xml（该站无 llms.txt），抓取脚本退出码 0
- 排除：`/community/` 25 条（3.x 各版本发布公告，与学习无关）
- 保留：`/community/release-notes/` 等 3 条有实际参考价值的内容见 topics-tutorial 分区
- 中间产物：`temp/web-index-drf-map.md`（69 条）
- 锚点列已整体省略：本索引绝大多数条目为整页定位，逐条锚点无实际价值
