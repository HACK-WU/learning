# 课 19　文件、存储与 Admin

> 📖 情节定位：**收尾（一）** —— 分离之后，剩下的那些"传统 Django 能力"该怎么处理
> 🎯 本课目标：文件走独立上传接口，Admin 定制成安全的运营后台，staticfiles 只服务于 Admin
> 🧪 本课所有结论均来自实跑：**42 个实验 / 75 项断言 / 零失败**（环境见文末「验证环境」）

---

## 术语直白解释表

| 术语 | 一句话解释 | 不解释会怎样 |
|------|-----------|-------------|
| `FileField` / `ImageField` | 数据库里只存**一个相对路径字符串**，真正的字节在 storage 里 | 以为文件存在数据库里，奇怪为什么迁移数据库不带上文件 |
| `STORAGES` | Django 4.2+ 的存储后端注册表，用名字换掉"文件存哪、url 怎么拼" | 还在用 `DEFAULT_FILE_STORAGE`（已废弃） |
| storage | "文件放哪 + 怎么读写 + url 怎么拼"的统一抽象 | 换对象存储时业务代码要到处改 |
| `MEDIA_ROOT` / `MEDIA_URL` | 上传文件的**落盘目录** / **访问前缀** | 上传成功却 404，不知道查哪 |
| `STATIC_ROOT` | `collectstatic` 把静态文件**汇总到这里**的目录 | 和 `MEDIA_ROOT` 混为一谈 |
| `STATICFILES_DIRS` | 你自己写的静态文件放哪（分离后通常为空） | 以为业务前端的 JS/CSS 也要放这儿 |
| `collectstatic` | 把散落在各 app 的静态文件**收集到一个目录**，供 Nginx 直接使用 | 生产环境静态资源 404 |
| Admin | Django 自带的数据管理后台，**自带模板体系**，与前后端分离不冲突 | 以为"分离了就该删掉 Admin" |
| `is_staff` | 能不能**进入** Admin 的总开关（与具体权限无关） | 给了权限却进不去，或只勾 staff 就能进 |
| `list_display` | Admin 列表页显示哪些列 | 列表页全是 `Invoice object (12)` |
| `list_select_related` | 让列表页**预先 join** 外键，专治 Admin 的 N+1 | 列表页几百条时慢得离谱 |
| `readonly_fields` | 表单级只读——**不是数据库约束** | 以为设了只读数据就改不了 |
| `upload_to` | 文件落盘的子目录规则，支持 `%Y/%m/%d` 时间占位 | 所有文件堆在一个目录 |
| 孤儿文件 | 数据库记录删了、磁盘文件还在 | 磁盘缓慢增长，查不到原因 |
| WSGI | Web 服务器与 Python 应用之间的**同步**接口协议 | 与文件存储混为一谈 |
| ASGI | WSGI 的异步继任者，支持 WebSocket 与长连接 | 同上 |
| instrumentation | 在代码里**埋点采集**运行数据的动作与代码的统称 | 与业务日志混淆 |
| magic number | 文件开头几个字节的**固定标识**（如 PNG 是 `89 50 4E 47`），用来判断真实类型 | 以为只能靠扩展名判断文件类型 |
| `default_acl` | 上传到对象存储时的**默认访问权限**；设 `None` 表示交给 bucket policy 统一管 | 随手设 `public-read` 导致文件被公开访问 |
| browsable API | DRF 自带的 HTML 调试页面（浏览器访问 API 时看到的那个界面） | 不知道 `collectstatic` 里那 27 个非 Admin 文件是哪来的 |

---

## 第一幕：上传成功了，但用户说"下载不了"

### 1.1 一个分离项目的真实工单

你的前后端分离项目上线三个月，运营提了个工单：

> "我在后台上传了合同 PDF，页面显示'上传成功'，但点链接是 404。"

你去查，看到了这些事实：

```text
数据库里有这条记录：Attachment(id=42, original_name="contract.pdf")
文件确实在磁盘上：/app/media/attachments/2026/09/03/contract.pdf
接口返回 201，前端提示"上传成功"
浏览器访问 /media/attachments/2026/09/03/contract.pdf → 404
```

**四个环节全对，结果是错的。**

这类问题的共同点是：**每个环节单独看都没错，错在环节之间的假设**。文件写进去了，URL 也生成了，但没人负责"把这个 URL 变成可访问的 HTTP 响应"。

传统 Django 项目里，这件事由 `django.conf.urls.static()` 做——但**它只在 `DEBUG=True` 时工作**。分离项目部署时 `DEBUG=False`，于是这段路由**安静地消失了**。

### 1.2 这个工单背后藏着三个问题

| 现象 | 真实的根因 | 属于哪个知识点 |
|------|-----------|--------------|
| 上传成功但下载 404 | `static()` 只在 DEBUG 下挂载 `/media/` | 知识点 3 staticfiles |
| 同名文件被悄悄改名 | storage 自动加随机后缀，但**没人告诉你** | 知识点 1 文件上传 |
| 运营后台谁都能进 | `is_staff=True` 是总开关，与权限无关 | 知识点 2 Admin 安全 |

它们看似无关，其实是一条线：**分离之后，Django 不再是"整个网站"，而只是"一组 API + 一个后台"。** 那些原本由框架一手包办的事情（服务文件、渲染页面、管理入口），现在需要你**重新划清归属**。

### 1.3 五分钟定位：这类问题怎么查

遇到"上传成功但下载不了"，按这四步走，别一上来就翻代码：

```bash
# ① 文件到底在不在磁盘上？
ls -la /app/media/attachments/2026/09/03/contract.pdf

# ② 生产环境的 DEBUG 是什么？（这一步经常被跳过）
python manage.py shell -c "from django.conf import settings; print(settings.DEBUG)"

# ③ urls.py 里 static() 是不是被 if settings.DEBUG 包着？
grep -n "static(" config/urls.py

# ④ 别只看配置，实际访问一次
curl -I https://your-domain/media/attachments/2026/09/03/contract.pdf
```

第 ② 步是关键：**`DEBUG=False` 时 `static()` 那段路由根本不存在**（4.3 节会给出实测证据）。第 ④ 步也不能省——`collectstatic` 和数据库记录都正常的情况下，**只有实际访问才能暴露"没人服务这个 URL"。**

### 1.4 本课的三个问题

1. 文件从请求进来，到落在磁盘/对象存储，中间经过了谁？哪些环节会**静默改变结果**？
2. Admin 作为"分离后唯一保留的服务端渲染页面"，怎么定制成**安全的**运营后台？
3. `staticfiles` 这套东西，在前后端分离之后**还属于 Django 吗**？

---

## 第二幕：文件上传与 STORAGES

### 2.1 先确认：文件到底存成了什么

`FileField` 最容易误解的一点：**数据库里存的不是文件，是一个路径字符串**。

```python
class Attachment(models.Model):
    file = models.FileField(upload_to="attachments/%Y/%m/%d/")
```

落库之后，`file` 字段的值是这样的：

```text
attachments/2026/09/03/report.txt
```

