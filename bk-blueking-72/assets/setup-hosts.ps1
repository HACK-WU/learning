# 蓝鲸 7.2 CE · 本地访问 hosts 配置
# 用法：以「管理员身份」运行 PowerShell，执行本脚本
# 说明：所有 paas.example.com 域名解析到 WSL 的 ingress 网关（80 端口已通）

$ErrorActionPreference = "Stop"
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"

# 自动探测 WSL IP
$wslIP = (wsl.exe hostname -I).Trim().Split()[0]
if (-not $wslIP) {
    Write-Host "无法获取 WSL IP，请检查 WSL 是否运行" -ForegroundColor Red
    exit 1
}
Write-Host "探测到 WSL IP: $wslIP" -ForegroundColor Cyan

$domains = @(
    "paas.example.com",
    "bkpaas.paas.example.com",
    "apigw.paas.example.com",
    "bkapi.paas.example.com",
    "bkiam.paas.example.com",
    "bkiam-api.paas.example.com",
    "bkauth.paas.example.com",
    "bkrepo.paas.example.com",
    "static.bkrepo.example.com",
    "bkssm.paas.example.com",
    "bkuser.paas.example.com",
    "apps.paas.example.com",
    "docker.paas.example.com",
    "helm.paas.example.com",
    "svc-bkrepo.paas.example.com",
    "svc-mysql.paas.example.com",
    "svc-otel.paas.example.com",
    "svc-rabbitmq.paas.example.com",
    "lesscode.example.com"
)

# 备份
$backup = "$hostsPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $hostsPath $backup -Force
Write-Host "已备份 hosts -> $backup" -ForegroundColor Green

# 读取现有内容，剔除旧的蓝鲸条目（避免重复追加）
$existing = Get-Content $hostsPath -ErrorAction SilentlyContinue
$kept = $existing | Where-Object { $_ -notmatch 'paas\.example\.com|bkrepo\.example\.com|lesscode\.example\.com' }

# 写入
$newLines = @("", "# ===== 蓝鲸 7.2 CE 本地访问 (WSL IP: $wslIP) =====")
foreach ($d in $domains) { $newLines += "$wslIP  $d" }
$newLines += "# ===== 蓝鲸 end ====="

($kept + $newLines) | Set-Content $hostsPath -Encoding ASCII -Force
Write-Host "hosts 已写入 $($domains.Count) 条域名" -ForegroundColor Green
Write-Host ""
Write-Host "现在可以访问：" -ForegroundColor Yellow
Write-Host "  http://bkpaas.paas.example.com/    (蓝鲸 PaaS3 主入口)" -ForegroundColor White
