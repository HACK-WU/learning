# 课 19《文件、存储与 Admin》learner 视角评审

评审对象：`stages/6-工程化与生产/lessons/lesson-19-文件存储与Admin.md`
评审日期：2026-09-03

---

## 总评

**P0 = 0**。

假设我是一个零上下文的学员，读完能知道：文件存成了什么、STORAGES 怎么配、Admin 怎么收敛、staticfiles 归谁。术语表 17 个词覆盖了主要陌生概念，自检题有折叠答案。

以下是我在"照着做"时会卡住的地方。

---

## L1-① 2.6 节的上传校验代码看不出该放在哪、怎么接

**问题**：2.6 节给了一个完整的 `AttachmentUploadSerializer`，但没给**视图**。我知道有这个 Serializer 了，却不知道：

- 它配合哪个 `APIView` / `ModelViewSet`？
- `parser_classes` 要配什么？
- 上传成功后返回什么？

术语表和 2.8 节都提到 `MultiPartParser`，但整份讲义**没有一处完整的"上传接口 + 视图"代码**。

**建议**：在 2.6 节补上对应的视图，形成一个能直接抄的闭环：

```python
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView


class AttachmentUploadAPI(APIView):
    """独立上传接口：上传与业务创建分开。"""

    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        ser = AttachmentUploadSerializer(data=request.data)   # ← 第一行就触发解析
        ser.is_valid(raise_exception=True)
        f = ser.validated_data["file"]
        obj = Attachment.objects.create(
            original_name=f.name,      # 原始名另存，供展示
            file=f,                    # storage 返回的名字才是真的
            size=f.size,
            content_type=getattr(f, "content_type", "") or "",
        )
        return Response({"id": obj.id, "url": obj.file.url},
                        status=status.HTTP_201_CREATED)
```

并注明 `original_name` 与 `file.name` 的区别（呼应 2.4 节的同名文件改名）。

---

## L1-② 3.1 节说"两级权限"，但没说怎么建一个能用的运营账号

**问题**：3.1 节讲清了 `is_staff` + model 权限两级，也给了实验数据。但我要真去配一个运营账号时，还是不知道：

- 是建 Group 还是直接给 user 加 permission？
- 给了 `view_invoice` 之后，列表页能看，但**能不能改**？需要再加哪个权限？
- `list_editable = ["status"]` 这种行内编辑，需要 `change` 权限吗？

**建议**：补一个"开通运营账号"的最小步骤：

```python
from django.contrib.auth.models import Group, Permission
from django.contrib.contenttypes.models import ContentType
from apps.core.models import Invoice

ct = ContentType.objects.get_for_model(Invoice)
ops_group, _ = Group.objects.get_or_create(name="财务运营")

# 只给查看 + 修改，不给删除
for codename in ["view_invoice", "change_invoice"]:
    ops_group.permissions.add(Permission.objects.get(content_type=ct, codename=codename))

# 再把用户加进组，并勾 is_staff
user.groups.add(ops_group)
user.is_staff = True      # ← 不加这个进不了 Admin，与组权限无关
user.save()
```

并明确：**`list_editable` 需要 `change` 权限；`has_delete_permission` 返回 False 时，即使有 `delete` 权限也删不掉**（两级都要过）。

---

## L1-③ 4.4 节 WhiteNoise 的判断标准给了，但没说"如果要用怎么配"

**问题**：4.4 节的表格判断标准很清楚（"业务静态资源还有没有走 Django"）。但如果我的结论是"要用"，讲义没给配置。学员会被卡在这里。

**建议**：补一小段最小配置：

```python
# settings.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",   # ← 紧跟 SecurityMiddleware
    # ... 其它中间件
]

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}
```

并提醒：**WhiteNoise 只服务 `STATIC_ROOT`，不服务 `MEDIA_ROOT`**——所以它解决不了本课第一幕那个工单（上传文件下载 404）。这个反直觉的点值得写一句。

---

## L1-④ 术语表缺少 3 个词

讲义里出现了但我第一遍没看懂的词：

| 词 | 上下文 | 需要的一句话解释 |
|----|--------|----------------|
| magic number | 2.6 节"或 python-magic 读 magic number" | 文件开头几个字节的固定标识，用来判断真实类型（不看扩展名） |
| `default_acl` | 2.10 节对象存储配置 | 上传对象的默认访问权限；设 `None` 表示交给 bucket policy 统一管 |
| browsable API | 4.1 节"DRF 的可浏览 API" | DRF 自带的 HTML 调试页面，也是它那 27 个静态文件的来源 |

另外 2.10 节的 `region_name`、`file_overwrite` 建议加行内注释，否则学员不知道哪些该改。

---

## 已确认的强项

- **术语表质量高**：`MEDIA_ROOT` / `STATIC_ROOT` / `STATICFILES_DIRS` 三个目录的分工表（4.2 节）一扫就懂。
- **"不报错的错误"清单**（5.2 节）很实用，第 14-17 处都有明确出处。
- **高频误区表**（5.3 节）15 条，每条都标了实验编号，可回溯。
- **验证环境的四条受限披露**诚实，特别是"对象存储未真实联网"和"未测真实并发上传"。

---

## 结论

**通过（P0=0）**，建议采纳 L1-①（上传接口视图闭环，这是最影响"照着做"的一项）。L1-②③④ 一并处理更佳。
