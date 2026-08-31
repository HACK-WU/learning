# Shard-count comparison: same data, different shard counts
# Measure: took time, aggregation behavior, shard overhead

Write-Output "===== Create 3 indexes with same 3000 docs, different shard counts ====="

foreach ($n in @(1, 3, 50)) {
  $idx = "l10_shard_$n"
  curl.exe -s -X DELETE "http://localhost:9201/$idx" | Out-Null
  $m = '{"settings":{"number_of_shards":' + $n + ',"number_of_replicas":0},"mappings":{"properties":{"brand":{"type":"keyword"},"amount":{"type":"integer"}}}}'
  [System.IO.File]::WriteAllText("D:\projects\learning\elasticsearch\playground\l10_m_$n.json", $m)
  $r = curl.exe -s -X PUT "http://localhost:9201/$idx" -H 'Content-Type: application/json' --data-binary "@D:\projects\learning\elasticsearch\playground\l10_m_$n.json"
  Write-Output "created $idx : $r"
}
Write-Output ""

Write-Output "===== Write same 3000 docs to each (routing spread) ====="
foreach ($n in @(1, 3, 50)) {
  $idx = "l10_shard_$n"
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt 3000; $i++) {
    $brand = "BRAND-" + ($i % 30)
    [void]$sb.AppendLine('{"index":{"_index":"' + $idx + '","_id":"' + $i + '"}}')
    [void]$sb.AppendLine('{"brand":"' + $brand + '","amount":' + ($i % 100) + '}')
  }
  [System.IO.File]::WriteAllText("D:\projects\learning\elasticsearch\playground\l10_b_$n.ndjson", $sb.ToString())
  curl.exe -s -X POST "http://localhost:9201/$idx/_bulk?refresh=true" -H 'Content-Type: application/x-ndjson' --data-binary "@D:\projects\learning\elasticsearch\playground\l10_b_$n.ndjson" | Out-Null
  Write-Output "loaded 3000 docs into $idx"
}
Start-Sleep -Seconds 3
Write-Output ""

Write-Output "===== Compare: search latency (5 runs each) ====="
$q = '{"size":0,"aggs":{"top":{"terms":{"field":"brand","size":10}}}}'
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\l10_shard_q.json', $q)
foreach ($n in @(1, 3, 50)) {
  $idx = "l10_shard_$n"
  $times = @()
  for ($k = 0; $k -lt 5; $k++) {
    $res = curl.exe -s -X POST "http://localhost:9201/$idx/_search" -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_shard_q.json' | ConvertFrom-Json
    $times += $res.took
  }
  $avg = ($times | Measure-Object -Average).Average
  Write-Output "$idx : took avg = $avg ms  (runs: $($times -join ','))"
}
Write-Output ""

Write-Output "===== Shard sizes on disk ====="
curl.exe -s 'http://localhost:9201/_cat/indices/l10_shard_*?v&h=index,pri,docs.count,store.size'
Write-Output ""
Write-Output "===== Per-shard detail for l10_shard_50 ====="
curl.exe -s 'http://localhost:9201/_cat/shards/l10_shard_50?v&h=shard,prirep,docs,store,node' | Select-Object -First 8
