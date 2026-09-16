# HTTP 层主题讲解（Django Docs · 共 22 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：与 http-views 分区互补——这里讲用法与流程，那边查 API 细节

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查 HTTP 层主题总入口 | [HTTP 总览](https://docs.djangoproject.com/en/6.1/topics/http/) | HTTP、请求、总览 |
| 用视图装饰器限流/限制方法 | [Decorators](https://docs.djangoproject.com/en/6.1/topics/http/decorators/) | require_http_methods、gzip |
| 处理文件上传表单 | [File uploads](https://docs.djangoproject.com/en/6.1/topics/http/file-uploads/) | 上传、FileField、表单 |
| 用内置通用视图简化代码 | [Generic views](https://docs.djangoproject.com/en/6.1/topics/http/generic-views/) | 通用视图、ListView |
| 写自定义中间件 | [Middleware](https://docs.djangoproject.com/en/6.1/topics/http/middleware/) | 中间件、编写、顺序 |
| 用 session 存用户状态 | [Sessions](https://docs.djangoproject.com/en/6.1/topics/http/sessions/) | session、会话、登录态 |
| 用 shortcut（render/redirect/get_object_or_404） | [Shortcuts](https://docs.djangoproject.com/en/6.1/topics/http/shortcuts/) | render、redirect、404 |
| 配置 URLconf 与命名空间 | [URLs](https://docs.djangoproject.com/en/6.1/topics/http/urls/) | URL、namespace、path |
| 写视图函数（主题讲解） | [Views](https://docs.djangoproject.com/en/6.1/topics/http/views/) | 视图函数、HttpResponse |
| 查主题文档总目录 | [主题总览](https://docs.djangoproject.com/en/6.1/topics/) | 主题、总览、目录 |
| 从零理解类视图怎么用 | [CBV intro](https://docs.djangoproject.com/en/6.1/topics/class-based-views/intro/) | 类视图、入门 |
| 查类视图主题总入口 | [CBV 主题](https://docs.djangoproject.com/en/6.1/topics/class-based-views/) | 类视图、总览 |
| 用展示类视图做列表/详情页 | [Generic display](https://docs.djangoproject.com/en/6.1/topics/class-based-views/generic-display/) | ListView、DetailView |
| 用编辑类视图做增删改 | [Generic editing](https://docs.djangoproject.com/en/6.1/topics/class-based-views/generic-editing/) | CreateView、UpdateView |
| 组合混入定制类视图 | [Mixins](https://docs.djangoproject.com/en/6.1/topics/class-based-views/mixins/) | mixin、组合 |
| 查表单主题总入口 | [Forms 主题](https://docs.djangoproject.com/en/6.1/topics/forms/) | 表单、总览 |
| 用 formset 批量编辑 | [Formsets](https://docs.djangoproject.com/en/6.1/topics/forms/formsets/) | formset、批量 |
| 给表单挂 CSS/JS 静态资源 | [Media](https://docs.djangoproject.com/en/6.1/topics/forms/media/) | Media、静态资源、widget 资源 |
| 用 ModelForm 从模型建表单 | [ModelForms](https://docs.djangoproject.com/en/6.1/topics/forms/modelforms/) | ModelForm |
| 查模板主题与配置 | [Templates](https://docs.djangoproject.com/en/6.1/topics/templates/) | 模板、配置、引擎 |
| 序列化模型为 JSON/XML | [Serialization](https://docs.djangoproject.com/en/6.1/topics/serialization/) | 序列化、JSON、dump |
| 做分页 | [Pagination](https://docs.djangoproject.com/en/6.1/topics/pagination/) | 分页、Paginator |
