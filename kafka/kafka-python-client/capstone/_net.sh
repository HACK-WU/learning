for c in l9-kafka-1 l9-kafka-2 l9-kafka-3 l9-sr l11; do
  echo "--- $c ---"
  docker inspect "$c" --format '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{$v.IPAddress}}{{println}}{{end}}' 2>/dev/null
done
echo "=== 各网络成员数 ==="
for n in $(docker network ls --format '{{.Name}}'); do
  cnt=$(docker network inspect "$n" --format '{{len .Containers}}' 2>/dev/null)
  [ "${cnt:-0}" -gt 0 ] && echo "$n : $cnt"
done
