#!/usr/bin/env bash
# 仅测试用。用官方工具造一个最小的、没签名的 APK（最小清单 + 一个只有空类的 classes.dex），给签名测试当夹具。
# 产物 minimal-unsigned.apk 已提交；只有想重造时才需要跑这个脚本（不联网）。
#   用法：source ~/workspace/tools/env.sh && test/fixtures/apkpack_sign/make_fixture.sh
set -euo pipefail
cd "$(dirname "$0")"
BT="$ANDROID_HOME/build-tools/36.0.0"
JAR="$ANDROID_HOME/platforms/android-35/android.jar"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"$BT/aapt2" link -o "$work/base.apk" --manifest AndroidManifest.xml -I "$JAR"
javac -d "$work/classes" Empty.java
"$BT/d8" --release --min-api 21 --lib "$JAR" --output "$work" "$work/classes/Empty.class"
(cd "$work" && "$BT/aapt" add base.apk classes.dex >/dev/null)
"$BT/zipalign" -f 4 "$work/base.apk" minimal-unsigned.apk
"$BT/zipalign" -c 4 minimal-unsigned.apk
ls -l minimal-unsigned.apk