**只是一个相对路径。** 真正的字节在 `MEDIA_ROOT` 下，而"这个路径对应的 URL 是什么"由 storage 决定。

这就解释了为什么换存储后端不需要改模型——模型只认相对路径，怎么落盘、怎么拼 URL 是 storage 的事。

### 2.2 Django 4.2+ 的 STORAGES：一次配两个后端

老写法（已废弃）：

```python
DEFAULT_FILE_STORAGE = "..."      # 4.2 起废弃
STATICFILES_STORAGE = "..."       # 4.2 起废弃
```

新写法：

```python
STORAGES = {
    "default": {           # FileField/ImageField 用这个
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {       # collectstatic 用这个
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
    },
}
```

**两个键是独立的**，这是本课第一个要记住的结构。

### 2.3 怎么确认配置真的生效了（回接课 18 的 4.3 节）

课 18 讲过一个原则：**打印真实生效值，而不是读 settings**。这里有个更隐蔽的坑——连 `default_storage` 都不是真实对象。

实验 1 的实测输出：

```text
settings.STORAGES['default']['BACKEND'] = django.core.files.storage.FileSystemStorage
实际 default_storage 类              = DefaultStorage        ← 惰性代理！
storages['default'] 类               = FileSystemStorage     ← 这个才是真的
storages['staticfiles'] 类           = StaticFilesStorage
未触发时 _wrapped                    = object                ← 还没解包
触发一次操作后                        = FileSystemStorage
```

**`default_storage` 是个 `LazyObject`**，打印它的类名只会得到 `DefaultStorage`。你要看真实后端，得用 `storages['default']`，或者先触发一次操作让它解包。

```python
from django.core.files.storage import storages

print(type(storages["default"]).__name__)      # FileSystemStorage
print(type(default_storage).__name__)          # DefaultStorage ← 不是真实类
default_storage.exists("x")                    # 触发解包
print(type(default_storage._wrapped).__name__) # FileSystemStorage
```

### 2.4 同名文件：不报错，但结果变了（第 14 处「不报错的错误」）

实验 3 的实测：连传两个 `report.txt`。

```text
第一次 201 → original_name='report.txt'  落盘=attachments/2026/09/03/report.txt
第二次 201 → original_name='report.txt'  落盘=attachments/2026/09/03/report_WawkC7Q.txt
```

**两次都返回 201，一次错都不报。** 但第二个文件的落盘名被加了随机后缀。

这件事的危险在于：如果你的代码**假设"文件名 = 上传时的名字"**，那么第二次上传之后，这个假设就失效了——而且是静默失效。

实验 4 连传 20 次同名文件，确认了后缀的形态：

```text
第 1 个  = attachments/2026/09/03/same.txt
第 20 个 = attachments/2026/09/03/same_D1f5NTy.txt
后缀长度 = 16 字符
```

后缀是 **7 位随机字符串**，不是 `_1` `_2` 递增。这是好事——递增后缀会让文件名**可枚举**，攻击者能猜到其他人的文件地址。

> **工程含义**：永远用 `obj.file.name`（storage 返回的真实名字）或 `obj.file.url`，**不要自己拼 `upload_to + 原文件名`**。
> 如果你需要保留原始文件名（给用户看），**单独存一个字段**（如 `original_name`），不要靠解析路径去还原。

### 2.5 目录遍历：storage 帮你挡了，但别依赖运气

实验 38 上传一个文件名叫 `../../../evil.txt` 的文件：

```text
上传文件名 '../../../evil.txt' → 201
落盘路径 = attachments/2026/09/03/evil.txt
MEDIA_ROOT 内吗 = True
```

Django 的 storage 会**清洗路径**，跳出 `MEDIA_ROOT` 的尝试会被去掉。但这属于**实现行为**而非文档契约——自己的业务代码里仍然不要拼接用户提供的路径。

### 2.6 上传校验：三道防线，两道不可信

一个能用的独立上传接口长这样：

```python
import os

from rest_framework import serializers

MAX_UPLOAD_BYTES = 1024 * 1024  # 1 MB
ALLOWED_EXT = {".pdf", ".png", ".jpg", ".jpeg", ".txt", ".csv"}
ALLOWED_CONTENT_TYPE = {
    "application/pdf", "image/png", "image/jpeg",
    "text/plain", "text/csv",
}


class AttachmentUploadSerializer(serializers.Serializer):
    file = serializers.FileField()

    def validate_file(self, value):
        # 防线 1：扩展名白名单（按最后一段判断）
        ext = os.path.splitext(value.name)[1].lower()
        if ext not in ALLOWED_EXT:
            raise serializers.ValidationError(f"不支持的文件类型：{ext or '(无扩展名)'}")

        # 防线 2：大小限制
        if value.size > MAX_UPLOAD_BYTES:
            raise serializers.ValidationError(
                f"文件过大：{value.size} 字节，上限 {MAX_UPLOAD_BYTES} 字节"
            )

        # 防线 3：content_type —— 可伪造，仅作辅助
        declared = getattr(value, "content_type", "") or ""
        if declared and declared not in ALLOWED_CONTENT_TYPE:
            raise serializers.ValidationError(f"不支持的 Content-Type：{declared}")

        return value
```

三道防线的可信度**完全不同**，实验 5/7 给出了对照：

配套的视图长这样——注意 `request.data` 是**第一行就取**的（原因见 2.8 节）：

```python
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.models import Attachment
from apps.core.serializers import AttachmentUploadSerializer


class AttachmentUploadAPI(APIView):
    """独立上传接口：上传与业务创建分成两步。"""

    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        # ⚠️ 第一行就触发解析 —— 别让任何 if 分支抢在它前面 return，
        #    否则 DRF 不会选 parser，也就不报错（见 2.8 节）
        ser = AttachmentUploadSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        f = ser.validated_data["file"]
        obj = Attachment.objects.create(
            original_name=f.name,      # 原始名，只用于展示
            file=f,                    # storage 给的名字才是真的落盘名
            size=f.size,
            content_type=getattr(f, "content_type", "") or "",
        )
        return Response(
            {"id": obj.id, "original_name": obj.original_name, "url": obj.file.url},
            status=status.HTTP_201_CREATED,
        )
```

`original_name` 与 `file.name` 的区别要记牢（呼应 2.4 节）：前者是**用户上传时的名字**（供展示），后者是 **storage 决定的真实落盘名**——同名文件第二次上传时，这两个值就不一样了。

| 防线 | 实测结果 | 可信吗 |
|------|---------|--------|
| 扩展名白名单 | `.exe` → 400；无扩展名 → 400；`report.pdf.exe` → 400 | ✅ 按**最后一段**判断就可靠 |
| 大小限制 | 1MB+10B → 400（Serializer 拦的，不是 413） | ✅ 可靠，但要拦在正确层级 |
| `content_type` | 把文本改名 `shell.png` 并声明 `image/png` → **201 通过** | ❌ **纯客户端声明，可伪造** |

实验 7 的完整输出：

```text
声明 image/png 的 .png 文本文件 → 201
落盘 content_type 记录 = 'image/png'（原样存了客户端声明）
```

