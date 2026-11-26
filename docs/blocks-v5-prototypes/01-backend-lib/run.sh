#!/bin/bash
# 库“接口服务”：翻译 → 起 Node / Python 两个服务 → 打 135 条现有一致性样本 → 对比。用法：bash 01-backend-lib/run.sh
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
fail=0
P=${LC_PROTO_PORT_BASE:-18100}   # 端口从哪儿数起（回归测试会换一个，免得两处同时跑撞端口）
one() {  # 名字 轮次 源码目录 输出目录 Node端口 Python端口
  python3 ../tool/lcx.py build $3/app/main.lcx -o $4 -L $3/libs --round $2 --dump-core $4/expanded.lcx --report $4/report.txt > $4.log 2>&1 || { cat $4.log; fail=1; return; }
  python3 ../tool/httpcheck.py --cases cases.json --logs expected-logs.json --name "$1" \
    --server "node:$5:node $4/node/main.js" --server "python:$6:python3 $4/python/main.py" || fail=1
}
mkdir -p out
one "01 接口服务·第1轮" 1 round1 out/round1 $((P+11)) $((P+12))
one "01 接口服务·第2轮" 2 . out/round2 $((P+1)) $((P+2))
echo "[01 探针] 很多请求同时往集合里加东西（第 1 轮的 Python 服务是“取出来→改→放回去”三步，按道理会撞；看这次撞没撞出来）："
timeout 90 python3 race_check.py "第1轮 python" $((P+21)) "python3 out/round1/python/main.py" || fail=1
timeout 90 python3 race_check.py "第2轮 python" $((P+22)) "python3 out/round2/python/main.py" || fail=1
exit $fail
