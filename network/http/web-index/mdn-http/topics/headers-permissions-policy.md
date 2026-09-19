# headers-permissions-policy（MDN HTTP · 共 51 条）

> 范围：/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy · 生成日期：2026-09-10 · 来源：站点 sitemap
> 按站点二级目录拆出（Permissions-Policy 首部 + 各指令子页，站点原结构）
> 各指令统一回答的问题：「这个浏览器能力允许哪些源（自身/指定源/*）使用」

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看 Permissions-Policy 总览与指令清单（第三方 iframe 权限怎么收） | [Permissions-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy) | | 权限策略、iframe、委托 | [只上报模式](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy-Report-Only) |
| 查加速度传感器授权 | [accelerometer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/accelerometer) | | 传感器、加速度 | |
| 查环境光传感器授权 | [ambient-light-sensor](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/ambient-light-sensor) | | 光线、传感器 | |
| 查无障碍播报 API 授权 [待确认] | [aria-notify](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/aria-notify) | | 无障碍、播报 | |
| 查广告归因授权 | [attribution-reporting](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/attribution-reporting) | | 归因、广告 | |
| 查自动播放授权（配 gesture 限制） | [autoplay](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/autoplay) | | 自动播放、媒体 | |
| 查蓝牙授权 | [bluetooth](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/bluetooth) | | 蓝牙、WebBLE | |
| 查兴趣画像（Topics）授权 [待确认] | [browsing-topics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/browsing-topics) | | Topics、广告 | |
| 查摄像头授权 | [camera](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/camera) | | 摄像头、getUserMedia | |
| 查录屏表面选择授权 [待确认] | [captured-surface-control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/captured-surface-control) | | 录屏、共享 | |
| 查高熵客户端提示打包授权 | [ch-ua-high-entropy-values](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/ch-ua-high-entropy-values) | | 高熵提示 | |
| 查计算压力感知授权 [待确认] | [compute-pressure](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/compute-pressure) | | 负载感知 | |
| 查跨域隔离状态暴露授权 [待确认] | [cross-origin-isolated](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/cross-origin-isolated) | | 隔离、SharedArrayBuffer | |
| 查延迟取书签类存储访问授权 [待确认] | [deferred-fetch](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/deferred-fetch) | | 存储访问、fetch 配额 | |
| 查延迟取（最小配额）授权 [待确认] | [deferred-fetch-minimal](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/deferred-fetch-minimal) | | 存储访问、配额 | |
| 查屏幕内容选取授权 | [display-capture](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/display-capture) | | 录屏、getDisplayMedia | |
| 查加密媒体（DRM）授权 | [encrypted-media](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/encrypted-media) | | DRM、EME | |
| 查全屏授权 | [fullscreen](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/fullscreen) | | 全屏 | |
| 查游戏手柄授权 | [gamepad](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gamepad) | | 手柄 | |
| 查地理定位授权（含精度控制） | [geolocation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/geolocation) | | 定位、精度 | |
| 查陀螺仪授权 | [gyroscope](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gyroscope) | | 传感器、陀螺仪 | |
| 查 HID 设备授权 | [hid](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/hid) | | HID、外设 | |
| 查联邦身份凭据获取授权 [待确认] | [identity-credentials-get](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/identity-credentials-get) | | 联邦登录、身份 | |
| 查空闲状态感知授权 | [idle-detection](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/idle-detection) | | 空闲、检测 | |
| 查端侧语言检测授权 [待确认] | [language-detector](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/language-detector) | | 端侧 AI、翻译 | |
| 查端侧语言模型授权 [待确认] | [language-model](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/language-model) | | 端侧 AI、Prompt API | |
| 查本地字体访问授权 | [local-fonts](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/local-fonts) | | 字体、本机 | |
| 查本地网络设备访问授权 [待确认] | [local-network](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/local-network) | | 本地网络、内网 | |
| 查本地网络访问授权（新名） [待确认] | [local-network-access](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/local-network-access) | | 内网、CSRF 防护 | |
| 查回环地址访问授权 [待确认] | [loopback-network](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/loopback-network) | | 回环、localhost | |
| 查磁力计授权 | [magnetometer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/magnetometer) | | 传感器、磁力 | |
| 查麦克风授权 | [microphone](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/microphone) | | 麦克风、getUserMedia | |
| 查 MIDI 授权 | [midi](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/midi) | | MIDI、乐器 | |
| 查端侧语音识别授权 [待确认] | [on-device-speech-recognition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/on-device-speech-recognition) | | 语音、端侧 | |
| 查一次性凭据授权（WebOTP 等） | [otp-credentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/otp-credentials) | | 短信验证码、WebOTP | |
| 查支付授权（Payment Request） | [payment](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/payment) | | 支付、PaymentRequest | |
| 查画中画授权 | [picture-in-picture](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/picture-in-picture) | | 画中画、视频 | |
| 查私有状态令牌签发授权 [待确认] | [private-state-token-issuance](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/private-state-token-issuance) | | 信任令牌、签发 | |
| 查私有状态令牌兑换授权 [待确认] | [private-state-token-redemption](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/private-state-token-redemption) | | 信任令牌、兑换 | |
| 查公钥凭据创建授权（passkey 创建） | [publickey-credentials-create](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/publickey-credentials-create) | | passkey、WebAuthn | |
| 查公钥凭据获取授权（passkey 登录） | [publickey-credentials-get](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/publickey-credentials-get) | | passkey、WebAuthn | |
| 查屏幕常亮授权 | [screen-wake-lock](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/screen-wake-lock) | | 常亮、WakeLock | |
| 查串口授权 | [serial](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/serial) | | 串口、外设 | |
| 查共享屏幕音频授权 [待确认] | [speaker-selection](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/speaker-selection) | | 扬声器、选择 | |
| 查第三方 cookie 存储访问授权 | [storage-access](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/storage-access) | | 存储访问、第三方 cookie | |
| 查端侧摘要生成授权 [待确认] | [summarizer](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/summarizer) | | 端侧 AI、摘要 | |
| 查端侧翻译授权 [待确认] | [translator](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/translator) | | 端侧 AI、翻译 | |
| 查 USB 授权 | [usb](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/usb) | | WebUSB、外设 | |
| 查 Web Share 授权 | [web-share](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/web-share) | | 分享、系统分享 | |
| 查窗口管理授权 | [window-management](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/window-management) | | 多窗口、桌面 | |
| 查 XR 空间追踪授权 | [xr-spatial-tracking](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/xr-spatial-tracking) | | VR/AR、WebXR | |