**`content_type` 是客户端在 multipart 头里自己写的。** 它能拦住"误传"，拦不住"故意"。真正判断文件类型要靠**读内容**（如 Pillow 解析、或 `python-magic` 读 magic number）。

### 2.7 ImageField 会校验内容吗？会——但只在有 Pillow 时

实验 8 把一个带 `<script>` 的 SVG 改名成 `evil.png` 上传：

```text
把 SVG 脚本伪装成 .png 上传 → 400
响应 = {'detail': '不是合法图片：UnidentifiedImageError: cannot identify image file <InMemoryUploadedFile: evil.png (image/png)>'}
真 PNG → 201
```

关键点：

1. **`ImageField` 本身不校验内容**——安装 Pillow 后，`ImageField` 才会去解析图片拿宽高。上面这个 400 是我**在视图里显式调用 `Image.verify()`** 得到的。
2. 没装 Pillow 时，`ImageField` 会退化成普通 `FileField`，**连尺寸字段都不校验**。
3. 依赖组合要实跑（必查项 #12）：本课实测 Pillow **12.3.0** 在 Django 6.1 + Python 3.13.14 下工作正常。

### 2.8 忘了配 MultiPartParser：静默的 200（第 15 处「不报错的错误」）

这是本课最反直觉的一个发现。

我原本以为：给一个只配了 `JSONParser` 的接口发 multipart 请求，会返回 **415 Unsupported Media Type**。实验 9 实测：

```text
不碰 request.data   → 200  {"ok":true}          ← 预期 415，实测 200
碰一下 request.data → 415  {"detail":"不支持请求中的媒体类型 …"}
```

**同一个请求，动没动 `request.data` 决定了它报不报错。**

原因是 DRF 的 `_parse()` 是**懒加载**的（源码 `rest_framework/request.py:353-356`）：

```python
def _parse(self):
    ...
    parser = self.negotiator.select_parser(self, self.parsers)
    if parser is None:
        raise exceptions.UnsupportedMediaType(media_type)   # ← 这里才抛
```

只有访问 `request.data`（或 `.FILES`）时才触发 `_parse()`。**不访问，就不解析，也就不报错。**

工程含义很实在：

- 上传接口如果**忘了配 `MultiPartParser`**，但代码里又因为某种原因没碰 `request.data`（比如走进了某个提前 return 的分支），你会得到一个**看起来正常的 200，但文件根本没被处理**。
- 反过来，一旦访问了 `request.data`，才会 415——这时错误才暴露。
- 自检方法：**上传接口的视图函数第一行就去拿 `request.FILES`**，别让解析被跳过。

### 2.9 换存储后端：业务代码一行都不用改（前提是你别硬拼 URL）

实验 16 用一个假的对象存储后端做了对照：

```python
class FakeS3Storage(FileSystemStorage):
    def url(self, name):
        return f"https://cdn.example.com/{name}"
```

```text
FileSystemStorage.url('/media/x.txt') → /media/x.txt
FakeS3Storage.url('a/b/c.txt')       → https://cdn.example.com/a/b/c.txt
```

**同一段业务代码，换后端后 URL 语义完全变了。** 这恰恰是好事——前提是你的代码**从来没硬拼过路径**。

| 写法 | 换到对象存储后 |
|------|--------------|
| `obj.file.url` | ✅ 自动变成 CDN 地址 |
| `f"{MEDIA_URL}{obj.file.name}"` | ❌ 拼出 `/media/xxx`，在生产是死链 |
| `obj.file.path` | ❌ **直接报错**——对象存储没有本地路径 |

> **`file.path` 是 `FileSystemStorage` 专有概念。** 一旦换成对象存储，`Storage` 基类根本没有 `path`，所有 `.path` 调用全部炸掉。迁移前先全局搜 `.path`。

### 2.10 对接对象存储：django-storages 的现况

实验 15 实测的依赖组合：

```text
django-storages = 1.14.6
boto3           = 1.43.87
Django          = 6.1
```

配置方式：

```python
STORAGES = {
    "default": {
        "BACKEND": "storages.backends.s3.S3Storage",
        "OPTIONS": {
            "bucket_name": "my-bucket",              # ← 改成你的桶名
            "region_name": "ap-guangzhou-1",         # ← 改成你的地域
            "default_acl": None,        # None = 交给 bucket policy 统一管
                                        # 别设 public-read，那等于文件公开
            "file_overwrite": False,    # False = 同名不覆盖（与 2.4 节一致）
        },
    },
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
    },
}
```

**⚠️ 类名已经变了。** 实验 15c 的实测：

```text
旧名 S3Boto3Storage 还在吗：False
实际可用：['BaseStorage', 'S3ManifestStaticStorage', 'S3StaticStorage', 'S3Storage']
```

网上大量教程（包括一些 2024 年的）还在用 `S3Boto3Storage`，在 1.14 里会直接 `ImportError`。**现在叫 `S3Storage`。**

另外两个实测事实：

1. **装 `django-storages` 不会自动装 `boto3`**（实验 15b）。缺了会报：
   ```
   ImproperlyConfigured: Could not load Boto3's S3 bindings. No module named 'boto3'
   ```
   提示很明确，照着装就行。
2. **不给凭证也能构造成功**（实验 15c）。`S3Storage()` 是惰性的，凭证在真正发请求时才校验。好处是启动不会因为配置缺失而失败，坏处是**配置错误要到第一次上传才暴露**。

### 2.11 STORAGES 的两个配置陷阱

**陷阱一：漏配 `staticfiles` 键会报错——但不是启动时报（实验 12）**

```python
STORAGES = {"default": {"BACKEND": "..."}}   # 漏了 staticfiles
```

实测：

```text
InvalidStorageError: Could not find config for 'staticfiles' in settings.STORAGES.
```

⚠️ **我原以为会有默认值兜底，实测没有。** 这个错误比"静默用错后端"好，但要注意它是**访问 `storages['staticfiles']` 时才抛**，不是启动时——所以如果你的测试没走到静态资源那条路径，本地可能一直不报错，上线才炸。

**陷阱二：`override_settings` 改 STORAGES 是生效的，但自定义后端必须放独立模块（实验 11/20）**

实验 11 确认 `override_settings(STORAGES=...)` **确实生效**（与课 2 中间件、课 8 simplejwt 的情况不同）：

```text
settings.STORAGES['default'] = lab_storages.ProbeStorage
storages['default'] 真实类    = ProbeStorage
getattr marker                = PROBE          ← 消费方真的看到了
退出 override 后              = FileSystemStorage
```

但这里踩到一个**实验工程层面的坑**：我一开始把自定义的 `ProbeStorage` 直接定义在 `run_lab2.py` 里，结果 `import_string("run_lab2.ProbeStorage")` 把整个脚本**重新执行了一遍**，报 `setup_test_environment() was already called`。

原因：`STORAGES` 的 `BACKEND` 是**点分路径字符串**，Django 会去 `import` 那个模块。所以**自定义 storage 必须放在独立模块里**，不要写在实验脚本或 `manage.py` 旁边。

实验 20 还确认了 `OPTIONS` 的传递方式：

