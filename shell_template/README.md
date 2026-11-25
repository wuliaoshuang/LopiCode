# LopiCode 网页壳模板（shell_template）

LopiCode「本地打包 APK」用的模板：一个极小的安卓应用，启动后打开安装包里 `assets/www/` 的网页，离线可用。
它编出来是 `assets/apk_shell/shell.apk`（未签名、已对齐），随 LopiCode 一起发。手机上的打包器把它当 ZIP 打开，
放进网页、改二进制清单、换图标、重新签名，就得到用户的应用。手机上不需要任何编译工具。

- 全部自己写，**没有任何第三方代码**：不用 androidx、不用任何库，只用安卓系统自带的类（`android.*`、`java.*`、`org.json`）。
  所以它不需要在「第三方声明」里登记（`lib/core/third_party.dart`、`third_party/` 都没有它的条目）。
- 不带任何统计、联网上报、远程代码加载。源码里唯一的网址是本地地址 `https://lopi.invalid`（测试守着）。
- 模板的具体数字（字节数、sha256、条目清单）以 `assets/apk_shell/shell.json` 为准。
- 给打包器的改动指南（改包名 / 应用名 / 版本 / 权限 / 图标分别动哪里）在 [docs/apk-shell-template.md](../docs/apk-shell-template.md)。

## 目录

| 路径 | 是什么 |
| --- | --- |
| `AndroidManifest.xml` | 清单源文件 |
| `src/lopi/shell/*.java` | 壳的代码（Java 包固定 `lopi.shell`，和应用包名无关） |
| `res/mipmap-*/ic_launcher.png` | 默认图标，五个密度（48 / 72 / 96 / 144 / 192 像素），由 `tools/IconGen.java` 画出来后提交 |
| `res/values/`、`res/values-night/` | 浅色 / 深色主题（只继承系统自带主题） |
| `selftest/ShellSelfTest.java` | 开发机上能跑的自测（路径换算、MIME、Range），不进安装包 |
| `tools/Repack.java` | 把产物装成“每次都一模一样”的 ZIP |
| `tools/Describe.java` | 写 `shell.json` |
| `tools/IconGen.java` | 画默认图标（只在想换默认图标时手动跑：`java tools/IconGen.java res`） |
| `build.sh` | 一键重编 |
| `build/` | 中间产物，不提交 |

## 重编

```
shell_template/build.sh           # 重编并写 assets/apk_shell/shell.apk、shell.json
shell_template/build.sh --check   # 只比较：重编结果和已提交的是否逐字节一致
```

需要 `ANDROID_HOME`（build-tools 36.0.0、platforms/android-35）和 JDK 11 以上。不用 Gradle、不联网。步骤：

1. `aapt2 compile --no-crunch`：编译资源，PNG 原样不重压（APK 里的图标和 `res/` 里的逐字节相同）。
2. `aapt2 link`：链接清单和资源。**没有**开资源路径缩短、资源名混淆、稀疏编码。
3. `javac -source 8 -target 8 -bootclasspath android.jar`：按 Java 8 语法、对 android-35 的 `android.jar` 编。
   （没用 `--release 8`：那样 `java.*` 是照 JDK 8 的接口查的；用 `-bootclasspath` 是照安卓自己的接口查，更准。）
   编完立刻跑 `selftest`，有一条不过就停。
4. `d8 --release --min-api 24`：转成 dex。没有用 R8（不做混淆和裁剪）。
5. `tools/Repack.java` 装包 → `zipalign -f 4` → `zipalign -c 4` 检查 → `aapt2 dump` 再核对图标路径和清单。
6. `tools/Describe.java` 写 `shell.json`。

**改了这个目录里的任何文件（README.md 除外）都要重编并把新的 `shell.apk`、`shell.json` 一起提交。**
`test/apk_shell_template_test.dart` 会核对源码目录的指纹（`shell.json` 的 `sourceSha256`），忘了重编测试就不过。

### 可重复

同一台机器上连编两次，`shell.apk` 逐字节相同（2026-11-26 实测）。靠的是：条目顺序固定、时间戳固定
（1981-01-01 01:01:02）、不写附加字段、文件按名字排序后再编。`shell.json` 里的构建日期在模板内容没变时沿用旧值。

