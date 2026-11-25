#!/bin/bash
# 库“小框架”＋示例服务“小书店”：翻译 → 起 Node / Python 两个服务 → 打 39 条事先写好期望的请求 → 对比。用法：bash 02-web-framework/run.sh
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
fail=0
mkdir -p out
python3 ../tool/lcx.py build round1/app/main.lcx -o out/round1 -L round1/libs --round 1 --report out/round1/report.txt > out/round1.log 2>&1 || { cat out/round1.log; exit 1; }
echo "—— 第 1 轮（只用 v4 的核心）：预期第 17 条不过——标准库没法判断“这段文字是不是数字”（GAP-F1-07），日志第 17 行跟着不同 ——"
python3 ../tool/httpcheck.py --cases cases.json --logs expected-logs-round1.json --name "02 小框架·第1轮" \
  --server "node:18211:node out/round1/node/main.js" --server "python:18212:python3 out/round1/python/main.py" | grep -v "^  实际：" > out/round1.result.txt
cat out/round1.result.txt
# 第 1 轮“应该的样子”：两种语言各 38/39，不过的只有第 17 条，两种语言之间 39 条全相同。
if [ "$(grep -c '38 条等于写死的期望，1 条不等' out/round1.result.txt)" = 2 ] && [ "$(grep -c '第 17 条' out/round1.result.txt)" = 2 ] && grep -q '39 条相同，0 条不同' out/round1.result.txt; then
  echo "[02 小框架·第1轮] 和预期一样：只有第 17 条不过"
else
  echo "[02 小框架·第1轮] 和预期不一样"; fail=1
fi
echo "—— 第 2 轮（核心增补以后重写了校验、仓库、错误处理）——"
python3 ../tool/lcx.py build app/main.lcx -o out/round2 -L libs --round 2 --dump-core out/round2/expanded.lcx --report out/round2/report.txt > out/round2.log 2>&1 || { cat out/round2.log; exit 1; }
python3 ../tool/httpcheck.py --cases cases.json --logs expected-logs.json --name "02 小框架·第2轮" \
  --server "node:18201:node out/round2/node/main.js" --server "python:18202:python3 out/round2/python/main.py" > out/round2.result.txt; [ $? = 0 ] || fail=1
grep -v "用了 [0-9]* 毫秒" out/round2.result.txt
exit $fail
