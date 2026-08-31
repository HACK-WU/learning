# Rebuild l9_trap2: high-cardinality dataset for multi-shard aggregation error demo
# Target: 1500 docs / 500 brands x 3 shards, per-shard cardinality >> default shard_size

Write-Output "===== STEP1 delete old index ====="
curl.exe -s -X DELETE 'http://localhost:9201/l9_trap2'
Write-Output ""

Write-Output "===== STEP2 create index (3 primary, 0 replica) ====="
$mapping = '{"settings":{"number_of_shards":3,"number_of_replicas":0},"mappings":{"properties":{"brand":{"type":"keyword"},"amount":{"type":"integer"}}}}'
curl.exe -s -X PUT 'http://localhost:9201/l9_trap2' -H 'Content-Type: application/json' -d $mapping
Write-Output ""

Write-Output "===== STEP3 generate 1500 docs ====="
$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt 1500; $i++) {
  $g = $i % 3
  $b = [math]::Floor($i / 3)
  $amt = $i % 100
  $id = "BRAND-" + $g + "-" + $b
  [void]$sb.AppendLine('{"index":{"_index":"l9_trap2","_id":"' + $i + '","routing":"R' + $g + '"}}')
  [void]$sb.AppendLine('{"brand":"' + $id + '","amount":' + $amt + '}')
}
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\l9_trap2_bulk.ndjson', $sb.ToString())
Write-Output "bulk file generated"

Write-Output "===== STEP4 bulk write ====="
curl.exe -s -X POST 'http://localhost:9201/l9_trap2/_bulk?refresh=true' -H 'Content-Type: application/x-ndjson' --data-binary '@D:\projects\learning\elasticsearch\playground\l9_trap2_bulk.ndjson' | Out-Null
Start-Sleep -Seconds 3

Write-Output ""
Write-Output "===== STEP5 verify count ====="
curl.exe -s 'http://localhost:9201/l9_trap2/_count'
Write-Output ""
Write-Output "===== STEP6 shard distribution ====="
curl.exe -s 'http://localhost:9201/_cat/shards/l9_trap2?v&h=index,shard,prirep,state,docs,node'
