# API Guide（DRF · 共 28 条）

> 范围：全站（排除 /community/ 版本公告）· 生成日期：2026-09-16
> 主题：DRF 核心组件参考——序列化、视图、认证、权限、限流、过滤、分页、路由

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 写序列化器、做字段校验与嵌套 | [Serializers](https://www.django-rest-framework.org/api-guide/serializers/) | serializer、校验、嵌套、create/update |
| 查序列化器字段类型与参数 | [Fields](https://www.django-rest-framework.org/api-guide/fields/) | 字段、CharField、read_only、source |
| 定义外键/多对多关系字段 | [Relations](https://www.django-rest-framework.org/api-guide/relations/) | PrimaryKeyRelated、StringRelated、Hyperlinked |
| 写字段级/对象级校验器 | [Validators](https://www.django-rest-framework.org/api-guide/validators/) | validator、UniqueTogether、校验 |
| 用 APIView 写接口 | [Views](https://www.django-rest-framework.org/api-guide/views/) | APIView、@api_view |
| 用通用视图（ListAPIView 等） | [Generic views](https://www.django-rest-framework.org/api-guide/generic-views/) | ListAPIView、RetrieveAPIView |
| 用 ModelViewSet 快速写 CRUD | [Viewsets](https://www.django-rest-framework.org/api-guide/viewsets/) | ViewSet、ModelViewSet、@action |
| 用 router 自动生成 URL 路由 | [Routers](https://www.django-rest-framework.org/api-guide/routers/) | DefaultRouter、SimpleRouter、注册 |
| 配置认证（Session/Token/JWT） | [Authentication](https://www.django-rest-framework.org/api-guide/authentication/) | 认证、Token、JWT、Session |
| 配置权限（IsAuthenticated 等） | [Permissions](https://www.django-rest-framework.org/api-guide/permissions/) | 权限、IsAdmin、自定义权限 |
| 配置限流（防刷接口） | [Throttling](https://www.django-rest-framework.org/api-guide/throttling/) | 限流、throttle、rate |
| 做过滤、搜索与排序 | [Filtering](https://www.django-rest-framework.org/api-guide/filtering/) | 过滤、SearchFilter、OrderingFilter |
| 做分页 | [Pagination](https://www.django-rest-framework.org/api-guide/pagination/) | PageNumberPagination、LimitOffset |
| 用解析器处理请求体（JSON/表单） | [Parsers](https://www.django-rest-framework.org/api-guide/parsers/) | parser、JSONParser、MultiPart |
| 用渲染器控制响应格式 | [Renderers](https://www.django-rest-framework.org/api-guide/renderers/) | JSONRenderer、渲染 |
| 内容协商（按 Accept 返回格式） | [Content negotiation](https://www.django-rest-framework.org/api-guide/content-negotiation/) | Accept、协商 |
| 用 format suffix（.json/.api） | [Format suffixes](https://www.django-rest-framework.org/api-guide/format-suffixes/) | 后缀、.json |
| 查 Request 对象扩展了什么 | [Requests](https://www.django-rest-framework.org/api-guide/requests/) | request.data、query_params |
| 查 Response 对象与返回方式 | [Responses](https://www.django-rest-framework.org/api-guide/responses/) | Response、data、status |
| 查 HTTP 状态码常量 | [Status codes](https://www.django-rest-framework.org/api-guide/status-codes/) | 200、400、HTTP_200_OK |
| 自定义错误响应与异常处理 | [Exceptions](https://www.django-rest-framework.org/api-guide/exceptions/) | APIException、ValidationError、handler |
| 反向解析 API URL | [Reverse](https://www.django-rest-framework.org/api-guide/reverse/) | reverse、超链接 |
| 查元数据（OPTIONS 返回） | [Metadata](https://www.django-rest-framework.org/api-guide/metadata/) | OPTIONS、元数据 |
| 生成 OpenAPI/Schema 文档 | [Schemas](https://www.django-rest-framework.org/api-guide/schemas/) | OpenAPI、Schema、drf-spectacular |
| 配置缓存（ETag/Cache-Control） | [Caching](https://www.django-rest-framework.org/api-guide/caching/) | 缓存、ETag |
| 写 API 测试（APIClient） | [Testing](https://www.django-rest-framework.org/api-guide/testing/) | APIClient、APITestCase、断言 |
| 查 DRF 的 settings 配置项 | [Settings](https://www.django-rest-framework.org/api-guide/settings/) | DEFAULT_PERMISSION_CLASSES、配置 |
| 做 API 版本管理 | [Versioning](https://www.django-rest-framework.org/api-guide/versioning/) | 版本、URLPathVersioning |
