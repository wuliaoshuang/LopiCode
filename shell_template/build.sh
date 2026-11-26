#!/usr/bin/env bash
# 一键重编 LopiCode 的网页壳模板。只用官方工具：aapt2 → javac → d8 → zipalign。不用 Gradle、不联网。
#
# 用法：shell_template/build.sh            重编，写 assets/apk_shell/shell.apk 和 shell.json
#       shell_template/build.sh --check    只重编到临时目录，和已提交的模板逐字节比较（不写任何文件）
#
# 需要：ANDROID_HOME（或 ANDROID_SDK_ROOT）指向装了 build-tools 和 platforms/android-35 的 SDK；JDK 11 以上。
# 可用环境变量换版本：LOPI_BUILD_TOOLS（默认 36.0.0）。
set -euo pipefail
cd "$(dirname "$0")"
here="$PWD"
repo="$(cd .. && pwd)"

TEMPLATE_VERSION=1
MIN_SDK=24
TARGET_SDK=35
BUILD_TOOLS_VERSION="${LOPI_BUILD_TOOLS:-36.0.0}"

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$sdk" ] && [ -f "$HOME/workspace/tools/env.sh" ]; then
  # shellcheck disable=SC1091
  source "$HOME/workspace/tools/env.sh" >/dev/null 2>&1
  sdk="${ANDROID_HOME:-}"
fi
[ -n "$sdk" ] || { echo "没设 ANDROID_HOME：不知道安卓 SDK 在哪。" >&2; exit 2; }
bt="$sdk/build-tools/$BUILD_TOOLS_VERSION"
android_jar="$sdk/platforms/android-$TARGET_SDK/android.jar"
[ -x "$bt/aapt2" ] || { echo "找不到 $bt/aapt2" >&2; exit 2; }
[ -f "$android_jar" ] || { echo "找不到 $android_jar" >&2; exit 2; }
# 这几个工具都是离线的；别让开发机上给 Gradle 配的代理参数混进来刷屏。
unset JAVA_TOOL_OPTIONS
export TZ=UTC LC_ALL=C
J="-Xmx192m -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 -Dfile.encoding=UTF-8"

check=0
[ "${1:-}" = "--check" ] && check=1

out="$here/build"
rm -rf "$out"
mkdir -p "$out/compiled" "$out/classes" "$out/selftest" "$out/dex"

echo "1/6 编译资源（aapt2 compile，PNG 原样不重压）"
"$bt/aapt2" compile --no-crunch --dir res -o "$out/compiled/res.zip"

echo "2/6 链接清单和资源（aapt2 link）"
"$bt/aapt2" link -o "$out/linked.apk" \
  --manifest AndroidManifest.xml -I "$android_jar" \
  --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
  --no-auto-version --no-version-vectors \
  "$out/compiled/res.zip"

echo "3/6 编译 Java（javac，按 Java 8 语法、对 android.jar 编）"
# shellcheck disable=SC2046
javac -J-Xmx256m -encoding UTF-8 -source 8 -target 8 -Xlint:-options -nowarn \
  -bootclasspath "$android_jar" -d "$out/classes" $(find src -name '*.java' | sort)
javac -J-Xmx256m -encoding UTF-8 -source 8 -target 8 -Xlint:-options -nowarn \
  -cp "$out/classes" -d "$out/selftest" selftest/ShellSelfTest.java
java $J -cp "$out/classes:$out/selftest" lopi.shell.ShellSelfTest

echo "4/6 转成 dex（d8 --release --min-api $MIN_SDK）"
# shellcheck disable=SC2046
"$bt/d8" --release --min-api "$MIN_SDK" --lib "$android_jar" --output "$out/dex" \
  $(find "$out/classes" -name '*.class' | sort)

echo "5/6 装包（固定顺序、固定时间戳）并对齐（zipalign）"
java $J tools/Repack.java "$out/linked.apk" "$out/dex/classes.dex" "$out/unaligned.apk"
"$bt/zipalign" -f 4 "$out/unaligned.apk" "$out/shell.apk"
"$bt/zipalign" -c 4 "$out/shell.apk"
# 官方工具再读一遍：资源表改过路径后必须还能读、图标路径必须是约定的固定路径、不能有依赖包名的写法。
badging="$("$bt/aapt2" dump badging "$out/shell.apk")"
for d in mdpi:160 hdpi:240 xhdpi:320 xxhdpi:480 xxxhdpi:640; do
  echo "$badging" | grep -qx "application-icon-${d#*:}:'res/mipmap-${d%:*}/ic_launcher.png'" \
    || { echo "图标路径不对（${d%:*}）：" >&2; echo "$badging" | grep application-icon >&2; exit 1; }
done
tree="$("$bt/aapt2" dump xmltree --file AndroidManifest.xml "$out/shell.apk")"
if echo "$tree" | grep -E 'android:(name|authorities|permission|taskAffinity|process)\(' | grep -Eq '"\.|com\.lopicode\.shell'; then
  echo "清单里出现了依赖包名的写法：" >&2; echo "$tree" >&2; exit 1
fi

echo "6/6 写说明文件"
java $J tools/Describe.java "$here" "$out/shell.apk" "$repo/assets/apk_shell/shell.json" "$out/shell.json" \
  "$TEMPLATE_VERSION" "$MIN_SDK" "$TARGET_SDK" "$BUILD_TOOLS_VERSION"

if [ "$check" = 1 ]; then
  if cmp -s "$out/shell.apk" "$repo/assets/apk_shell/shell.apk" && cmp -s "$out/shell.json" "$repo/assets/apk_shell/shell.json"; then
    echo "和已提交的模板逐字节一致。"
  else
    echo "重编结果和已提交的模板不一样（源码改了没重编，或工具版本不同）。" >&2
    exit 1
  fi
else
  mkdir -p "$repo/assets/apk_shell"
  cp "$out/shell.apk" "$repo/assets/apk_shell/shell.apk"
  cp "$out/shell.json" "$repo/assets/apk_shell/shell.json"
  echo "已写入 assets/apk_shell/shell.apk（$(wc -c < "$out/shell.apk") 字节）和 shell.json"
fi
