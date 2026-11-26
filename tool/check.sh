#!/usr/bin/env bash
# 一键检查：排版 → 静态检查 → 架构守门 → 全量测试。提交前跑一遍，四步都过才算能提交。
#
# 用法：
#   tool/check.sh          全部跑
#   tool/check.sh --quick  只跑排版、静态检查、架构守门（几十秒），不跑全量测试
#   tool/check.sh --fix    先自动排版再检查
#   LOPI_TEST_JOBS=1 tool/check.sh   全量测试只开一路（内存紧的机器上用，慢但不会被系统杀掉）
#
# 说明：
# - 全量测试要写很多临时文件。有的机器 /tmp 很小（512MB），所以这里把 TMPDIR 指到工程里的 .tmp/。
# - test/generated/ 是低代码导出器的原样输出，不参与排版检查。
set -uo pipefail
cd "$(dirname "$0")/.."

if [ -f "$HOME/workspace/tools/env.sh" ] && ! command -v flutter >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "$HOME/workspace/tools/env.sh" >/dev/null 2>&1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "找不到 flutter 命令。先把 Flutter SDK 加进 PATH。" >&2
  exit 2
fi

mkdir -p .tmp
export TMPDIR="$PWD/.tmp"

quick=0
fix=0
for arg in "$@"; do
  case "$arg" in
    --quick) quick=1 ;;
    --fix) fix=1 ;;
    *) echo "不认识的参数：$arg" >&2; exit 2 ;;
  esac
done

failed=()
step() {
  local name="$1"; shift
  echo
  echo "━━ $name"
  if "$@"; then
    echo "✓ $name"
  else
    echo "✗ $name"
    failed+=("$name")
  fi
}

format_targets() {
  find lib test tool -name '*.dart' -not -path 'test/generated/*' -print0
}

check_format() {
  if [ "$fix" = 1 ]; then
    format_targets | xargs -0 dart format >/dev/null
  fi
  local out
  out="$(format_targets | xargs -0 dart format --output=none --set-exit-if-changed 2>&1)"
  local code=$?
  if [ $code -ne 0 ]; then
    echo "$out" | grep '^Changed' | sed 's/^Changed /  没排版：/'
    echo "  跑 tool/check.sh --fix 自动排好。"
  fi
  return $code
}

step "排版（dart format）" check_format
step "静态检查（flutter analyze，必须零问题）" flutter analyze --no-pub
step "架构守门（依赖方向、文件行数、存盘写法）" flutter test --no-pub test/architecture_test.dart
if [ "$quick" = 0 ]; then
  # 机器内存紧的时候：LOPI_TEST_JOBS=1 tool/check.sh（一次只跑一个测试文件）
  step "全量测试（flutter test）" flutter test --no-pub ${LOPI_TEST_JOBS:+--concurrency=$LOPI_TEST_JOBS}
fi

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "全部通过。"
  exit 0
fi
echo "没通过的：${failed[*]}"
exit 1