```python
STORAGES = {
    "default": {"BACKEND": "lab_storages.OptStorage", "OPTIONS": {"custom_opt": "hello-opt"}},
}
# → OptStorage(custom_opt="hello-opt")，作为 kwargs 传给构造函数
```

### 2.12 孤儿文件：删了记录，文件还在（第 16 处「不报错的错误」）

实验 17 的实测：

```text
上传后落盘：/media/attachments/2026/09/03/to-delete.txt  存在=True
obj.delete() 后文件还在吗：True
```

**删数据库记录不会删磁盘文件。** Django 有意这么设计（删文件是有风险的操作），但后果是：文件会**无限累积**。

实验 18 做了放大检验（必查项 #28）：

```text
建 200 条（每份 500B）后 MEDIA_ROOT = 97.8 KB
全部 delete() 后 MEDIA_ROOT         = 97.8 KB
残留比例 = 100%
```

**删光了所有记录，磁盘占用一点没降。** 生产上这就是"磁盘莫名其妙满了，但数据库里没几条数据"的经典原因。

**孤儿文件会一直累积，而你浑然不觉。** 下面是发现它们的手段——把"数据库引用的"与"磁盘上有的"做差集：

```python
import os
from pathlib import Path

from django.conf import settings

from apps.core.models import Attachment

# 数据库里引用的文件
# ⚠️ 必须用 values_list(flat=True)：10 万条时只取这一列，
#    而 for obj in Attachment.objects.all() 会把全表读进内存（必查项 #28）
db_names = set(Attachment.objects.values_list("file", flat=True))

# 磁盘上真实存在的文件
disk_names = {
    str(p.relative_to(settings.MEDIA_ROOT)).replace("\\", "/")
    for p in Path(settings.MEDIA_ROOT).rglob("*")
    if p.is_file()
}

orphans = disk_names - db_names
print(f"数据库引用 {len(db_names)} 个，磁盘 {len(disk_names)} 个，孤儿 {len(orphans)} 个")
for name in sorted(orphans)[:20]:
    print(f"  孤儿：{name}")
```

⚠️ 换成对象存储后这段要改——没有 `rglob`，得调 `storage.listdir()` 分页遍历，或用对象存储自带的**生命周期规则**（配一条"多少天后自动清理无引用对象"更省事）。

> **更省心的做法**：对象存储普遍支持**生命周期规则**（如 COS/S3 的 Lifecycle），可以直接配"上传 90 天后删除"，或者用**清单（Inventory）+ 定期比对**做清理。这比自己写扫描脚本可靠得多。

正确姿势有两种：

```python
# 方式一：手动删文件再删记录
obj.file.delete(save=False)   # 只删文件
obj.delete()                  # 再删记录

# 方式二：用 signal 自动清理（注意与课 17 的耦合警告）
from django.db.models.signals import post_delete
from django.dispatch import receiver

@receiver(post_delete, sender=Attachment)
def _delete_file(sender, instance, **kwargs):
    if instance.file:
        instance.file.delete(save=False)
```

⚠️ **方式二会引入课 17 讲的隐式耦合**——`bulk_delete` / `queryset.delete()` **不会触发 signal**，所以批量删除仍然留下孤儿文件。选型时要知道这个代价。

### 2.13 上传的内存边界

实验 37 实测了 Django 的 handler 选择逻辑：

```text
FILE_UPLOAD_MAX_MEMORY_SIZE = 1048576 字节 (1.0 MB)
100KB 文件 → MemoryFileUploadHandler      （全在内存）
3MB 文件   → TemporaryFileUploadHandler   （写临时文件）
```

小于阈值走内存，大于阈值写 `/tmp`。**默认值是 2.5 MB**（本课实验里设成了 1 MB 做演示）。

这意味着：如果你的上传接口允许 100 MB 的文件，而 `FILE_UPLOAD_MAX_MEMORY_SIZE` 还是默认的 2.5 MB，那么超出的部分会写临时文件——**磁盘 IO 和临时目录空间**会成为瓶颈，而不是内存。

另一个相关的量是 `DATA_UPLOAD_MAX_MEMORY_SIZE`（整个请求体），超限会抛 `RequestDataTooBig` → **413**。

---

## 第三幕：Admin 定制与安全收敛

### 3.0 先回答：都前后端分离了，为什么还留着 Admin

**因为 Admin 从来不是"对外的页面"，它是"内部的数据管理界面"。**

课 1 就讲过：分离之后**退场的是模板渲染这套对外交付方式**，不是"服务端不能渲染页面"。Admin 自带模板体系，照用不误——它服务的是**运营、客服、你自己**，不是终端用户。

分离后的现实是：

| 需求 | 自己做 | 用 Admin |
|------|--------|---------|
| 运营改个订单状态 | 写一个后台 + 一套前端页面 + 权限 | `list_editable` 一行 |
| 客服查某笔交易 | 写查询页 + 分页 + 导出 | `search_fields` 一行 |
| 批量审核 | 写批量接口 + 前端多选 | 自定义 action 几行 |

**Admin 是"用 5% 的成本覆盖 80% 的内部管理需求"。** 前提是——**把它收敛好**。

### 3.1 谁能进 Admin：is_staff 是总开关

实验 21 的实测对照：

```text
alice : is_staff=False  → GET /admin/ → 302（重定向到登录页）
bob   : is_staff=True   → GET /admin/ → 200
```

**`is_staff=True` 就能进 Admin 首页，哪怕这个用户零权限。** 而 `is_staff=False` 的用户，哪怕给了所有权限也进不去（302）。

实验 22 接着测：

```text
bob（is_staff=True，零权限）访问 /admin/core/invoice/ → 403
给 view_invoice 后                                  → 200
```

所以是两级：

1. **`is_staff`** —— 能不能进 Admin 这个"门"（与具体权限无关）
2. **model 级权限**（`view/add/change/delete_xxx`）—— 能不能看某个模型

> **课 10 的回接**：`is_staff` / `is_superuser` 是 **Admin 的开关**，不是业务角色。
> 业务里的"管理员""审核员"应该自己建角色表或 Group，**不要复用 `is_staff`**——否则你给运营开 Admin 权限的同时，可能顺手给了他不该有的东西。

### 3.2 开通一个运营账号：最小步骤

知道两级权限之后，真要配人时按这个来：

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
user.is_staff = True      # ← 不加这个进不了 Admin，与组权限无关（实验 21）
user.save()

