Write-Output "===== FINAL: verify every corrected command actually runs ====="
Write-Output ""

Write-Output "--- 1. unlock.json + --data-binary ---"
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\unlock.json', '{"index.blocks.read_only_allow_delete": null}')
curl.exe -s -X PUT 'http://localhost:9201/l9_hi/_settings' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\unlock.json'
Write-Output ""

Write-Output "--- 2. explain.json + --data-binary ---"
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\explain.json', '{"index":"l9_hi","shard":0,"primary":true}')
curl.exe -s 'http://localhost:9201/_cluster/allocation/explain?pretty' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\explain.json' | Select-String -Pattern 'index|shard|can_allocate' | Select-Object -First 4
Write-Output ""

Write-Output "--- 3. Select-String UNASSIGNED (no grep) ---"
curl.exe -s 'http://localhost:9201/_cat/shards?v&h=index,shard,prirep,state,docs,node' | Select-String 'UNASSIGNED'
Write-Output "(empty = none, expected)"
Write-Output ""

Write-Output "--- 4. CMD escaped-quote variant ---"
cmd /c 'curl.exe -s "http://localhost:9201/_cluster/allocation/explain?pretty" -H "Content-Type: application/json" -d "{\"index\":\"l9_hi\",\"shard\":0,\"primary\":true}"' | Select-String -Pattern 'index|can_allocate' | Select-Object -First 3
Write-Output ""

Write-Output "--- 5. l10_mapping files + --data-binary ---"
foreach ($n in @(1,3,50)) {
  $m = '{"settings": {"number_of_shards": ' + $n + ', "number_of_replicas": 0}, "mappings": {"properties": {"brand": {"type": "keyword"}, "amount": {"type": "integer"}}}}'
  [System.IO.File]::WriteAllText("D:\projects\learning\elasticsearch\playground\l10_mapping_$n.json", $m)
}
curl.exe -s -X PUT 'http://localhost:9201/l10_verify_3' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\l10_mapping_3.json'
Write-Output ""

Write-Output "--- 6. agg_q.json + --data-binary ---"
[System.IO.File]::WriteAllText('D:\projects\learning\elasticsearch\playground\agg_q.json', '{"size":0,"aggs":{"top":{"terms":{"field":"brand","size":10}}}}')
curl.exe -s -X POST 'http://localhost:9201/l10_shard_3/_search' -H 'Content-Type: application/json' --data-binary '@D:\projects\learning\elasticsearch\playground\agg_q.json' | Select-String -Pattern 'doc_count' | Select-Object -First 2
Write-Output ""

Write-Output "--- 7. cleanup verify index ---"
curl.exe -s -X DELETE 'http://localhost:9201/l10_verify_3'
Write-Output ""

Write-Output "--- 8. final cluster health ---"
curl.exe -s 'http://localhost:9201/_cluster/health?pretty' | Select-String -Pattern 'status|unassigned|number_of_nodes'