会让结果不同的只有工具本身：换了 aapt2 / d8 / zipalign 的版本（build-tools）、换了 `android.jar`、
换了 JDK（javac 生成的字节码、JDK 自带 zlib 的压缩结果都可能变）。**没在第二台机器上验证过。**

### 一处不是“官方工具原样产物”的地方：图标路径去掉 -v4

aapt2 会把带密度的目录名自动写成 `res/mipmap-mdpi-v4/`，没有开关能关。约定的图标路径是
`res/mipmap-mdpi/ic_launcher.png`，所以 `tools/Repack.java` 在装包时把 ZIP 里的路径和资源表（`resources.arsc`
开头的全局字符串池）里的同一串路径一起改掉，别的字节不动。改完由 `aapt2 dump badging` 重新读一遍核对，读不出来或路径不对构建就失败。

## 清单为什么这样写

打包器不重新编译清单，而是直接改编译后的二进制。所以清单里每一处都要保证“只改一个地方就够”：

1. **包名默认 `com.lopicode.shell`，只在 `package` 属性里出现一次。** 所有组件写全限定类名
   （`lopi.shell.MainActivity`），Java 包固定是 `lopi.shell`。没有 `.MainActivity` 这种简写、没有
   `${applicationId}`、没有 `<provider>`（authority 通常带包名）、没有自定义 `<permission>`、没有
   `taskAffinity` / `process`。这样改包名只换一个字符串，壳的代码一个字都不用动。
2. **应用名 `android:label="LopiApp"` 是字面字符串**，不是 `@string` 引用。改应用名只动清单的字符串池，
   不用碰 `resources.arsc`。Activity 没有单独的 label，跟着应用名走。
3. **`versionCode`、`versionName` 写在清单里**（没有交给 aapt2 的参数注入，这样源文件就是全部事实）。
4. **图标是五个密度的普通 PNG**，没有自适应图标 XML（`mipmap-anydpi-v26`），没有 `roundIcon`。
   打包器按固定路径替换 PNG 就能换图标，不用改清单也不用改资源表。代价：在安卓 8 以上的桌面上，
   系统会把这张方图缩小后放进它自己的图标形状里（四周多一圈底色），不如自适应图标好看。
5. **默认只声明 `android.permission.INTERNET`。** 打包器按用户勾选增删 `<uses-permission>`。
   壳在运行时查“自己清单里声明了哪些权限”来决定行为（见下面「权限」），所以增删权限也不用改代码。
6. **`android:usesCleartextTraffic="true"`：允许 http 明文。** 取舍：用户做的网页常要连局域网里的接口
   （`http://192.168.x.x:3000`），不放开就连不上；代价是网页访问 http 地址时内容不加密、可能被同一网络里的人看到或改掉。
   配套地，壳里把 WebView 的“混合内容”也放开了（本地地址是 https，去连 http 接口本来会被拦）。
7. **`android:allowBackup="false"`**：应用数据不参加系统的云备份，数据只留在这台手机上。
8. **`android.webkit.WebView.MetricsOptOut = true`**：让系统 WebView 不为这个应用收集使用统计
   （按安卓官方文档，这个开关不管崩溃报告，崩溃报告仍取决于用户自己在系统里是否同意）。
9. **`configChanges` 列全了**（横竖屏、屏幕大小、深浅色、字号、密度、语言、键盘等）：这些变化都不重建页面，
   网页不会被重新加载。
10. **`windowSoftInputMode="adjustResize"`**：键盘弹出时网页区域变矮，输入框不被挡住。
11. **`exported="true"`**：targetSdk 31 起带启动入口的页面必须显式写。
12. **主题引用 `@style/LopiShell`、图标引用 `@mipmap/ic_launcher`** 是清单里仅有的两处资源引用
    （资源号 `0x7f020000`、`0x7f010000`）。打包器不要动它们。

minSdk 24（安卓 7.0），targetSdk 35（安卓 15），用的是 `platforms/android-35` 的 `android.jar`。

## 壳的行为