# ⚠️ 权限有缓存：改动后要重新取用户对象才看得到新权限
user = User.objects.get(pk=user.pk)
```

几个容易踩的点：

- **用 Group 而不是逐个加 permission**。人多了以后，逐个加必然出错，且无法回答"这个组能看到什么"。
- **`is_staff` 与组权限是两个独立开关**。实验 21 实测：只给权限不勾 `is_staff` → 302 进不去；只勾 `is_staff` 不给权限 → 能进首页但看列表 403。
- **`list_editable` 需要 `change` 权限**。只给 `view_invoice` 的话，列表页能看到，但行内编辑的表单不会出现。
- **`has_delete_permission` 返回 False 时，即使有 `delete` 权限也删不掉**。两级都要过——权限是"能不能"，`has_xxx_permission` 是额外的"要不要"。
- **改完权限要重新取用户对象**。Django 会缓存 `_perm_cache`，同一个对象实例上加了权限却读不到，是新手常见的困惑。

### 3.2 Admin 的 N+1：list_display 里的外键

这是一个**在小数据量下完全看不出来**的问题，也是必查项 #28 的典型场景。

实验 24 实测（30 条发票，`owner` 是外键）：

```text
list_display=['id','title','amount','status_badge','owner','created_at']
渲染列表页 SQL 次数 = 16

去掉 owner 后 SQL 次数      = 8
差额 = 8
```

**一个外键字段，在这个规模下就多了 8 次查询。** 注意这里 30 条数据只多了 8 次而不是 30 次——因为 Admin 默认分页（每页通常 100 条），且**同一个 owner 会被 Django 的身份映射缓存**。真实场景里 owner 各不相同，就是**每多一行多一次查询**。

实验 25 的修法：

```python
class InvoiceAdmin(admin.ModelAdmin):
    list_select_related = ["owner"]      # ← 一行修好
```

```text
加 list_select_related=['owner'] 后 = 8
```

> **必查项 #28 的判定**：示例给学员的练手数据量必须小到能跑（30 条刚好），
> 但示例**本身的写法**必须大到 10 万行也不炸。加 `list_select_related` 就是后者。

### 3.3 自定义 action：用 update()，不要逐条 save()

实验 26 走真实 HTTP 请求触发 action，实测：

```text
准备批量通过 30 条（走真实 HTTP 请求）
响应 = 200
通过 30 条 → SQL 次数 = 14
其中 UPDATE 语句 = 1 条
```

**30 行数据，1 条 UPDATE。** 这是对的写法：

```python
@admin.action(description="批量通过（所选）")
def mark_approved(self, request, queryset):
    updated = queryset.update(status="approved")     # ← 一条 SQL
    self.message_user(request, f"已通过 {updated} 条")
```

对照错误写法（必查项 #28 明确禁止）：

```python
@admin.action(description="批量通过（错误示范）")
def mark_approved_bad(self, request, queryset):
    for obj in queryset:          # ← 循环体里有数据库写操作
        obj.status = "approved"
        obj.save()                # ← N 次 UPDATE
```

10 万行时，前者 1 条 SQL，后者 10 万条。

⚠️ **但要注意**：`queryset.update()` **不触发 signal**、**不调用 `save()`**。如果你的模型在 `save()` 里埋了业务逻辑（课 17 的坑），`update()` 会绕开它。

这个取舍必须**明确做出**，而不是让它默认发生。决策表：

| 场景 | 选哪个 | 代价 |
|------|--------|------|
| 纯状态流转，无副作用 | `queryset.update()` | 快（1 条 SQL），但 signal 不触发 |
| 有审计 / 通知 / 缓存失效 | 逐条 `save()`，或 `update()` 后显式补做 | 慢（N 条 SQL），副作用不丢 |
| 数据量大到 `save()` 跑不动 | `update()` + 显式补做副作用 | 需自己保证一致性 |

**一句话记住**：**Admin 的 action 里选 `update()`，等于默认这批操作不需要 signal。** 如果有人在 `post_save` 里挂了审计日志（课 17 讲的典型用法），那么运营点一次"批量通过 30 条"，界面显示"已通过 30 条"，而**审计日志一条都没记**——同样不报错。

选 `update()` 还是 `save()`，本质是**要性能还是要副作用**，二者不可兼得——这与课 14/课 15 的结论完全一致。

### 3.4 安全收敛：三件事必须做

**① 删除权限收敛**

```python
def has_delete_permission(self, request, obj=None):
    return bool(request.user.is_superuser)
```

实验 27 实测：

```text
superuser 的 has_delete_permission = True
staff bob 的 has_delete_permission = False
```

**② 只读收敛**

```python
class RestrictedUserAdmin(UserAdmin):
    def get_readonly_fields(self, request, obj=None):
        ro = list(super().get_readonly_fields(request, obj) or [])
        if not request.user.is_superuser:
            ro += ["is_active", "is_staff", "is_superuser",
                   "groups", "user_permissions"]
        return ro
```

⚠️ 实验 29 确认了一个重要边界：**`readonly_fields` 是表单级收敛，不是数据库约束。**

```text
AttachmentAdmin.readonly_fields = ['size', 'content_type', 'created_at']
get_readonly_fields 返回        = ['size', 'content_type', 'created_at']
```

它挡住的是"通过 Admin 表单修改"。**直接改数据库、或通过 API 改，它一点用都没有。** 真正的约束要落在模型或数据库层（课 12 的 `CheckConstraint`）。

**③ 登录限流——Django 核心不做（第 17 处「不报错的错误」）**

实验 28 的实测：

```text
连续 12 次错误密码 → 状态码集合 = [200]
最后一次 = 200
```

**连错 12 次，全部返回 200，没有任何限流。** Admin 的登录页可以被无限次爆破。

这属于 Django 有意留下的空白（限流策略因部署而异）。补齐方式：

```python
# 方案一：装 django-axes
INSTALLED_APPS += ["axes"]
MIDDLEWARE += ["axes.middleware.AxesMiddleware"]
AUTHENTICATION_BACKENDS = [
    "axes.backends.AxesStandaloneBackend",   # 必须放第一个
    "django.contrib.auth.backends.ModelBackend",
]
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 1  # 小时

# 方案二：在网关/Nginx 层限流（推荐，覆盖所有入口）
# limit_req_zone $binary_remote_addr zone=adminlogin:10m rate=5r/m;
```

### 3.5 Admin 权限 ≠ API 权限，但会被复用

实验 30 的实测：

```text
DjangoModelPermissions.perms_map['GET'] = []
bob 有 view_invoice   = True
bob 有 change_invoice = False
```

**同一套 Django 权限，两张皮。** 如果你在 API 上用了 DRF 的 `DjangoModelPermissions`（课 9 讲过），那么**你在 Admin 里给某人加的 `change_invoice` 权限，等于同时给 API 的写操作开了口子**。

```python
class InvoiceViewSet(ModelViewSet):
    permission_classes = [DjangoModelPermissions]   # ← 复用 Django 权限
```

给运营开权限前，先确认这个模型的 API 有没有用 `DjangoModelPermissions`。

### 3.6 Admin 定制的完整示例

```python
from django.contrib import admin
from django.utils.html import format_html

