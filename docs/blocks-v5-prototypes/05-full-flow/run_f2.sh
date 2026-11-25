#!/bin/bash
# 任务 F2 一键全跑：03 前端小库 → 04 组件 → 05 完整流程，各两轮。输出存到同目录的 RESULT-F2.txt。
# 用法：bash docs/blocks-v5-prototypes/05-full-flow/run_f2.sh
cd "$(dirname "$0")/.." || exit 1
OUT=05-full-flow/RESULT-F2.txt
fail=0
{
  echo "任务 F2 的全部原型，重跑于 $(date '+%Y-%m-%d %H:%M:%S %Z')；node $(node --version)，$(python3 --version)"
  for d in 03-frontend-lib 04-component 05-full-flow; do
    echo; echo "════════ $d ════════"
    bash $d/run.sh; code=$?
    echo "[$d] run.sh 退出码 $code"; [ $code = 0 ] || fail=1
  done
  echo; echo "════════ 汇总 ════════"
  if [ $fail = 0 ]; then echo "三个目录的 run.sh 都是 0：第 2 轮全部通过，第 1 轮的失败和留档的一样。"; else echo "有 run.sh 没过，见上面。"; fi
} > $OUT 2>&1
grep -E "条检查，|逐字节|和留档|退出码|汇总|都是 0|没过" $OUT | grep -v "^  "
exit $fail