### 本地地址：`https://lopi.invalid/`

不用 `file://`。壳拦截所有请求（`shouldInterceptRequest`），把 `https://lopi.invalid/<路径>` 映射到安装包里的
`assets/www/<路径>`。网页以为自己在一个普通 https 网站上，所以相对路径、以 `/` 开头的绝对路径、`fetch`、
ES module、Service Worker 都照常能用，而且算“安全环境”（摄像头、定位、`crypto.subtle` 这些只在 https 下才给用）。

- 域名选 `.invalid` 结尾：这是 RFC 2606 保留的后缀，真实网络上永远解析不到。万一有请求漏拦，也不会连到别人的服务器。
- 按扩展名给 MIME（表在 `Paths.java`）；文字类带 `utf-8`；不认识的给 `application/octet-stream`。
- 路径里有 `..`、反斜杠、控制字符的一律当找不到（404）。
- 找不到的文件返回 404。整页打开时显示一页大白话说明，子资源返回纯文本 `Not Found`。
- 支持 `Range` 请求（音频、视频拖进度条要用）。
- 只读：对本地地址的 POST 等返回 405。
- 响应带 `Cache-Control: no-store`：覆盖安装新版本后立刻看到新网页，不会被旧缓存挡住。
- **单页应用的路由回退：做了，默认开。** 找不到、最后一段不带扩展名（如 `/user/12`）、而且请求的是页面
  （整页打开，或请求头接受 `text/html`）时，返回入口文件。带扩展名的（`/a.js`）照常 404。
  可以用 `spaFallback: false` 关掉。注意：回退后入口里的**相对路径**是相对 `/user/` 算的，单页应用自己要用绝对路径或 `<base>`。

### 设置文件 `assets/lopi_shell.json`

全部可选，每一项都有默认值。文件没有、不是合法 JSON、某一项写错，壳都照常起来（写错的那一项用默认值）。

| 键 | 默认 | 含义 |
| --- | --- | --- |
| `entry` | `"index.html"` | 入口文件，相对 `assets/www/`，可以在子目录里（`"app/index.html"`）。不能有 `..`、不能带 `?` `#` |
| `spaFallback` | `true` | 单页应用路由回退（见上） |
| `externalLinks` | `"browser"` | 整页跳到外部网站时：`"browser"` 交给系统浏览器；`"inapp"` 就在壳里打开 |
| `background` | `"#FFFFFF"` | 浅色模式下的底色（状态栏、导航栏区域和网页加载前都是它），只认 `#RRGGBB` |
| `backgroundDark` | `"#121212"` | 深色模式下的底色 |
| `orientation` | `"auto"` | `"auto"` 跟随手机、`"portrait"` 锁竖屏、`"landscape"` 锁横屏 |
| `keepScreenOn` | `false` | 应用在前台时屏幕常亮（不需要 WAKE_LOCK 权限） |
| `zoom` | `false` | 允许双指缩放网页 |

入口文件不在安装包里时（比如直接装了空模板），显示一页说明：“这个应用里没有找到网页……这不是你手机的问题，
是打包时出的问题”，并带上设置文件的问题（如果有）。

### 权限：清单里声明了才给

壳启动时用 `PackageManager` 查自己清单里的 `<uses-permission>`：

- 网页要摄像头 / 麦克风（`getUserMedia` → `onPermissionRequest`）：清单里声明了 `CAMERA` / `RECORD_AUDIO` 才向用户弹系统权限窗，
  用户同意后转给网页；没声明就直接拒绝，不弹窗、不崩。同时要两样但只声明了一样时，只给声明了的那样。
- 网页要定位（`onGeolocationPermissionsShowPrompt`）：声明了 `ACCESS_FINE_LOCATION` 或 `ACCESS_COARSE_LOCATION` 才申请；
  用户只给“大概位置”也算同意。
- 只答应应用自己的网页（本地地址）。嵌进来的外部网站、或 `externalLinks: "inapp"` 下打开的外部网站来要，一律拒绝。
- `INTERNET`、`ACCESS_NETWORK_STATE`、`VIBRATE`、`WAKE_LOCK` 是安装即有的普通权限，壳不需要为它们写代码：
  声明了，WebView 里对应的网页功能（联网、`navigator.onLine`、`navigator.vibrate`、屏幕常亮接口）就能用。