from apps.core.models import Invoice


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    """运营后台：发票审核"""

    list_display = ["id", "title", "amount", "status_badge", "owner", "created_at"]
    list_display_links = ["id", "title"]
    list_filter = ["status", "created_at"]
    search_fields = ["title", "note"]
    list_editable = ["status"]
    list_per_page = 20
    list_select_related = ["owner"]          # ← 治 N+1
    date_hierarchy = "created_at"
    ordering = ["-created_at"]
    actions = ["mark_approved", "mark_rejected"]

    @admin.display(description="状态", ordering="status")
    def status_badge(self, obj):
        color = {"pending": "#999", "approved": "#2a7", "rejected": "#c33"}.get(obj.status)
        return format_html('<b style="color:{}">{}</b>', color, obj.get_status_display())

    @admin.action(description="批量通过（所选）")
    def mark_approved(self, request, queryset):
        updated = queryset.update(status="approved")     # ← 一条 SQL，不是 N 条
        self.message_user(request, f"已通过 {updated} 条")

    def has_delete_permission(self, request, obj=None):
        return bool(request.user.is_superuser)           # ← 删除只对 superuser 开放
```

---

## 第四幕：staticfiles 的真实归属

### 4.1 分离之后，静态资源归谁

一句话结论：**业务前端的 JS/CSS/图片归前端，Django 的 `staticfiles` 只服务 Admin（和 DRF 的 browsable API）。**

实验 32 用 `collectstatic` 给出了硬证据：

```text
收集文件总数 = 157
其中 admin/  = 130  (83%)
非 admin 样例 = ['rest_framework/css/bootstrap-theme.min.css',
                'rest_framework/css/default.css',
                'rest_framework/css/font-awesome-4.0.3.css', ...]
```

**157 个文件里 130 个是 Admin 的，剩下 27 个是 DRF 的可浏览 API 的。** 你自己写的业务静态资源：**0 个**。

这就是为什么分离项目里 `STATICFILES_DIRS` 通常是空的——业务前端有自己的构建流程（Vite/webpack），产物由前端自己部署到 CDN，**根本不进 Django 的 `STATIC_ROOT`**。

### 4.2 三个目录的分工

| 配置 | 装的是什么 | 谁写进去 | 谁读 |
|------|-----------|---------|------|
| `STATICFILES_DIRS` | 你自己写的静态文件 | 你（分离后通常为空） | `collectstatic` |
| `STATIC_ROOT` | `collectstatic` 的**汇总输出** | `collectstatic` 命令 | Nginx / WhiteNoise |
| `MEDIA_ROOT` | **用户上传**的文件 | 运行时（上传接口） | 对象存储 / Nginx |

**`STATIC_ROOT` 和 `MEDIA_ROOT` 必须分开**，因为来源和安全级别完全不同：前者是**代码的一部分**（可重现），后者是**用户数据**（需备份、不可重现）。

### 4.3 DEBUG 开关：同一个 URL，两种命运

这是本课第一幕那个工单的答案。

实验 34（DEBUG=True）：

```text
上传 201，url = http://testserver/media/attachments/2026/09/03/dl.txt
DEBUG=True 下 GET /media/attachments/2026/09/03/dl.txt → 200
```

实验 33（DEBUG=False，独立进程）：

```text
[probe] DEBUG = False
[probe] GET /media/attachments/2026/09/03/probe/probe.txt → 404
```

**同一个 URL，DEBUG 一变，200 变 404。**

原因是这段代码：

```python
# config/urls.py
if settings.DEBUG:                                   # ← 魔鬼在这
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

`django.conf.urls.static()` 的文档第一句就是：**"仅用于开发环境"**。它在 `DEBUG=False` 时**根本不会被调用**，路由安静地消失。

生产环境的正解（三选一）：

| 方案 | 做法 | 适用 |
|------|------|------|
| Nginx 直接服务 | `location /media/ { alias /app/media/; }` | 单机部署 |
| 对象存储 | `STORAGES` 换成 S3/OSS/COS 后端 | 推荐，多实例部署必选 |
| 反向代理/CDN | `MEDIA_URL` 指向 CDN 域名 | 有 CDN 时 |

### 4.4 WhiteNoise 还需要吗

**看情况——但在纯前后端分离项目里，通常不需要。**

| 场景 | 需要吗 | 理由 |
|------|--------|------|
| 传统 Django 全栈项目 | ✅ 需要 | 业务静态资源也由 Django 服务 |
| 前后端分离 + 保留 Admin | ⚠️ 可选 | 只为 Admin 那 157 个文件引入一个中间件，通常用 Nginx 更划算 |
| 前后端分离 + Admin 也走 Nginx | ❌ 不需要 | `collectstatic` + Nginx 就够了 |
| 容器化、不想挂 volume | ✅ 需要 | WhiteNoise 可以把静态文件打进镜像 |

判断标准很简单：**你的业务静态资源还有没有走 Django？** 如果没有，那 WhiteNoise 就只是在服务 Admin——为一个内部后台引入生产中间件，收益不大。

如果确实要用，最小配置是这样：

```python
# settings.py
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",   # ← 紧跟 SecurityMiddleware，别放最后
    # ... 其它中间件
]

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        # 压缩 + manifest 命名，支持永久缓存
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}
```

⚠️ **一个反直觉的点**：**WhiteNoise 只服务 `STATIC_ROOT`，不服务 `MEDIA_ROOT`。**

所以它对**本课第一幕那个工单（上传文件下载 404）一点用都没有**——上传的文件在 `MEDIA_ROOT` 里，不在 WhiteNoise 的管辖范围。要服务用户上传的文件，还是得靠 Nginx、对象存储，或者给 WhiteNoise 额外配 `WHITENOISE_ROOT`（不推荐——用户数据混进静态资源目录，安全和备份都难做）。

### 4.5 静态资源的三个检查点

```bash
# ① 确认 staticfiles 后端真的生效（别只看 settings）
python manage.py shell -c \
  "from django.core.files.storage import storages; print(type(storages['staticfiles']).__name__)"

# ② collectstatic 之后核对数量，别只看"命令没报错"
python manage.py collectstatic --noinput
find var/staticfiles -type f | wc -l

# ③ 生产环境实际访问一次 Admin 的 CSS，确认 200
curl -sI https://your-domain/static/admin/css/base.css | head -1
```

第 ③ 步最容易漏——`collectstatic` 成功**不等于** Web 服务器配置对了。

---

## 第五幕：体系收束

### 5.1 三个知识点的决策表

| 决策点 | 选 A | 选 B | 本课建议 |
|--------|------|------|---------|
| 文件存哪 | 本地 `MEDIA_ROOT` | 对象存储 | 单机/内部系统用 A；多实例、需要 CDN 用 B |
| 上传接口 | 挂在 ModelViewSet 上 | 独立上传接口 | **独立接口**——上传与业务创建是两件事 |
| 文件名 | 用原文件名 | 让 storage 生成 | **让 storage 生成**，另存 `original_name` 字段 |
| 类型校验 | 看扩展名 | 读文件内容 | **扩展名做初筛 + 内容校验做确认** |
| `content_type` | 作为依据 | 仅作参考 | **仅作参考**（可伪造，实验 7） |
| 删记录时 | 只 `delete()` | 先删文件再删记录 | **先删文件**（实验 17/18 的孤儿文件） |
| `list_display` 外键 | 直接放 | 配 `list_select_related` | **配 `list_select_related`**（16→8 次 SQL） |
| 批量 action | 逐条 `save()` | `queryset.update()` | **`update()`**（1 条 vs N 条 SQL） |
| 登录限流 | 不管 | django-axes 或网关层 | **必须补**（Django 核心不做，实验 28） |
| 静态资源 | Django 服务 | Nginx / CDN | 业务归前端；Admin 用 Nginx 或对象存储 |

