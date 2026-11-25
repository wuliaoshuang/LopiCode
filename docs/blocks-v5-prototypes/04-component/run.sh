#!/bin/bash
# 04 组件“待办列表”：在 Node 的假页面上真跑，两轮。用法：bash 04-component/run.sh
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
T=../03-frontend-lib/tool-f2; fail=0; mkdir -p out
one() { # 轮名 入口 库目录
  local name=$1 o=out/$1
  python3 $T/lcx_f2.py build $2 -o $o -L $3 -L ../03-frontend-lib/libs --target node --natives host/natives.json --host-dir host \
    --report $o.report.txt --dump-core $o.expanded.lcx > $o.build.log 2>&1 || { cat $o.build.log; return 2; }
  timeout 30 node $o/node/main.js > $o.node.txt 2> $o.node.err; echo "[04 $name] node 退出码 $?，错误输出 $(wc -l < $o.node.err) 行"
  grep "用到的宿主原生接口" $o.report.txt | sed "s/^/[04 $name] /"
  python3 $T/check_lines.py expected.txt $o.node.txt "04 $name node"
}
echo "—— 第 1 轮（组件只用 D 的甲类界面接口：读、写、当事件；预期有不过的，原样留档在 round1/RESULT-round1.txt）——"
one 第1轮 round1/app/main.lcx round1/libs > round1/RESULT-round1.txt 2>&1; cat round1/RESULT-round1.txt
if grep -q "04 第1轮 node\] 25 条检查，13 条等于" round1/RESULT-round1.txt; then echo "[04 第1轮] 和留档的一样：13/25"; else echo "[04 第1轮] 和留档的不一样"; fail=1; fi
echo "—— 第 2 轮（加了 4 个元素级宿主接口，用积木写了“画面库”）——"
one 第2轮 app/main.lcx libs || fail=1
[ -s out/第2轮.node.err ] && { echo "[04 第2轮] 错误输出不是空的："; cat out/第2轮.node.err; fail=1; }
exit $fail
