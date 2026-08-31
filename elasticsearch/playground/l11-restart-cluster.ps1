$ErrorActionPreference = "SilentlyContinue"

function Show-Step($msg) {
    Write-Output ""
    Write-Output "=============================================="
    Write-Output $msg
    Write-Output "=============================================="
}

# ---------- Step 1: record baseline ----------
Show-Step "STEP 1: BASELINE BEFORE RESTART"
curl.exe -s "http://localhost:9201/_cat/indices?v&s=index&h=index,docs.count,store.size" | Out-String
$totalBefore = (curl.exe -s "http://localhost:9201/_cat/count?v" | Select-String "count").ToString()
Write-Output "TOTAL DOCS: $totalBefore"
curl.exe -s "http://localhost:9201/_cluster/health?pretty" | Select-String "status"

# ---------- Step 2: stop all nodes ----------
Show-Step "STEP 2: STOP ALL 3 NODES"
$ports = @(9201, 9202, 9203)
foreach ($p in $ports) {
    $conns = Get-NetTCPConnection -LocalPort $p -State Listen
    foreach ($c in $conns) {
        $proc = Get-Process -Id $c.OwningProcess
        Write-Output "port $p -> PID $($proc.Id) [$($proc.ProcessName)] stopping"
        Stop-Process -Id $proc.Id -Force
    }
}
Start-Sleep -Seconds 8
foreach ($p in $ports) {
    $alive = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($alive) { Write-Output "port $p STILL LISTENING" } else { Write-Output "port $p released" }
}

# ---------- Step 3: start all nodes ----------
Show-Step "STEP 3: START ALL 3 NODES"
$base = "D:\projects\learning\elasticsearch\playground\l9-cluster"
foreach ($n in @("node-1", "node-2", "node-3")) {
    $bat = Join-Path $base "$n\bin\elasticsearch.bat"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$bat`"" -WindowStyle Minimized
    Write-Output "$n starting..."
    Start-Sleep -Seconds 3
}

# ---------- Step 4: wait for green ----------
Show-Step "STEP 4: WAIT FOR CLUSTER"
$ok = $false
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 5
    $h = curl.exe -s "http://localhost:9201/_cluster/health"
    if ($h -match '"status":"green"') {
        Write-Output "GREEN after $($i * 5) seconds"
        $ok = $true
        break
    }
    if ($h -match '"status":"yellow"') { Write-Output "attempt ${i}: yellow" }
    elseif ($h -match '"status":"red"') { Write-Output "attempt ${i}: red" }
    else { Write-Output "attempt ${i}: not up yet" }
}
if (-not $ok) { Write-Output "!! CLUSTER DID NOT REACH GREEN" }

curl.exe -s "http://localhost:9201/_cat/nodes?v"
curl.exe -s "http://localhost:9201/_cluster/health?pretty"

# ---------- Step 5: verify path.repo in effect ----------
Show-Step "STEP 5: VERIFY path.repo NOW IN EFFECT"
curl.exe -s "http://localhost:9201/_nodes/settings?pretty" | Select-String -Pattern "path.repo" -Context 0,2

# ---------- Step 6: compare doc counts ----------
Show-Step "STEP 6: DOC COUNT AFTER RESTART"
curl.exe -s "http://localhost:9201/_cat/indices?v&s=index&h=index,docs.count,store.size" | Out-String
$totalAfter = (curl.exe -s "http://localhost:9201/_cat/count?v" | Select-String "count").ToString()
Write-Output "TOTAL DOCS BEFORE: $totalBefore"
Write-Output "TOTAL DOCS AFTER : $totalAfter"
