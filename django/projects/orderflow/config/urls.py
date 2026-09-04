"""URL 配置。

⚠️ 课 20 坑 1 / 课 21 约定 1：**手写路径必须写在 include(router.urls) 之前。**

router 注册的 `<pk>` 默认匹配 `[^/.]+`，会吃掉 `/api/v1/orders/summary/` 这类路径，
让它落到 orders/<pk>/ 上，返回 405 且**没有任何报错**。

本项目把这条约定固化成了 System check（apps/shop/checks.py 的 check_route_order），
写错位置会在 `manage.py check` 时被拦下。
"""
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from apps.shop import views

# ---- 第 1 段：手写路径（必须排在 router 之前）----
handwritten = [
    path("admin/", admin.site.urls),
    path("api/v1/schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
        "api/v1/schema/swagger-ui/",
        SpectacularSwaggerView.as_view(url_name="schema"),
        name="swagger-ui",
    ),
    path("api/v1/me/", views.MeView.as_view(), name="me"),
    path("api/v1/health/", views.HealthView.as_view(), name="health"),
]

# ---- 第 2 段：router 自动路由（只能排在后面）----
from rest_framework.routers import DefaultRouter  # noqa: E402

router = DefaultRouter()
router.register(r"api/v1/products", views.ProductViewSet, basename="product")
router.register(r"api/v1/categories", views.CategoryViewSet, basename="category")
router.register(r"api/v1/orders", views.OrderViewSet, basename="order")

urlpatterns = handwritten + [
    path("", include(router.urls)),
]

# 课 19：DEBUG 下由 Django 托管 media；生产必须交给 Nginx / 对象存储
from django.conf import settings  # noqa: E402
from django.conf.urls.static import static  # noqa: E402

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
