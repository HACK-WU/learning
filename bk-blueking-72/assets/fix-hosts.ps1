$hosts = "C:\Windows\System32\drivers\etc\hosts"
$ip = "172.26.238.136"

Write-Output "=== 待处理的域名（已按 helmfile 核实）==="
$correct = @(
    "bknodeman.paas.example.com",
    "job.paas.example.com",
    "job-api.paas.example.com"
)
$wrong = @(
    "nodeman.paas.example.com",
    "jobapi.paas.example.com"
)

$lines = Get-Content $hosts -Encoding UTF8

Write-Output ""
Write-Output "=== 1. 删除我先前写错的条目 ==="
$kept = @()
$removed = 0
foreach ($l in $lines) {
    $drop = $false
    foreach ($w in $wrong) {
        if ($l -match [regex]::Escape($w)) { $drop = $true; $removed++ }
    }
    if (-not $drop) { $kept += $l }
}
Write-Output "  删除行数: $removed"
$kept | Set-Content $hosts -Encoding UTF8 -Force

Write-Output ""
Write-Output "=== 2. 追加正确条目（去重）==="
$lines2 = Get-Content $hosts -Encoding UTF8
$toAdd = @()
foreach ($c in $correct) {
    $hit = $false
    foreach ($l in $lines2) { if ($l -match [regex]::Escape($c)) { $hit = $true } }
    if ($hit) { Write-Output "  已存在跳过: $c" }
    else { $toAdd += "$ip  $c"; Write-Output "  待追加: $c" }
}
if ($toAdd.Count -gt 0) { Add-Content -Path $hosts -Value $toAdd -Encoding UTF8 }

Write-Output ""
Write-Output "=== 3. 最终校验（监控 + 节点管理 + 作业）==="
Get-Content $hosts -Encoding UTF8 | Where-Object { $_ -match "bkmonitor|bknodeman|job\.|job-api" } | ForEach-Object { Write-Output "  $_" }

Write-Output ""
Write-Output "=== 4. 确认我写错的域名已不存在 ==="
foreach ($w in $wrong) {
    $still = Get-Content $hosts -Encoding UTF8 | Where-Object { $_ -match [regex]::Escape($w) }
    if ($still) { Write-Output "  仍存在(异常): $w" } else { Write-Output "  已清除: $w" }
}
