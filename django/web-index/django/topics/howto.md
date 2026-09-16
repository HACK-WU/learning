# 操作指南 How-to（Django Docs · 共 38 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：部署、静态文件、自定义扩展点、数据迁移与升级

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查 how-to 总目录 | [How-to 总览](https://docs.djangoproject.com/en/6.1/howto/) | howto、指南、总览 |
| 通过 Web 服务器传递 REMOTE_USER 做单点 | [Auth remote user](https://docs.djangoproject.com/en/6.1/howto/auth-remote-user/) | SSO、REMOTE_USER、中间件 |
| 配置 CSP 响应头 | [CSP](https://docs.djangoproject.com/en/6.1/howto/csp/) | CSP、安全头 |
| 排查 CSRF 校验失败（含 Ajax） | [CSRF](https://docs.djangoproject.com/en/6.1/howto/csrf/) | CSRF、403、Ajax |
| 自定义文件存储后端 | [自定义存储](https://docs.djangoproject.com/en/6.1/howto/custom-file-storage/) | storage、S3、自定义 |
| 注册自定义字段查找（lookup） | [自定义查找](https://docs.djangoproject.com/en/6.1/howto/custom-lookups/) | lookup、__自定义 |
| 写自定义管理命令 | [自定义命令](https://docs.djangoproject.com/en/6.1/howto/custom-management-commands/) | management、命令、crontab |
| 自定义模型字段 | [自定义字段](https://docs.djangoproject.com/en/6.1/howto/custom-model-fields/) | Field、自定义字段 |
| 自定义 shell 启动逻辑 | [自定义 shell](https://docs.djangoproject.com/en/6.1/howto/custom-shell/) | shell、自定义 |
| 自定义模板引擎后端 | [自定义模板后端](https://docs.djangoproject.com/en/6.1/howto/custom-template-backend/) | 模板引擎、backend |
| 写自定义模板标签与过滤器 | [自定义模板标签](https://docs.djangoproject.com/en/6.1/howto/custom-template-tags/) | 标签、过滤器 |
| 从项目里安全删除一个 app | [删除 app](https://docs.djangoproject.com/en/6.1/howto/delete-app/) | 删除应用、清理 |
| 查部署总入口 | [部署](https://docs.djangoproject.com/en/6.1/howto/deployment/) | 部署、上线 |
| 用 ASGI 部署（异步） | [ASGI](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/) | ASGI、异步部署 |
| 用 Daphne 部署 | [Daphne](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/daphne/) | Daphne |
| 用 Granian 部署（ASGI） | [Granian ASGI](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/granian/) | Granian |
| 用 Hypercorn 部署 | [Hypercorn](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/hypercorn/) | Hypercorn |
| 用 Uvicorn 部署 | [Uvicorn](https://docs.djangoproject.com/en/6.1/howto/deployment/asgi/uvicorn/) | Uvicorn |
| 上线前过一遍官方检查清单 | [部署检查清单](https://docs.djangoproject.com/en/6.1/howto/deployment/checklist/) | 检查清单、上线、安全 |
| 用 WSGI 部署（同步） | [WSGI](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/) | WSGI、同步部署 |
| 用 Apache + mod_wsgi 做外部认证 | [Apache auth](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/apache-auth/) | Apache、认证 |
| 用 Granian 部署（WSGI） | [Granian WSGI](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/granian/) | Granian |
| 用 Gunicorn 部署 | [Gunicorn](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/gunicorn/) | Gunicorn、生产部署 |
| 用 mod_wsgi 部署 | [mod_wsgi](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/modwsgi/) | mod_wsgi、Apache |
| 用 uWSGI 部署 | [uWSGI](https://docs.djangoproject.com/en/6.1/howto/deployment/wsgi/uwsgi/) | uWSGI |
| 配置错误上报（邮件/哨兵） | [错误上报](https://docs.djangoproject.com/en/6.1/howto/error-reporting/) | 错误、上报、Sentry |
| 提供初始数据（fixture） | [初始数据](https://docs.djangoproject.com/en/6.1/howto/initial-data/) | fixture、初始数据 |
| 接入遗留数据库 | [遗留数据库](https://docs.djangoproject.com/en/6.1/howto/legacy-databases/) | inspectdb、老库 |
| 配置日志 | [日志](https://docs.djangoproject.com/en/6.1/howto/logging/) | 日志、配置 |
| 从旧邮件 API 迁移到新邮件 API | [邮件 API 迁移](https://docs.djangoproject.com/en/6.1/howto/mailers-migration/) | 邮件、迁移、升级 |
| 导出 CSV | [输出 CSV](https://docs.djangoproject.com/en/6.1/howto/outputting-csv/) | CSV、导出、流式 |
| 导出 PDF | [输出 PDF](https://docs.djangoproject.com/en/6.1/howto/outputting-pdf/) | PDF、ReportLab |
| 覆盖第三方 app 的模板 | [覆盖模板](https://docs.djangoproject.com/en/6.1/howto/overriding-templates/) | 模板覆盖、定制 |
| 管理静态文件（开发） | [静态文件](https://docs.djangoproject.com/en/6.1/howto/static-files/) | 静态文件、STATIC_URL |
| 部署静态文件（生产） | [静态文件部署](https://docs.djangoproject.com/en/6.1/howto/static-files/deployment/) | collectstatic、CDN |
| 升级 Django 版本 | [升级版本](https://docs.djangoproject.com/en/6.1/howto/upgrade-version/) | 升级、版本迁移 |
| 在 Windows 上跑 Django | [Windows](https://docs.djangoproject.com/en/6.1/howto/windows/) | Windows、本机环境 |
| 手写 migration | [编写 migrations](https://docs.djangoproject.com/en/6.1/howto/writing-migrations/) | migration、手写、数据迁移 |