### 5.2 本课踩到的「不报错的错误」（第 14-17 处）

| # | 现象 | 为什么危险 | 出处 |
|---|------|-----------|------|
| 14 | 同名文件被静默改名（201 + 随机后缀） | 假设"文件名=原名"的代码静默失效 | 实验 3、4 |
| 15 | 忘配 `MultiPartParser` 时，不碰 `request.data` 返回 **200** | 文件压根没处理，但接口"成功"了 | 实验 9 |
| 16 | 删数据库记录，磁盘文件 100% 残留 | 磁盘缓慢增长，查不到原因 | 实验 17、18 |
| 17 | Admin 登录连错 12 次全部 200，无限流 | 后台可被无限爆破 | 实验 28 |

### 5.3 高频误区对照表

| 误区 | 真相 | 出处 |
|------|------|------|
| "文件存在数据库里" | 只存**相对路径字符串**，字节在 storage | 2.1 |
| "`default_storage` 就是后端实例" | 是**惰性代理**，打印类名得到 `DefaultStorage` | 实验 1 |
| "同名文件会冲突报错" | **不报错**， storage 静默加 7 位随机后缀 | 实验 3、4 |
| "`content_type` 能拦住伪造" | 纯客户端声明，文本改名 `.png` 照样 201 | 实验 7 |
| "`ImageField` 会校验图片内容" | 只在**显式调用** Pillow 解析时；字段本身不校验 | 实验 8 |
| "传 multipart 给 JSON 接口会 415" | **只有访问 `request.data` 时才 415** | 实验 9 |
| "漏配 `staticfiles` 键有默认值" | **没有**，抛 `InvalidStorageError`（且访问时才抛） | 实验 12 |
| "`S3Boto3Storage` 是标准类名" | 1.14 里已改名 `S3Storage`，旧名直接 ImportError | 实验 15c |
| "装 django-storages 就有 S3 能力" | **不会自动装 boto3**，缺了报 ImproperlyConfigured | 实验 15b |
| "删了记录文件就没了" | **残留 100%**，孤儿文件 | 实验 17、18 |
| "`is_staff` 等于有权限" | `is_staff` 只是"能不能进门"，与权限无关 | 实验 21、22 |
| "Admin 登录有防爆破" | **Django 核心不限流**，连错 12 次全 200 | 实验 28 |
| "`readonly_fields` 是硬约束" | 只是**表单级**，API 和直接改库都绕得过去 | 实验 29 |
| "`collectstatic` 收的是业务静态资源" | 实测 83% 是 Admin 的，业务资源 **0 个** | 实验 32 |
| "分离后不需要 WhiteNoise" | 取决于**是否还有业务静态资源走 Django** | 4.4 |

### 5.4 自检题（做完再看答案）

1. 运营说"我上传的同名文件怎么找不到了"，数据库里 `original_name` 明明是对的。文件去哪了？
2. 你的上传接口配了 `parser_classes = [MultiPartParser]`，但线上偶尔有"上传成功但没文件"的反馈。最可能的原因是什么？
3. 生产环境 `DEBUG=False`，用户上传成功但下载 404。你会怎么排查（给出至少三步）？
4. 你给运营开了 `is_staff=True` 和 `change_invoice` 权限。这还可能影响哪里？

<details>
<summary>答案</summary>

1. 文件**没有丢**。同名文件第二次上传时，storage 会加 7 位随机后缀（`report_WawkC7Q.txt`），数据库里 `file` 字段存的是**新名字**，而 `original_name` 保留原名。用 `obj.file.name` 或 `obj.file.url` 去拿，不要自己拼 `upload_to + original_name`（实验 3）。

2. 最可能是**某个分支提前 return，没访问 `request.data`**。DRF 的解析是懒加载的，不访问就不解析、也不报错，直接走完返回 200（实验 9）。排查：确认视图函数第一行就取 `request.FILES`；检查有没有 `if` 分支在取文件之前返回。

3. 三步：① `ls` 确认文件真在 `MEDIA_ROOT` 下；② 检查 `urls.py` 里 `static(...)` 是否被 `if settings.DEBUG` 包着（DEBUG=False 时这段路由**根本不存在**，实验 33）；③ 确认生产是谁在服务 `/media/`——Nginx 的 `alias` 配了没有，或者 `STORAGES` 是否已经换成对象存储后端。补充一步：`curl -I` 实际访问一次，别只看配置。

4. 可能影响 **API 的写权限**。如果 `Invoice` 的 API 用了 DRF 的 `DjangoModelPermissions`（课 9），它复用的正是 Django 同一套权限——`change_invoice` 会同时给 API 的 PUT/PATCH 开口子（实验 30）。另外 `is_staff=True` 意味着他能进 Admin 首页，建议同时确认 `has_delete_permission` 等收敛是否到位。

</details>

---

## 事实来源标注（必查项 #22）

| 结论 | 来源 | 说明 |
|------|------|------|
| `STORAGES` 双键结构、`OPTIONS` 传参 | 📘 官方文档（Django 4.2 release notes / settings 参考） | 文档明示 |
| `default_storage` 是 `LazyObject` | ⚙️ 源码 + 🧪 实测 | 源码为 `LazyObject` 子类；实测打印类名得 `DefaultStorage` |
| 同名文件加 7 位随机后缀 | 🧪 实测（实验 3、4） | 文档只说"会加后缀"，**形态与长度属实现行为**，升级大版本需重验 |
| `content_type` 可伪造 | 🧪 实测（实验 7） | 文档明示它是客户端声明的值 |
| 不访问 `request.data` 不抛 415 | ⚙️ 源码 `request.py:353-356` + 🧪 实测（实验 9） | 懒加载是源码可验证的设计 |
| 漏配 `staticfiles` 抛 `InvalidStorageError` | 🧪 实测（实验 12） | ⚠️ 我原以为有默认值兜底，**实测被推翻** |
| `S3Boto3Storage` → `S3Storage` 改名 | 🧪 实测（实验 15c） | 属第三方库变更，教程易过时 |
| 缺 boto3 报 `ImproperlyConfigured` | 🧪 实测（实验 15b） | 属实现行为，但报错信息明确 |
| 删记录不删文件 | 🧪 实测（实验 17、18） | 文档明示 Django 不自动删文件 |
| `is_staff` 是 Admin 总开关 | 📘 文档 + 🧪 实测（实验 21、22） | 文档明示 `is_staff` 决定能否访问 Admin |
| Admin 登录无限流 | 🧪 实测（实验 28） | Django 核心确实不提供；文档未承诺限流 |
| `readonly_fields` 是表单级 | 🧪 实测（实验 29） | 文档明示它影响表单渲染 |
| `collectstatic` 收集内容构成 | 🧪 实测（实验 32，157 个文件 / 83% admin） | 数字与你的 `INSTALLED_APPS` 相关 |
| `static()` 仅用于开发环境 | 📘 官方文档 | 文档明示 |
| `list_select_related` 治 N+1 | 📘 文档 + 🧪 实测（实验 24、25） | 16 → 8 次 SQL 为实测 |

