#!/usr/bin/env bash
# 造一个“替身壳模板”给 lib/apkpack 的测试用（真模板由壳那一块提供，放 assets/apk_shell/shell.apk）。
# 约定和真模板一样：包名 com.lopicode.shell、组件写全限定类名（Java 包 lopi.shell）、label 是字面字符串、
# 图标 res/mipmap-*/ic_launcher.png（48/72/96/144/192）、只声明 INTERNET、assets/lopi_shell.json。
# 产物（未签名、已 4 字节对齐）提交在 test/fixtures/apkpack/fake_shell.apk，测试不需要 SDK 就能跑。
# 用法：source ~/workspace/tools/env.sh && tool/make_fake_apk_shell.sh
set -euo pipefail
cd "$(dirname "$0")/.."
BT="$ANDROID_HOME/build-tools/36.0.0"
JAR="$ANDROID_HOME/platforms/android-35/android.jar"
OUT="$PWD/test/fixtures/apkpack"
W="$PWD/.tmp/fake_shell"
rm -rf "$W" && mkdir -p "$W/res" "$W/src/lopi/shell" "$W/cls" "$W/dex" "$W/compiled" "$W/assets/www" "$OUT"

cat > "$W/AndroidManifest.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.lopicode.shell"
    android:versionCode="1"
    android:versionName="1.0">
    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="LopiCode Shell"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:usesCleartextTraffic="true">
        <activity
            android:name="lopi.shell.MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
XML

python3 - "$W/res" <<'PY'
import sys, zlib, struct, os
def png(n, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * n for _ in range(n))
    def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw, 9)) + ch(b'IEND', b'')
for d, n in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    os.makedirs(f'{sys.argv[1]}/mipmap-{d}', exist_ok=True)
    open(f'{sys.argv[1]}/mipmap-{d}/ic_launcher.png', 'wb').write(png(n, (0x33, 0x66, 0xcc)))
PY

cat > "$W/src/lopi/shell/MainActivity.java" <<'JAVA'
package lopi.shell;

public class MainActivity extends android.app.Activity {}
JAVA
printf '{"entry":"index.html"}' > "$W/assets/lopi_shell.json"
printf '<!doctype html><title>shell</title>' > "$W/assets/www/index.html"

javac -source 8 -target 8 -nowarn -cp "$JAR" -d "$W/cls" "$W/src/lopi/shell/MainActivity.java" 2>/dev/null
"$BT/d8" --min-api 24 --lib "$JAR" --output "$W/dex" "$W/cls/lopi/shell/MainActivity.class" 2>/dev/null
# --no-crunch：图标原样放进去（不让 aapt2 重压），和“图标是普通 PNG”的约定一致
"$BT/aapt2" compile --no-crunch --dir "$W/res" -o "$W/compiled/res.zip"
"$BT/aapt2" link -o "$W/base.apk" -I "$JAR" --manifest "$W/AndroidManifest.xml" -A "$W/assets" "$W/compiled/res.zip"
(cd "$W/dex" && zip -q -X "$W/base.apk" classes.dex)
rm -f "$OUT/fake_shell.apk"
"$BT/zipalign" -f 4 "$W/base.apk" "$OUT/fake_shell.apk"
"$BT/zipalign" -c 4 "$OUT/fake_shell.apk"
ls -l "$OUT/fake_shell.apk"
