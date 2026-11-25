#!/bin/bash
# 03 前端小库（状态库＋事件总线库）：翻成 Node 和 Python（假宿主）真跑，两轮。用法：bash 03-frontend-lib/run.sh
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
T=tool-f2; fail=0; mkdir -p out
one() { # 轮名 源目录 --round
  local name=$1 src=$2 rnd=$3 o=out/$1
  python3 $T/lcx_f2.py build $src/app/main.lcx -o $o -L $src/libs --round $rnd --natives $src/host/natives.json --host-dir $src/host \
    --report $o.report.txt --dump-core $o.expanded.lcx > $o.build.log 2>&1 || { cat $o.build.log; return 2; }
  timeout 30 node $o/node/main.js > $o.node.txt 2> $o.node.err; echo "[03 $name] node 退出码 $?，错误输出 $(wc -l < $o.node.err) 行$( [ -s $o.node.err ] && echo "：$(head -1 $o.node.err)")"
  timeout 30 python3 $o/python/main.py > $o.python.txt 2> $o.python.err; echo "[03 $name] python 退出码 $?，错误输出 $(wc -l < $o.python.err) 行$( [ -s $o.python.err ] && echo "：$(head -1 $o.python.err)")"
  local r=0
  python3 $T/check_lines.py expected.txt $o.node.txt "03 $name node" || r=1
  python3 $T/check_lines.py expected.txt $o.python.txt "03 $name python" || r=1
  if [ "$rnd" = 3 ] && { [ -s $o.node.err ] || [ -s $o.python.err ]; }; then echo "[03 $name] 错误输出不是空的（第 2 轮应该是空的）"; r=1; fi
  if cmp -s $o.node.txt $o.python.txt; then echo "[03 $name] node 和 python 的输出逐字节相同"; else echo "[03 $name] node 和 python 的输出不同"; r=1; fi
  grep "核心表以外" $o.report.txt | sed "s/^/[03 $name] /"; grep "要“等”的函数单位" $o.report.txt | sed "s/^/[03 $name] /"
  return $r
}
echo "—— 第 1 轮（只用 F1 第 2 轮的核心；预期有不过的，原样留档在 round1/RESULT-round1.txt）——"
one 第1轮 round1 2 > round1/RESULT-round1.txt 2>&1; cat round1/RESULT-round1.txt
n1=$(grep -c "条等于手写的期望" round1/RESULT-round1.txt)
if grep -q "03 第1轮 node\] 48 条检查，6 条等于" round1/RESULT-round1.txt && grep -q "03 第1轮 python\] 48 条检查，45 条等于" round1/RESULT-round1.txt; then
  echo "[03 第1轮] 和留档的一样：node 6/48（跑到第 [3b] 条时程序死了），python 45/48"
else echo "[03 第1轮] 和留档的不一样"; fail=1; fi
echo "—— 第 2 轮（增补 call! / isSame / 懒值槽 以后）——"
one 第2轮 . 3 || fail=1
echo "—— 探针：把“要等的”处理函数交给事件总线（两种语言不一样，这就是要记的事）——"
python3 $T/lcx_f2.py build probes/async_handler.lcx -o out/probe -L libs --natives host/natives.json --host-dir host > out/probe.build.log 2>&1 || { cat out/probe.build.log; fail=1; }
echo "[03 探针] Node 的输出：";   timeout 30 node out/probe/node/main.js 2>&1 | sed 's/^/    /'
echo "[03 探针] Python 的输出："; timeout 30 python3 out/probe/python/main.py 2>&1 | sed 's/^/    /'
exit $fail