> 标注为 🧪 实测的条目，其中"实现行为"部分（如后缀长度、文件数量）**不是契约保证**，升级 Django 大版本后需重新验证。

---

## 验证环境

| 项 | 值 |
|----|-----|
| 操作系统 | Windows 11（PowerShell 5.1） |
| Python | 3.13.14（`C:\Users\v_wypgwu\.workbuddy\binaries\python\envs\dj-course`） |
| Django | 6.1 |
| DRF | 3.18.0 |
| Pillow | 12.3.0 |
| django-storages | 1.14.6 |
| boto3 | 1.43.87 |
| 数据库 | SQLite（测试库，每次重建） |
| 实验工程 | `%TEMP%/dj-lesson19-demo/filelab`（**仓库外**） |
| 跑法 | `$env:PYTHONIOENCODING="utf-8"` 后 `python count_assertions.py` |

**⚠️ 受限披露（必查项 #20）**：

1. **未用 WSL** —— 与课 2 之后各课一致，本机 WSL 被安全策略拦截，全部实验在 Windows 托管 Python 上完成。命令均为 PowerShell 形式。
2. **对象存储未真实联网** —— `S3Storage` 只做到"可导入 + 可构造"，**未发起真实 S3 请求**（无凭证、无 bucket）。URL 语义变化用 `FakeS3Storage` 模拟。真实对象存储的签名、ACL、分段上传行为**不在本课验证范围**。
3. **Admin 页面只测行为不测渲染** —— 用 HTTP 状态码与 SQL 次数断言，**未截图核对页面外观**（必查项 #15：Admin 模板体系不在本课范围）。
4. **未测真实并发上传** —— 同名文件冲突、目录遍历均为串行验证。

**环境坑（已踩，供复现参考）**：

1. Windows 控制台默认 GBK，中文输出必炸 `UnicodeEncodeError`。**跑之前先设** `$env:PYTHONIOENCODING="utf-8"`。
2. `MEDIA_ROOT` 每次跑要换新目录——文件落在**真实磁盘**上，测试数据库回滚管不到。实验脚本用 `tempfile.mkdtemp` + 环境变量 `DJ_LAB19_MEDIA_ROOT` 解决。
3. **自定义 storage 必须放独立模块**。`STORAGES` 的 `BACKEND` 是点分路径字符串，Django 会 `import_string` 它；定义在实验脚本里会导致脚本被**重新执行一遍**（实测报 `setup_test_environment() was already called`）。
4. **独立进程探针要用 `os.environ[...] = ` 赋值，不能用 `setdefault`**——父进程若已导出 `DJANGO_SETTINGS_MODULE`，`setdefault` 会安静沿用旧值，探针跑在错误配置上（实测 `DEBUG` 打印出 `True`）。

---

## 实验工程说明

工程位于 `%TEMP%/dj-lesson19-demo/filelab`（**在课程仓库外**）：

```text
filelab/
├── config/
│   ├── settings.py            主配置（STORAGES / MEDIA / 上传限制）
│   ├── settings_prod.py       DEBUG=False（独立进程探针用）
│   ├── urls.py                Admin + API + static()
│   └── wsgi.py
├── apps/
│   ├── labkit.py              Check 断言器 / make_png / make_svg_bytes / dir_size
│   ├── core/                  模型（Attachment / Avatar / Invoice）、序列化器、视图
│   └── ops/admin.py           Admin 定制与安全收敛
├── lab_storages.py            自定义 storage（必须独立模块，见上文坑 3）
├── run_lab1.py                实验 1-10   文件上传与 STORAGES
├── run_lab2.py                实验 11-20  STORAGES 切换与对象存储
├── run_lab3.py                实验 21-30  Admin 定制与安全收敛
├── run_lab4.py                实验 31-42  staticfiles 归属与生产陷阱
├── probe_debug_false.py       独立进程：DEBUG=False 下 /media/ 可达性
├── probe_collectstatic.py     独立进程：collectstatic 收集了什么
└── count_assertions.py        全量回归 + 统计
```

跑法：

```powershell
$env:PYTHONIOENCODING="utf-8"; $env:PYTHONUTF8="1"
cd "$env:TEMP\dj-lesson19-demo\filelab"
& "C:\Users\v_wypgwu\.workbuddy\binaries\python\envs\dj-course\Scripts\python.exe" count_assertions.py
```

预期输出：

```text
  ✅ run_lab1.py      通过  27，失败   0   退出码 0
  ✅ run_lab2.py      通过  17，失败   0   退出码 0
  ✅ run_lab3.py      通过  14，失败   0   退出码 0
  ✅ run_lab4.py      通过  17，失败   0   退出码 0
  ✅ probe_debug_false.py 退出码 0
  ✅ probe_collectstatic.py 退出码 0
实验编号数（去重） = 42
断言总数           = 75
✅ 全量回归通过
```

---

## 🚀 下一批接力提示词

> 下一课：课 20《测试提速与文档》（仍在本阶段，阶段 6 共 5 课）。
>
> 带上这三个问题：
> 1. **"能跑"不等于"跑得快"** —— 本课验证了文件与 Admin 的行为，课 20 要解决"这些验证怎么跑得动"。测试变慢的根因往往不是测试本身，而是数据库与 IO（本课实验 24 的 N+1、实验 18 的孤儿文件都是前车之鉴）
> 2. **文档的归属** —— 本课结束时，`MEDIA_ROOT` / `STATIC_ROOT` / storage 后端这三处配置散落在 settings 里。课 20 讲 API 文档时，请回看本课 2.3 节"打印真实生效值"的思路——**文档的字段说明同样要来自真实响应，而不是手写**
> 3. **Admin 的文档化** —— Admin 是内部后台，它的操作约定（谁能删、批量操作会不会触发 signal）需要写进文档，否则运营会踩本课实验 26 提到的"`update()` 不触发 signal"这类坑
>
> 提示：本课实验工程在 `%TEMP%/dj-lesson19-demo/filelab`，`apps/labkit.py` 里的 `Check` 断言器、`make_png`、`dir_size` 可直接复用。
>
> ⚠️ 环境提醒：Windows 下跑实验前必须设 `$env:PYTHONIOENCODING="utf-8"`，否则中文输出会 `UnicodeEncodeError`。

---

## 🧭 课程导航

- ⬅️ 上一课：[课 18《中间件与请求链路》](./lesson-18-中间件与请求链路.md)
- ➡️ 下一课：[课 20《测试提速与文档》](./lesson-20-测试提速与文档.md)
- 📖 阶段概览：[阶段 6：工程化与生产](../overview.md)
- 📚 课程目录：[02-课程目录.md](../../../02-课程目录.md)
- 🏠 学习路径：[01-学习路径总览.md](../../../01-学习路径总览.md)

> 📌 **阶段 6 进度**：课 18、19 已完成（2/5）。下一课为课 20《测试提速与文档》。
