# Rigorous latency measurement: warm up first, then measure stable state
Write-Output "===== Warm up (10 runs, discarded) ====="
foreach ($n in @(1,3,50)) {
  $idx = "l10_shard_$n"
  for ($k=0; $k -lt 10; $k++) {
    curl.exe -s -X POST "http://localhost:9201/$idx/_search" -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_shard_q.json' | Out-Null
  }
  Write-Output "$idx warmed up"
}
Write-Output ""

Write-Output "===== Measure (20 runs each, after warm-up) ====="
foreach ($n in @(1,3,50)) {
  $idx = "l10_shard_$n"
  $times = @()
  for ($k=0; $k -lt 20; $k++) {
    $r = curl.exe -s -X POST "http://localhost:9201/$idx/_search" -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_shard_q.json' | ConvertFrom-Json
    $times += $r.took
  }
  $avg = [math]::Round(($times | Measure-Object -Average).Average,2)
  $min = ($times | Measure-Object -Minimum).Minimum
  $max = ($times | Measure-Object -Maximum).Maximum
  $med = ($times | Sort-Object)[[math]::Floor(20/2)]
  Write-Output "$idx : avg=$avg ms  median=$med ms  min=$min  max=$max"
}
Write-Output ""

Write-Output "===== Round 2 (repeat to check stability) ====="
foreach ($n in @(1,3,50)) {
  $idx = "l10_shard_$n"
  $times = @()
  for ($k=0; $k -lt 20; $k++) {
    $r = curl.exe -s -X POST "http://localhost:9201/$idx/_search" -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_shard_q.json' | ConvertFrom-Json
    $times += $r.took
  }
  $avg = [math]::Round(($times | Measure-Object -Average).Average,2)
  $med = ($times | Sort-Object)[[math]::Floor(20/2)]
  Write-Output "$idx : avg=$avg ms  median=$med ms"
}
Write-Output ""

Write-Output "===== Store sizes (after all writes settled) ====="
curl.exe -s 'http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,docs.count,store.size,pri.store.size'
Write-Output ""

Write-Output "===== Force merge then measure store size ====="
foreach ($n in @(1,3,50)) {
  curl.exe -s -X POST "http://localhost:9201/l10_shard_$n/_forcemerge?max_num_segments=1" | Out-Null
}
Start-Sleep -Seconds 5
curl.exe -s 'http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,docs.count,store.size,pri.store.size'
