#!/usr/bin/env bash
# 一键全跑。每个 pNN-*/ 目录：Node / Python / Go / Java 四份各跑一遍，输出逐字节对比 expect.txt（事先写好的预期），
# 再用 infer.py 对 prog.lc 自动推断，对比手写的 types.txt（不看行的先后）。
# 每个 eNN-*/ 目录（故意写错的例子）：infer.py 报出来的错误逐字节对比手写的 errors.txt。
# 用法：./run_all.sh [目录名开头…]      不带参数＝全跑，并把结果写进 RESULT.txt。
set -u
cd "$(dirname "$0")"
source ~/workspace/tools/env.sh 2>/dev/null
export PATH=$HOME/workspace/tools/gosdk/go/bin:$PATH
T=${LC_PROTO_TMP:-/tmp/v5-B}                # 临时文件放哪儿（回归测试会换一个）
export GOFLAGS=-mod=mod GOPROXY=off GOCACHE=${LC_PROTO_GOCACHE:-$T/gocache}
skip=" ${LC_PROTO_SKIP:-} "                  # 这台机器没有的编译器（go、java），空格隔开：那一种标“跳过”，不算通过也不算不符
export LC_ALL=C.UTF-8          # Java 的类型名要变成文件名，区域设置不是 UTF-8 时写不了中文（见 ROUNDS/round1-notes.md 的 F1）
unset JAVA_TOOL_OPTIONS
mkdir -p $T/bin $T/java $T/out
dirs=(); for a in "$@"; do dirs+=("$a"*/); done; [ ${#dirs[@]} -eq 0 ] && dirs=(p*/ e*/)
pass=0; bad=0; lines=()
say() { lines+=("$1"); echo "$1"; }
same() { if cmp -s "$1" "$2"; then pass=$((pass+1)); R=通过; else bad=$((bad+1)); R=不符; fi; }
say "类型原型全跑  $(TZ=Asia/Shanghai date '+%F %T %Z')  node $(node -v)  $(python3 -V 2>&1)  $(go version | cut -d' ' -f3)  javac $(javac -version 2>&1 | cut -d' ' -f2)"
for d in "${dirs[@]}"; do
  d=${d%/}; [ -d "$d" ] || continue
  row="$d:"
  if [ -f "$d/expect.txt" ]; then
    o=$T/out/$d
    node "$d/main.js" > $o.node 2>$o.node.err;       same $o.node "$d/expect.txt"; row+=" Node=$R"
    python3 -B "$d/main.py" > $o.py 2>$o.py.err;     same $o.py "$d/expect.txt";   row+=" Python=$R"
    ran=($o.node $o.py)
    if [[ $skip == *" go "* ]]; then row+=" Go=跳过"; else
    if go build -o $T/bin/$d ./$d/go 2>$o.go.err; then $T/bin/$d > $o.go 2>>$o.go.err; else echo "编译失败" > $o.go; fi
    same $o.go "$d/expect.txt"; row+=" Go=$R"; ran+=($o.go); fi
    if [[ $skip == *" java "* ]]; then row+=" Java=跳过"; else
    rm -rf $T/java/$d; mkdir -p $T/java/$d
    if javac -J-Xmx256m -J-XX:+UseSerialGC -encoding UTF-8 -Xlint:all -Werror -d $T/java/$d _prelude/Lc.java $d/Main.java 2>$o.java.err; then
      java -Xmx128m -XX:+UseSerialGC -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -cp $T/java/$d Main > $o.java 2>>$o.java.err; else echo "编译失败" > $o.java; fi
    same $o.java "$d/expect.txt"; row+=" Java=$R"; ran+=($o.java); fi
    alike=是; for f in "${ran[@]:1}"; do cmp -s "${ran[0]}" "$f" || alike=否; done
    n=${#ran[@]}; [ $n = 4 ] && n=四; row+=" ${n}份逐字节相同=$alike"
  fi
  if [ -f "$d/errors.txt" ]; then
    python3 -B infer.py "$d/prog.lc" --errors > $T/out/$d.infer 2>&1
    same $T/out/$d.infer "$d/errors.txt"; row+=" 自动报错对比手写=$R（$(grep -c . "$d/errors.txt") 条）"
  elif [ -f "$d/types.txt" ]; then
    python3 -B infer.py "$d/prog.lc" 2>&1 | sort > $T/out/$d.infer; sort "$d/types.txt" > $T/out/$d.hand
    same $T/out/$d.infer $T/out/$d.hand; row+=" 自动推断对比手写=$R（$(grep -c . "$d/types.txt") 行）"
  fi
  say "$row"
done
say "合计：通过 $pass 项，不符 $bad 项"
[ $# -eq 0 ] && printf '%s\n' "${lines[@]}" > RESULT.txt
exit $bad
