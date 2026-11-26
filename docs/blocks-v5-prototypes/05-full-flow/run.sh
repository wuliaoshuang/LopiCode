#!/bin/bash
# 05 完整流程：后端（小框架写的待办服务）翻成 Node、Python 各一份真起起来；前端（状态库＋画面库＋两个组件）在 Node 的假页面里跑，真发 HTTP。两轮。
# 用法：bash 05-full-flow/run.sh
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
T=../03-frontend-lib/tool-f2; fail=0; mkdir -p out
if [ -n "${LC_PROTO_PORT_BASE:-}" ]; then BASE=$((LC_PROTO_PORT_BASE + 200)); else BASE=$((18300 + RANDOM % 600)); fi; DEAD=$((BASE + 50))
# 后端：用 F1 的翻译脚本和 F1 的库，原样。
python3 ../tool/lcx.py build backend/main.lcx -o out/backend -L ../02-web-framework/libs --round 2 --report out/backend.report.txt > out/backend.build.log 2>&1 || { cat out/backend.build.log; exit 1; }
build_front() { # 轮名 接口库所在目录
  python3 $T/lcx_f2.py build frontend/app/main.lcx -o out/front-$1 -L $2 -L frontend/libs -L ../04-component/libs -L ../03-frontend-lib/libs --target node \
    --natives ../04-component/host/natives.json --host-dir ../04-component/host --report out/front-$1.report.txt > out/front-$1.build.log 2>&1 || { cat out/front-$1.build.log; exit 1; }
}
PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null; done' EXIT
serve() { # 语言 端口 → 起服务，等它说“已启动”
  local lang=$1 port=$2 log=out/server-$lang-$port.log
  if [ $lang = node ]; then PORT=$port HOST=127.0.0.1 node out/backend/node/main.js > $log 2>&1 &
  else PORT=$port HOST=127.0.0.1 PYTHONDONTWRITEBYTECODE=1 python3 -u out/backend/python/main.py > $log 2>&1 & fi
  SERVER_PID=$!; PIDS="$PIDS $SERVER_PID"
  for i in $(seq 1 100); do grep -q "后端已启动" $log && return 0; sleep 0.1; done
  echo "服务没起来：$lang $port"; cat $log; return 1
}
round() { # 轮名 端口偏移
  local name=$1 r=0 n=0
  for lang in node python; do
    n=$((n + 1)); local port=$((BASE + n + $2)) o=out/$name-对$lang服务
    serve $lang $port || return 2
    LC_API=http://127.0.0.1:$port LC_DEAD=http://127.0.0.1:$DEAD timeout 60 node out/front-$name/node/main.js > $o.txt 2> $o.err
    echo "[05 $name 对 $lang 服务] 前端退出码 $?，错误输出 $(wc -l < $o.err) 行"
    kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null
    python3 $T/check_lines.py expected.txt $o.txt "05 $name 对 $lang 服务" || r=1
  done
  if cmp -s out/$name-对node服务.txt out/$name-对python服务.txt; then echo "[05 $name] 对 Node 服务和对 Python 服务，前端的输出逐字节相同"; else echo "[05 $name] 对两个服务的输出不同"; r=1; fi
  return $r
}
build_front 第1轮 round1/libs; build_front 第2轮 /dev/null
echo "—— 第 1 轮（前端发请求只用 F1 的 net.fetch；预期有不过的，原样留档在 round1/RESULT-round1.txt）——"
round 第1轮 0 > round1/RESULT-round1.txt 2>&1; cat round1/RESULT-round1.txt
if [ "$(grep -c '15 条检查，11 条等于' round1/RESULT-round1.txt)" = 2 ] && grep -q "逐字节相同" round1/RESULT-round1.txt; then echo "[05 第1轮] 和留档的一样：对两个服务都是 11/15"; else echo "[05 第1轮] 和留档的不一样"; fail=1; fi
echo "—— 第 2 轮（换成 D 的“网络.请求”：不管状态码是多少都拿得到回应）——"
round 第2轮 10 || fail=1
for f in out/第2轮-对node服务.err out/第2轮-对python服务.err; do [ -s $f ] && { echo "[05 第2轮] 错误输出不是空的：$f"; cat $f; fail=1; }; done
exit $fail