### 其余行为

- **返回键**：全屏视频时先退出全屏；网页能后退就后退；否则退出应用。
- **外链**：整页跳到非本地的 http / https 网址，默认交给系统浏览器（这个应用是离线应用，不该变成浏览器）；
  网页里用 iframe 嵌的外部内容照常显示。`tel:`、`mailto:`、`sms:`、`geo:`、`market:` 和其他应用自己的链接交给系统找对应应用，
  没有能打开的就提示一句。`intent:` 链接不支持（能被用来拉起任意页面），`file:`、`content:` 直接拦掉。
- **选文件**（`<input type=file>`）：用系统文件选择器（`ACTION_GET_CONTENT`），支持 `accept` 和 `multiple`。
  不需要任何权限，也不需要 FileProvider。代价：`capture`（直接调起相机拍一张）不支持，会退化成选文件。
- **弹窗**：`alert` / `confirm` / `prompt` / 离开页面确认都支持，用系统对话框画（不显示网址）。
- **存储**：localStorage、DOM storage、IndexedDB、Cookie 都开着。网页不能直接读手机里的文件（`file://`、`content://` 关闭）。
- **深色**：主题跟随系统（`values-night`），安卓 10 及以上网页的 `prefers-color-scheme` 跟着变；系统切换深浅色时不重载网页。
  安卓 7–9 没有系统级深色模式，网页看到的一直是浅色。
- **状态栏 / 导航栏**：安卓 15 强制“边到边”。壳把系统栏、刘海、键盘占的地方都留成内边距，网页不会被盖住；
  这些区域显示的是 `background` / `backgroundDark`，图标深浅按底色亮度自动选。因为内边距已经留好，网页里的
  `env(safe-area-inset-*)` 都是 0。
- **横竖屏切换**：不重建页面、不重载网页。
- **下载**（WebView 自己不会下载，不处理的话点了没反应）：
  - 外部网址：交给系统浏览器去下。
  - 应用内的文件、`data:` 地址、`blob:` 地址（网页自己生成的导出文件）：弹系统的“保存到…”，用户选位置，壳把内容写进去。
    不需要存储权限。`blob:` 是整份读进内存再写的，几十 MB 以上的大文件可能失败（会提示“没有保存”）；文件名固定是 `download.扩展名`，可以在保存界面里改。
  为了读 `blob:`，壳给网页挂了一个脚本对象 `LopiShellHost`，上面只有一个方法，而且要带壳当场生成的一次性口令才理，
    别的网页调了也没用。这是壳暴露给网页的唯一接口。
- **全屏视频**：支持（网页的全屏接口），进全屏时隐藏系统栏。
- **网页进程崩了 / 被系统回收**（安卓 8 及以上）：换一个新的网页视图重新打开入口，应用本身不崩。
- **系统网页组件不可用**（被停用、正在更新、损坏）：显示一页说明和三条处理办法，不崩。
- **应用被系统杀掉后再回来**：恢复到之前的页面地址（重新加载那一页；网页内存里的状态不保留，localStorage 里的在）。

### 自己定的、可以再议的默认值

- 自动播放：保持 WebView 默认（带声音的视频要用户点一下才播）。
- 安全浏览（Safe Browsing）：保持 WebView 默认（开）。它是系统 WebView 自己的功能，访问外部网址时可能和 Google 核对网址。
- 网页调试（chrome://inspect）：没开。

## 验证到哪一步

- 开发机上做过的：官方工具的各项检查（`aapt2 dump badging` / `xmltree`、`zipalign -c`、临时钥匙 `apksigner verify`）、
  模拟打包器的冒烟（加网页 → 对齐 → 签名 → 验证通过）、`selftest` 49 条、`test/apk_shell_template_test.dart`。
- **没做的：没有装到任何手机或模拟器上运行过**（这台机器没有模拟器）。壳的所有运行时行为都只是对着源码检查过，没有实际跑过。
