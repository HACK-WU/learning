# HTTP 与视图层（Django Docs · 共 39 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：请求响应、URL 路由、视图与类视图、表单、模板、文件、分页、信号、安全中间件

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查 HttpRequest/HttpResponse 的属性与方法 | [Request/Response](https://docs.djangoproject.com/en/6.1/ref/request-response/) | request、response、HttpRequest、JsonResponse |
| 查 URL 配置与 path/re 的写法 | [URL dispatcher](https://docs.djangoproject.com/en/6.1/ref/urls/) | url、path、路由、include |
| 查反向解析函数（reverse/resolve） | [URL resolvers](https://docs.djangoproject.com/en/6.1/ref/urlresolvers/) | reverse、resolve、反向解析 |
| 查视图函数/类视图的基础装饰器与混入 | [Built-in views](https://docs.djangoproject.com/en/6.1/ref/views/) | 视图、装饰器、静态文件视图 |
| 查中间件写法与内置中间件清单 | [Middleware](https://docs.djangoproject.com/en/6.1/ref/middleware/) | middleware、process_request、中间件顺序 |
| 查类视图参考总入口 | [CBV 参考](https://docs.djangoproject.com/en/6.1/ref/class-based-views/) | 类视图、CBV、View |
| 查 View/TemplateView/RedirectView 基类 | [Base views](https://docs.djangoproject.com/en/6.1/ref/class-based-views/base/) | View、TemplateView、RedirectView |
| 按用途反查"该用哪个类视图" | [CBV 扁平索引](https://docs.djangoproject.com/en/6.1/ref/class-based-views/flattened-index/) | 选型、反查、哪个类视图 |
| 查日期归档类视图（ArchiveIndexView 等） | [Date-based views](https://docs.djangoproject.com/en/6.1/ref/class-based-views/generic-date-based/) | ArchiveIndexView、归档、日期 |
| 查 ListView/DetailView 展示类视图 | [Generic display views](https://docs.djangoproject.com/en/6.1/ref/class-based-views/generic-display/) | ListView、DetailView |
| 查 CreateView/UpdateView/DeleteView | [Generic editing views](https://docs.djangoproject.com/en/6.1/ref/class-based-views/generic-editing/) | CreateView、UpdateView、FormView |
| 查类视图混入总表与 MRO 组合方式 | [CBV mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins/) | mixin、混入、MRO |
| 查日期相关混入 | [Date mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins-date-based/) | 日期混入 |
| 查表单处理相关混入 | [Editing mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins-editing/) | FormMixin、ModelFormMixin |
| 查多对象混入（分页/排序） | [Multiple object mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins-multiple-object/) | MultipleObjectMixin、分页 |
| 查基础混入（ContextMixin 等） | [Simple mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins-simple/) | ContextMixin、TemplateResponseMixin |
| 查单对象混入 | [Single object mixins](https://docs.djangoproject.com/en/6.1/ref/class-based-views/mixins-single-object/) | SingleObjectMixin |
| 查表单参考总入口与章节导航 | [Forms 参考](https://docs.djangoproject.com/en/6.1/ref/forms/) | 表单、Form、总览 |
| 查表单 API 与 Form 类用法 | [Forms API](https://docs.djangoproject.com/en/6.1/ref/forms/api/) | Form、cleaned_data、is_valid |
| 查所有表单字段类型与参数 | [Form fields](https://docs.djangoproject.com/en/6.1/ref/forms/fields/) | 表单字段、CharField、widget |
| 用 formset 一次编辑多条记录 | [Formsets](https://docs.djangoproject.com/en/6.1/ref/forms/formsets/) | formset、批量表单 |
| 用 ModelForm 从模型生成表单 | [Model forms](https://docs.djangoproject.com/en/6.1/ref/forms/models/) | ModelForm、fields、exclude |
| 查表单渲染方式（as_p/as_table/手动） | [Form renderers](https://docs.djangoproject.com/en/6.1/ref/forms/renderers/) | 渲染、as_p、renderer |
| 查表单与字段校验流程、自定义 clean | [Form validation](https://docs.djangoproject.com/en/6.1/ref/forms/validation/) | 校验、clean、clean_xxx、错误 |
| 查所有 widget 部件与自定义 widget | [Widgets](https://docs.djangoproject.com/en/6.1/ref/forms/widgets/) | widget、部件、HTML 渲染 |
| 查模板参考总入口与引擎配置 | [Templates 参考](https://docs.djangoproject.com/en/6.1/ref/templates/) | 模板、引擎、总览 |
| 查模板引擎 API 与自定义后端 | [Templates API](https://docs.djangoproject.com/en/6.1/ref/templates/api/) | 模板 API、Engine、backend |
| 查内置模板标签与过滤器清单 | [Built-ins](https://docs.djangoproject.com/en/6.1/ref/templates/builtins/) | 标签、过滤器、for、if |
| 查模板语法（变量、继承、自动转义） | [Template language](https://docs.djangoproject.com/en/6.1/ref/templates/language/) | 模板语法、继承、转义 |
| 查文件/存储主题的总入口 | [Files 参考](https://docs.djangoproject.com/en/6.1/ref/files/) | 文件、存储、File、总览 |
| 查文件对象（File/ImageFile）API | [File API](https://docs.djangoproject.com/en/6.1/ref/files/file/) | File、ImageFile、文件对象 |
| 查存储后端 API 与自定义存储 | [Storage API](https://docs.djangoproject.com/en/6.1/ref/files/storage/) | storage、FileSystemStorage、S3 |
| 查文件上传处理与上传处理器 | [Uploads](https://docs.djangoproject.com/en/6.1/ref/files/uploads/) | 上传、upload handler、MEDIA |
| 用 Paginator 做分页 | [Paginator](https://docs.djangoproject.com/en/6.1/ref/paginator/) | 分页、Paginator、Page |
| 查内置信号清单与自定义信号 | [Signals](https://docs.djangoproject.com/en/6.1/ref/signals/) | signal、post_save、pre_delete |
| 用 TemplateResponse 延迟渲染 | [TemplateResponse](https://docs.djangoproject.com/en/6.1/ref/template-response/) | TemplateResponse、延迟渲染 |
| 防点击劫持（X-Frame-Options） | [Clickjacking](https://docs.djangoproject.com/en/6.1/ref/clickjacking/) | 点击劫持、X-Frame-Options |
| 配置 CSP 响应头 | [CSP](https://docs.djangoproject.com/en/6.1/ref/csp/) | CSP、Content-Security-Policy |
| 查 CSRF 机制与排除方式 | [CSRF](https://docs.djangoproject.com/en/6.1/ref/csrf/) | csrf_token、csrf_exempt |
