# Build classic aggregation-trap dataset for l9_trap2
# Design: one brand (TRAP) is 2nd in EVERY shard but 1st globally
# routing map (probed): R0/RB/RD/RF->shard0, R1/R2/RA/RE/RG->shard1, RC->shard2

Write-Output "===== STEP1 delete and recreate ====="
curl.exe -s -X DELETE 'http://localhost:9201/l9_trap2' | Out-Null
curl.exe -s -X PUT 'http://localhost:9201/l9_trap2' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l9_trap2_mapping.json'
Write-Output "index created"
Write-Output ""

Write-Output "===== STEP2 generate docs ====="
# shard0 routing: R0 ; shard1 routing: R1 ; shard2 routing: RC
$routings = @('R0','R1','RC')
$sb = New-Object System.Text.StringBuilder
$docId = 0
for ($s = 0; $s -lt 3; $s++) {
  $rt = $routings[$s]
  # LEADER brand: 20 docs in this shard (so it is #1 within shard)
  for ($k = 0; $k -lt 20; $k++) {
    [void]$sb.AppendLine('{"index":{"_index":"l9_trap2","_id":"' + $docId + '","routing":"' + $rt + '"}}')
    [void]$sb.AppendLine('{"brand":"LEADER-' + $s + '","amount":' + $k + '}')
    $docId++
  }
  # TRAP brand: 9 docs in EVERY shard (2nd within each shard, but 27 total = global #1)
  for ($k = 0; $k -lt 9; $k++) {
    [void]$sb.AppendLine('{"index":{"_index":"l9_trap2","_id":"' + $docId + '","routing":"' + $rt + '"}}')
    [void]$sb.AppendLine('{"brand":"TRAP","amount":' + $k + '}')
    $docId++
  }
  # noise: 400 unique brands, 1 doc each -> pushes shard_size window
  for ($k = 0; $k -lt 400; $k++) {
    [void]$sb.AppendLine('{"index":{"_index":"l9_trap2","_id":"' + $docId + '","routing":"' + $rt + '"}}')
    [void]$sb.AppendLine('{"brand":"NOISE-' + $s + '-' + $k + '","amount":' + $k + '}')
    $docId++
  }
}
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\l9_trap2_bulk.ndjson', $sb.ToString())
Write-Output "total docs generated: $docId"
Write-Output ""

Write-Output "===== STEP3 bulk write ====="
curl.exe -s -X POST 'http://localhost:9201/l9_trap2/_bulk?refresh=true' -H 'Content-Type: application/x-ndjson' --data-binary '@D:\projects\learning\elasticsearch\playground\l9_trap2_bulk.ndjson' | Out-Null
Start-Sleep -Seconds 3

Write-Output ""
Write-Output "===== STEP4 shard distribution ====="
curl.exe -s 'http://localhost:9201/_cat/shards/l9_trap2?v&h=index,shard,prirep,state,docs,node'
Write-Output ""
Write-Output "===== STEP5 total count ====="
curl.exe -s 'http://localhost:9201/l9_trap2/_count'
