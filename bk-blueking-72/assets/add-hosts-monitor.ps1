$hosts = "C:\Windows\System32\drivers\etc\hosts"
$ip = "172.26.238.136"
$entries = @(
    "bkmonitor.paas.example.com",
    "bkmonitor-ingester.paas.example.com",
    "nodeman.paas.example.com",
    "job.paas.example.com",
    "jobapi.paas.example.com"
)

Write-Output "=== 当前 hosts 中已有的监控/节点管理条目 ==="
$existing = Get-Content $hosts -Encoding UTF8
foreach ($e in $entries) {
    $hit = $existing | Select-String -Pattern [regex]::Escape($e) -SimpleMatch
    if ($hit) { Write-Output "  已存在: $e" } else { Write-Output "  缺失:   $e" }
}

Write-Output ""
Write-Output "=== 备份 hosts ==="
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $hosts "$hosts.bak-$ts" -Force
Write-Output "  已备份: hosts.bak-$ts"

Write-Output ""
Write-Output "=== 追加缺失条目 ==="
$toAdd = @()
foreach ($e in $entries) {
    $hit = $existing | Select-String -Pattern [regex]::Escape($e) -SimpleMatch
    if (-not $hit) { $toAdd += "$ip  $e" }
}
if ($toAdd.Count -eq 0) {
    Write-Output "  全部已存在，无需追加"
} else {
    Add-Content -Path $hosts -Value $toAdd -Encoding UTF8
    foreach ($l in $toAdd) { Write-Output "  已追加: $l" }
}

Write-Output ""
Write-Output "=== 追加后校验 ==="
Get-Content $hosts -Encoding UTF8 | Select-String -Pattern "bkmonitor|nodeman|job" | ForEach-Object { Write-Output "  $_" }
