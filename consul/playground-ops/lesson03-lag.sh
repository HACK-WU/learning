#!/usr/bin/env bash
# 修正：State 是 $4（不是 $3）。重测陈旧窗口
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

peers() { consul operator raft list-peers 2>/dev/null | awk 'NR>1 && NF>=6'; }
LN=$(peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
FN=$(peers | awk '$4!="leader"{print $1}' | head -1 | grep -oE '[0-9]+$')
echo "leader=node$LN  follower=node$FN"
peers | awk '{printf "  %s %s\n",$1,$4}'

echo
echo "########## 陈旧窗口实测（3 轮）##########"
for round in 1 2 3; do
  curl -s -o /dev/null -X PUT -d "old-$round" "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
  sleep 1
  curl -s -o /dev/null -X PUT -d "NEW-$round" "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
  FOUND=""
  S=$(date +%s.%N)
  for t in $(seq 1 50); do
    R=$(curl -s --max-time 2 "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&stale")
    if [ "$R" = "NEW-$round" ]; then E=$(date +%s.%N); FOUND=$t; break; fi
  done
  if [ -n "$FOUND" ]; then
    python3 -c "print(f'  第$round 轮: stale 追上新值耗时 {$E-$S:.3f}s')"
  else
    echo "  第$round 轮: 5s 内未追上（读到 [$R]）"
  fi
  sleep 1
done

echo
echo "########## 对照：同一时刻 consistent 立即返回新值 ##########"
curl -s -o /dev/null -X PUT -d "AAA" "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"; sleep 1
curl -s -o /dev/null -X PUT -d "BBB" "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
echo -n "  follower stale      = "; curl -s "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&stale"; echo
echo -n "  follower consistent = "; curl -s "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&consistent"; echo

echo
echo "########## 陈旧窗口有多大（用 index 量化）##########"
curl -s -o /dev/null -X PUT -d "idx" "http://127.0.0.$LN:$((8500+LN))/v1/kv/idx/p"
for n in 1 2 3; do
  IS=$(curl -s -D- -o /dev/null "http://127.0.0.$n:$((8500+n))/v1/kv/idx/p?stale" | grep -i 'x-consul-index' | tr -d '\r' | awk '{print $2}')
  IC=$(curl -s -D- -o /dev/null "http://127.0.0.$n:$((8500+n))/v1/kv/idx/p?consistent" | grep -i 'x-consul-index' | tr -d '\r' | awk '{print $2}')
  ROLE=$(peers | awk -v x="ops-node-$n" '$1==x{print $4}')
  echo "  node$n ($ROLE): stale index=$IS  consistent index=$IC"
done
