# 网页索引登记表（Django 课程）

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文
>
> 本目录归 **Django 系统学习课程** 使用，随课程走（不登记到仓库根 `.web-index/INDEX.md`）

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 | 索引位置 |
|------|------|----------|------|------|----------|----------|
| Django Docs | django | https://docs.djangoproject.com/en/6.1/ | `/en/6.1`，排除 `/releases/` | 279 | 2026-09-16 | [django/index.md](./django/index.md) |
| Django REST Framework | drf | https://www.django-rest-framework.org/ | 全站，排除 `/community/` 公告 | 44 | 2026-09-16 | [drf/index.md](./drf/index.md) |

## 版本基线

| 组件 | 本机实测版本 | 索引 URL 版本段 | 是否一致 |
|------|--------------|-----------------|----------|
| Django | 6.1 | 6.1 | ✅ |
| DRF | 3.18.0 | 文档站不分版本（滚动更新） | ✅ |

> 升级 Django 版本后，`/en/6.1/` 链接不再对应当前环境，需整站重跑重建。

## 使用约定

1. 需要官方文档出处时，先查本目录对应站的「我要…」列定位页面
2. 定位后用 web_fetch 打开该 URL 取细节，**不要把正文抄进索引**
3. 索引是快照，链接大面积失效或 Django 升级版本时整站重跑重建
