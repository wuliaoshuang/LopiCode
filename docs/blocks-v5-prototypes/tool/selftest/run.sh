#!/bin/bash
# 翻译脚本的自测 ＋ 两个探针。用法：bash tool/selftest/run.sh
cd "$(dirname "$0")/../.." || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
OUT=${LC_PROTO_TMP:-/tmp/v5-F1}/run; mkdir -p $OUT
fail=0
python3 tool/lcx.py build tool/selftest/features.lcx -o $OUT/self > $OUT/self.log 2>&1 || { cat $OUT/self.log; exit 1; }
node $OUT/self/node/main.js > $OUT/self.node.txt 2>&1
python3 $OUT/self/python/main.py > $OUT/self.python.txt 2>&1
lines=$(wc -l < tool/selftest/features.expected.txt)
if cmp -s $OUT/self.node.txt $OUT/self.python.txt && cmp -s $OUT/self.node.txt tool/selftest/features.expected.txt; then
  echo "[自测] 语言特性 $lines 行输出：Node 和 Python 逐字节相同，并且等于手写的期望 → 通过"
else
  echo "[自测] 不一致："; diff $OUT/self.node.txt tool/selftest/features.expected.txt | head -10; diff $OUT/self.node.txt $OUT/self.python.txt | head -10; fail=1
fi
for p in objects async_predicate; do
  python3 tool/lcx.py build tool/probes/$p.lcx -o $OUT/probe_$p > $OUT/probe_$p.log 2>&1 || { cat $OUT/probe_$p.log; fail=1; continue; }
  echo "[探针 $p] Node 的输出："; node $OUT/probe_$p/node/main.js 2>&1 | sed 's/^/    /'
  echo "[探针 $p] Python 的输出："; python3 $OUT/probe_$p/python/main.py 2>&1 | sed 's/^/    /'
done
exit $fail
