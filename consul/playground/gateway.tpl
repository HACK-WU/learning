# 由 consul-template 渲染：KV 变更 → 文件重写 → 触发 reload
retries = {{ key "web/api-gateway/retries" }}
timeout = "{{ keyOrDefault "web/api-gateway/timeout" "3s" }}"
