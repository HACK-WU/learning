# contrib 包（Django Docs · 共 53 条）

> 范围：/en/6.1（排除 /releases/）· 生成日期：2026-09-16
> 主题：admin、auth、postgres 专属能力、GIS、staticfiles、sitemaps 等官方内置应用
> ⚠️ GIS 子站（25 条）与本课程学习目标弱相关，仅为完整性保留

| 我要… | 去哪一页 | 关键词 |
|-------|----------|--------|
| 查 contrib 包总清单与入口 | [contrib 总览](https://docs.djangoproject.com/en/6.1/ref/contrib/) | contrib、内置应用、总览 |
| 配置 admin 站点与 ModelAdmin 选项 | [Admin](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/) | admin、ModelAdmin、list_display |
| 写 admin 批量操作（action） | [Admin actions](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/actions/) | action、批量操作、下拉动作 |
| 启用 admindocs 自动生成文档 | [Admin docs](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/admindocs/) | admindocs、文档 |
| 自定义 admin 列表过滤器 | [Admin filters](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/filters/) | 过滤器、SimpleListFilter |
| 在 admin 里注入自定义 JS | [Admin JS](https://docs.djangoproject.com/en/6.1/ref/contrib/admin/javascript/) | JavaScript、admin 静态资源 |
| 用内置认证系统（登录/登出/用户模型） | [Auth](https://docs.djangoproject.com/en/6.1/ref/contrib/auth/) | auth、User、login、logout、权限 |
| 查 ContentTypes 框架与泛型关联 | [ContentTypes](https://docs.djangoproject.com/en/6.1/ref/contrib/contenttypes/) | ContentType、GenericForeignKey |
| 用 flatpages 管理简单静态页 | [Flatpages](https://docs.djangoproject.com/en/6.1/ref/contrib/flatpages/) | flatpage、静态页 |
| 用 humanize 做数字/日期友好显示 | [Humanize](https://docs.djangoproject.com/en/6.1/ref/contrib/humanize/) | humanize、intcomma、naturaltime |
| 用 messages 框架传一次性提示 | [Messages](https://docs.djangoproject.com/en/6.1/ref/contrib/messages/) | messages、提示、success |
| 用 redirects 应用管理 301/302 | [Redirects](https://docs.djangoproject.com/en/6.1/ref/contrib/redirects/) | redirect、301 |
| 生成站点地图 sitemap.xml | [Sitemaps](https://docs.djangoproject.com/en/6.1/ref/contrib/sitemaps/) | sitemap、SEO |
| 用 sites 框架支持多站点 | [Sites](https://docs.djangoproject.com/en/6.1/ref/contrib/sites/) | Site、多站点 |
| 查静态文件收集与 staticfiles 应用 | [Staticfiles](https://docs.djangoproject.com/en/6.1/ref/contrib/staticfiles/) | collectstatic、STATIC_ROOT、静态文件 |
| 生成 RSS/Atom 订阅源 | [Syndication](https://docs.djangoproject.com/en/6.1/ref/contrib/syndication/) | RSS、Feed、Atom |
| 查 PostgreSQL 专属能力总入口 | [PostgreSQL 专属](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/) | postgres、psycopg、专属功能 |
| 用 PostgreSQL 聚合函数 | [PG aggregates](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/aggregates/) | 聚合、ArrayAgg、JSONBAgg |
| 用 PostgreSQL 排他约束 | [PG constraints](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/constraints/) | ExclusionConstraint、排他 |
| 查 PostgreSQL 专属表达式 | [PG expressions](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/expressions/) | ArraySubquery、表达式 |
| 用 JSONField/ArrayField 等专属字段 | [PG fields](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/fields/) | JSONField、ArrayField、HStoreField |
| 查 PostgreSQL 专属表单字段与部件 | [PG forms](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/forms/) | 表单字段、widgets |
| 用 PostgreSQL 专属函数 | [PG functions](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/functions/) | 函数、RandomUUID |
| 查 PostgreSQL 索引类型（BRIN/GIN） | [PG indexes](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/indexes/) | BRIN、GIN、索引 |
| 查 PostgreSQL 专属查找（lookup） | [PG lookups](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/lookups/) | lookup、unaccent、trigram |
| 查 PostgreSQL 专属迁移操作 | [PG operations](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/operations/) | 迁移操作、扩展 |
| 用 PostgreSQL 全文搜索 | [PG search](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/search/) | 全文搜索、SearchVector、tsvector |
| 查 PostgreSQL 专属校验器 | [PG validators](https://docs.djangoproject.com/en/6.1/ref/contrib/postgres/validators/) | 校验器、范围校验 |
| 查 GeoDjango 总入口 | [GIS](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/) | GIS、GeoDjango、空间 |
| 在 admin 中编辑地理数据 | [GIS admin](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/admin/) | GeoModelAdmin、地图 |
| 查 GeoDjango 管理命令 | [GIS commands](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/commands/) | ogrinspect、命令 |
| 查空间数据库 API | [GIS db-api](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/db-api/) | 空间查询、GEOSGeometry |
| 部署 GeoDjango | [GIS deployment](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/deployment/) | 部署、PostGIS |
| 生成地理信息订阅源 | [GIS feeds](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/feeds/) | GeoFeed、订阅 |
| 查地理表单字段与部件 | [GIS forms](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/forms-api/) | 地理表单 |
| 查空间数据库函数 | [GIS functions](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/functions/) | 空间函数、Distance |
| 用 GDAL 读写栅格数据 | [GDAL](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/gdal/) | GDAL、栅格 |
| 用 GeoIP2 做 IP 地理定位 | [GeoIP2](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/geoip2/) | GeoIP、IP 定位 |
| 查空间查询集 API | [GeoQuerySet](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/geoquerysets/) | GeoQuerySet |
| 用 GEOS 做几何运算 | [GEOS](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/geos/) | GEOS、几何 |
| 安装 GeoDjango 依赖 | [GIS install](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/install/) | 安装、依赖 |
| 安装 GEOS/GDAL/PROJ 库 | [GIS geolibs](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/install/geolibs/) | GEOS、GDAL、PROJ |
| 安装 PostGIS | [PostGIS](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/install/postgis/) | PostGIS |
| 安装 SpatiaLite | [SpatiaLite](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/install/spatialite/) | SpatiaLite |
| 用 LayerMapping 导入空间数据 | [LayerMapping](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/layermapping/) | 数据导入、shapefile |
| 做距离/面积测量 | [Measure](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/measure/) | 测量、Distance、Area |
| 查空间模型字段 | [GIS model api](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/model-api/) | 空间字段、PointField |
| 从现有数据表反向生成模型 | [ogrinspect](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/ogrinspect/) | 反向生成、inspect |
| 序列化地理数据 | [GIS serializers](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/serializers/) | 序列化、GeoJSON |
| 生成地理站点地图 | [GIS sitemaps](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/sitemaps/) | sitemap、KML |
| 测试 GeoDjango 代码 | [GIS testing](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/testing/) | 测试 |
| 跟着 GeoDjango 教程上手 | [GIS tutorial](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/tutorial/) | 教程、入门 |
| 查 GeoDjango 工具函数 | [GIS utils](https://docs.djangoproject.com/en/6.1/ref/contrib/gis/utils/) | utils、工具 |
