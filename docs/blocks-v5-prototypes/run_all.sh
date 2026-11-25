#!/bin/bash
# 一键全跑：自测和探针 → 01 接口服务（两轮）→ 02 小框架（两轮）。输出同时存到 RESULT.txt。
# 用法：bash run_all.sh     （要 node 和 python3；端口用 18101–18212；起的服务跑完都按 pid 关掉）
cd "$(dirname "$0")" || exit 1
[ -f ~/workspace/tools/env.sh ] && source ~/workspace/tools/env.sh
{
  echo "运行时间：$(date '+%Y-%m-%d %H:%M:%S %Z')    node $(node --version)    $(python3 --version)"
  echo; echo "======== 一、翻译脚本自测和探针 ========"
  bash tool/selftest/run.sh; a=$?
  echo; echo "======== 二、01-backend-lib：库“接口服务” ========"
  bash 01-backend-lib/run.sh; b=$?
  echo; echo "======== 三、02-web-framework：库“小框架” ========"
  bash 02-web-framework/run.sh; c=$?
  echo; echo "======== 总结 ========"
  echo "自测：$([ $a = 0 ] && echo 通过 || echo 有问题)；01 接口服务：$([ $b = 0 ] && echo 通过 || echo 有问题)；02 小框架：$([ $c = 0 ] && echo 通过 || echo 有问题)"
} 2>&1 | tee RESULT.txt
