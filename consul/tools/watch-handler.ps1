$i = [Console]::In.ReadToEnd()
$m = [regex]::Match($i, '"CheckID":\s*"web-1-http"[\s\S]{0,200}?"Status":\s*"(\w+)"')
$status = if ($m.Success) { $m.Groups[1].Value } else { "no-match" }
Add-Content -Path "D:/projects/learning/consul/playground/watch-handler.log" -Value ("{0} handler fired: web-1-http = {1}" -f (Get-Date -Format "HH:mm:ss"), $status)
