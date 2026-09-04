"""权限：你能干什么（课 9）。

课 9 的两条硬结论：
  1. 对象级权限与 queryset 过滤是**两个方向**：
     - queryset 过滤管"列表里能看到什么"（不过滤 = 信息泄漏）
     - 对象级权限管"单个对象能操作什么"（不校验 = 越权）
     只做其中一个都漏。
  2. has_object_permission 不会自动被调用 —— 必须由 get_object() 触发。
"""
from rest_framework import permissions

from apps.shop.models import Order


class IsOwner(permissions.BasePermission):
    """对象级权限：只有订单本人能操作。"""

    message = "只能操作自己的订单"

    def has_object_permission(self, request, view, obj):
        return obj.user_id == request.user.pk


class IsOwnerOrStaff(permissions.BasePermission):
    """本人或后台人员。"""
    def has_object_permission(self, request, view, obj):
        return bool(
            obj.user_id == request.user.pk or (request.user and request.user.is_staff)
        )


class OrderQuerysetMixin:
    """queryset 过滤：列表只返回自己的订单。

    ⚠️ 这一条和 IsOwner 是互补的，不是替代关系。
    """
    def get_queryset(self):
        qs = Order.objects.all()
        if self.request.user.is_staff:
            return qs
        return qs.filter(user=self.request.user)
