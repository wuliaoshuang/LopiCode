# 本地打包 APK：格式事实、规则和依据

给 `lib/apkpack/` 用的备忘。每条写明**依据**和**核对状态**：

- 「已核对源码」＝2026-11-26 对着 AOSP 官方仓库的网页读过那一段。
- 「已用官方工具验证」＝开发机上用 SDK build-tools 36.0.0 的 aapt2 / zipalign / apksigner 实测过（测试在 `test/apkpack_official_tools_test.dart`）。
- 「未核对」＝凭已有知识写的，这次没找到官方原文对照；用到的地方都有测试兜着，但出处没确认。

真机上装不装得上、点开能不能用，这一块**一概没验证**（开发机没有模拟器）。

## 1. 二进制清单（AXML）

来源：`frameworks/base/libs/androidfw/include/androidfw/ResourceTypes.h`
（<https://android.googlesource.com/platform/frameworks/base/+/oreo-release/libs/androidfw/include/androidfw/ResourceTypes.h>）。

| 事实 | 状态 |
| --- | --- |
| 每个块以 `ResChunk_header` 开头：类型 u16、头部长度 u16、整块大小 u32，小端 | 已核对源码 |
| 块类型：字符串池 0x0001、XML 0x0003、命名空间开始/结束 0x0100/0x0101、元素开始/结束 0x0102/0x0103、文本 0x0104、资源号表 0x0180 | 已核对源码 |
| 字符串池头部 28 字节：stringCount、styleCount、flags、stringsStart、stylesStart；偏移表相对 stringsStart | 已核对源码 |
| flags：`SORTED_FLAG = 1<<0`、`UTF8_FLAG = 1<<8` | 已核对源码 |
| UTF-16 串：u16 长度（超过 32767 时最高位置 1、再跟一个 u16 低位），内容，u16 的 0 结尾 | 已核对源码（头文件注释） |
| UTF-8 串：先“UTF-16 长度”再“字节数”，各 1 字节，超过 127 时最高位置 1 用 2 字节；内容；1 字节 0 结尾 | 未核对源码（实现在 ResourceTypes.cpp）；已用官方工具验证（aapt2 能读我们写的 UTF-8 池子，含表情） |
| UTF-8 池子里基本平面以外的字符（表情）按 aapt2 的做法写成两个代理项、各 3 字节 | 未核对源码；已用官方工具验证（aapt2 读回来的应用名一致） |
| `Res_value`：size u16（＝8）、res0 u8、dataType u8、data u32；类型 STRING 0x03、REFERENCE 0x01、INT_DEC 0x10、INT_HEX 0x11、INT_BOOLEAN 0x12 | 已核对源码 |
| 字符串引用“没有”＝0xFFFFFFFF | 已核对源码（comment 字段的注释“-1 if none”） |
| 节点头 16 字节（块头 + 行号 + 注释）；元素扩展：ns、name、attributeStart(20)、attributeSize(20)、attributeCount、idIndex、classIndex、styleIndex；属性 20 字节：ns、name、rawValue、Res_value | 字段存在已核对源码；逐字节的布局靠“读入再写出字节完全一致”和 aapt2 能读来确认 |
| 资源号表第 i 项是字符串池第 i 条（属性名）的资源号，所以带资源号的属性名必须排在池子最前面 | 未核对源码；已用官方工具验证（aapt2 dump xmltree 打印出的资源号都对） |
| 官方工具写清单用 UTF-16 池子 | 实测：aapt2 和老 aapt 产出的清单 flags 都是 0。UTF-8 池子的清单官方工具造不出来，测试里是自己转出来再让 aapt2 读 |

用到的系统属性资源号（android.R.attr，aapt2 dump xmltree 的输出里能直接看到）：label 0x01010001、icon 0x01010002、name 0x01010003、authorities 0x01010018（未核对，模板里没有 provider）、versionCode 0x0101021b、versionName 0x0101021c。

### 改清单的做法（`lib/apkpack/manifest_editor.dart`）

- 不改池子里已有的字符串（别的属性可能共用），只追加新字符串、把引用改过去；改完把没人引用的“值字符串”清掉并重排下标。带资源号的属性名那一段一条不动。
- 新字符串只在“资源号表之后”的区域里找重复，不复用属性名那几条（即使字面相同）。
- 包名：`manifest` 上没有命名空间的 `package` 属性，字符串类型，rawValue 和 data 指向同一条。
- 版本号：`android:versionCode`，写成 INT_DEC，rawValue＝“没有”。版本名、应用名：字符串类型，rawValue＝data。
- 权限：`<uses-permission android:name=…>`，是 `manifest` 的直接子元素。要的留着、多的删掉、缺的按名字顺序加在最后一个权限后面（一个都没有时加在 `uses-sdk` 后面 / `application` 前面）。精确定位自动连带 `ACCESS_COARSE_LOCATION`（安卓 12 起只声明精确定位不被允许——未核对官方文档原文）。
- 新增权限元素要用到 `android:name` 这条属性名在池子前部的下标；模板里一定有（Activity 就用它），没有就报“模板不对”，不往前部插字符串。
- 模板里以默认包名开头的 provider `authorities`、`<permission>` / `<uses-permission>` 的名字会跟着换成新包名（否则两个打出来的应用会抢同一个名字装不上）。现在的模板里没有这些，属于防守。
- 模板不符合约定（包名不是 `com.lopicode.shell`、应用名不是字面字符串、缺版本号、根元素不是 manifest、不认识的块、长度对不上、被截断）一律报错，不猜。
- 往返：替身模板的清单读入再原样写出，**字节完全一致**（`test/apkpack_axml_test.dart`）。

## 2. resources.arsc 要不要改

**结论：不用改。** 改包名、应用名、图标都不动 `resources.arsc`。

依据：

1. 应用名在清单里是字面字符串，不经过资源表；图标是按路径替换同名 PNG 文件，资源表里记的路径不变。
2. 资源表里的包名和清单里的包名本来就允许不同：官方 aapt2 自己提供 `--rename-manifest-package`（只改清单里的包名）和
   `--rename-resources-package`（改资源表里的包名）两个分开的开关（`aapt2 link --help` 原文：“Renames the package in AndroidManifest.xml.” /
   “Renames the package in resources table”）。开发机实测：`aapt2 link --rename-manifest-package com.other.app` 产出的包，
   `aapt2 dump badging` 报 `package: name='com.other.app'`，`aapt2 dump resources` 报 `Package name=com.lopicode.shell id=7f`。
   我们改完的包和它是同一种状态。**已用官方工具验证。**
3. 运行时取资源靠资源号（0x7fxxxxxx，按包号 7f 找），不靠资源表里的包名。——未核对源码。
4. 最低证据（已用官方工具验证，测试“包名改了、resources.arsc 没动”）：包名改成别的以后，`aapt2 dump badging` 仍然读出五个密度的图标路径和应用名。

**留给壳模板的注意事项**：壳的代码里不要写 `getResources().getIdentifier(名字, 类型, getPackageName())`——资源表里的包名还是
`com.lopicode.shell`，用新包名去查会查不到。直接用 `R.xxx` 资源号没问题。真机上“改了包名能装、能取资源”**没有验证**。

另：`resources.arsc` 必须不压缩且 4 字节对齐（targetSdk 30 起系统会拒绝压缩的资源表；AOSP `ParsingPackageUtils` 里有
`INSTALL_PARSE_FAILED_RESOURCES_ARSC_COMPRESSED` 这个错误码——错误码存在已核对源码，具体条件未核对）。打包器会保证这一点：模板里若是压缩的，也改成不压缩。

## 3. 模板约定里和原先说法不一样的一处：图标路径

约定写的是 `res/mipmap-{mdpi,…}/ic_launcher.png`。实测 aapt2 link 会给密度目录补版本后缀，产物里是
`res/mipmap-mdpi-v4/ic_launcher.png`。打包器按 `res/mipmap-<密度>(-v数字)?/ic_launcher.png` 找，两种都认；五个密度缺一个就报“模板不匹配”。
真的壳模板（`assets/apk_shell/shell.apk`，壳那一块提交 f3584a5）在装包时已经把 `-v4` 去掉了，路径就是约定的
`res/mipmap-mdpi/ic_launcher.png`；替身模板（`test/fixtures/apkpack/fake_shell.apk`）是 aapt2 的原样产物，带 `-v4`。两种测试里都有。
壳模板**不能开资源路径缩短**（AGP 的 resource shrinker / `android.enableResourceOptimizations` 会把路径改成 `res/xY.png`），否则找不到图标。

## 4. ZIP 与对齐（`lib/apkpack/zip/`）

ZIP 结构（本地文件头 0x04034b50、中央目录 0x02014b50、结尾记录 0x06054b50，字段偏移）按 PKWARE APPNOTE 写——未重新核对原文；
验证方式：产物能被 `archive` 包、`unzip`、aapt2、zipalign、apksigner 读。

- **读**（只读模板）：从末尾找结尾记录，走中央目录。不支持 ZIP64、加密、分卷、deflate 以外的压缩，遇到就报错。模板条目带着压缩好的原始字节走，不重压。
- **写**：
  - 条目顺序：模板原有顺序（清单、图标就地替换）→ `assets/lopi_shell.json` → `assets/www/` 下的文件按路径排序 → v1 签名文件按名字排序。
  - 时间戳固定 1980-01-01 00:00:00；不写数据描述符；文件名含非 ASCII 时置“名字是 UTF-8”标志（第 11 位）。产物里没有任何“当前时间”，
    同样输入产出同样字节（签名前）；测试隔一秒打两次包比过字节。
  - 不压缩的条目数据起点按 4 字节对齐（`.so` 按 16384，即 16KB 页；模板里没有 .so，这条未验证）。垫位置用本地文件头的 extra 字段，
    写成一个正规的 extra 项：编号 0xd935、长度、u16 对齐值、后面补 0（和 apksigner 对齐时用的是同一个编号——未核对源码）。至少 6 字节，不够就多垫一个对齐周期。
  - 已经压缩过的格式不再压缩，直接存：png jpg jpeg gif webp avif heic mp3 mp4 m4a m4v aac ogg oga ogv opus webm mov flac woff woff2 zip gz br zst 7z rar apk jar。
    其余用 deflate（级别 6）；压完没变小的也改成直接存。
  - 不写 ZIP64：条目数 ≥ 65535、单个或整体 ≥ 4GB 直接报错。
- `zipalign -c -v 4`：三个样例产物（替身模板和真模板各打一遍）都是 `Verification successful`。**已用官方工具验证。**

## 4.1 用真的壳模板验过什么

`test/fixtures/apkpack/real_shell.apk` 是从壳那一块原样拷来的一份（sha256 `4976223b…b6d658`，和它的 `shell.json` 一致；壳重编后要重新拷）。
用它打三个样例，`aapt2 dump badging` 读出的包名、应用名、版本、权限、五个图标路径、启动页、minSdk 24 / targetSdk 35 都对；
`aapt2 dump xmltree` 里主题和图标的资源引用（`@0x7f020000`、`@0x7f010000`）、`meta-data` 原样还在；`classes.dex`、`resources.arsc` 的字节没动；
`zipalign -c -v 4` 通过；官方 apksigner 用临时钥匙签（v1 + v2）后 `verify --min-sdk-version 24` 通过。**已用官方工具验证。**
真模板不带 `assets/lopi_shell.json`，打包器写进去的是 `{"entry":"…"}`（其余设置走壳的默认值）。

## 5. 项目识别（`detectWebProject`）

读了这些代码定的规则：

- `lib/core/templates.dart`：前端网页模板在根目录生成 `index.html`、`style.css`、`script.js`；低代码模板在根目录生成 `page.lc.json`（`kLowcodePageFile`）+ 导出的 `index.html`、`style.css`。
- `lib/lowcode/builder_screen.dart`、`lib/agent/agent_tools.dart`：搭建器每次保存、Agent 每次改页面，都会把 `index.html`、`style.css`（有逻辑时加 `logic.js`）
  重新导出到**项目根目录**；`export/` 下是另外导出的 Flutter / Vue / React 代码，不是成品网页。
- `lib/build/build_screen.dart`、`workflow_templates.dart`：现在的“网页套壳”远程打包用的就是仓库根目录的 `index.html`（`rsync` 整个根目录到 `assets/www/`）。
- `lib/preview/preview_server.dart`：预览打开的也是根目录的 `index.html`。
- `lib/templates/fullstack_web.dart`：“前端 + 后端”模板的网页在 `web/`，根目录的 `index.html` 只是把预览带到 `web/`，后端在 `server/`。

规则（按顺序，先中先算）：

1. 有 `pubspec.yaml` → 不适用（Flutter）。有 `build.gradle(.kts)` / `settings.gradle(.kts)` → 不适用（原生安卓）。
2. 有 `page.lc.json` → 低代码（kind `lowcode`）：网页目录＝项目根目录，入口 `index.html`。根目录没有 `index.html` → 不适用，提示“先打开搭建保存一次”。
   **不需要界面调 lowcode 的导出函数**：导出结果本来就在盘上。界面那边只要保证打包前页面是保存过的。
3. 有后端文件（`server/backend.lc.json` 或 `backend.lc.json`）且有 `web/index.html` → kind `web`：只打包 `web/`，说明里提醒“后端不进安装包，接口地址要改成手机能访问到的”。
4. `package.json` 里有 `build` 脚本（要构建的前端工程）→ 在 `dist`、`build`、`out`、`www`、`public`、`web` 里按顺序找第一个含 `index.html` 的，kind `dist`；
   一个都没有 → 不适用，提示先 `npm run build`。（这种工程根目录的 `index.html` 是源码，直接装进去跑不起来，所以不用它。）
5. 根目录有 `index.html` → 纯网页（kind `static`）。
6. 根目录没有入口，但上面那几个目录之一含 `index.html` → kind `dist`。
7. 其余：有后端迹象（`backend.lc.json`、`go.mod`、`pom.xml`、`requirements.txt`、`main.py`、`composer.json`、`package.json`、`main.go`、`index.php`）→ “看起来是后端服务”；
   否则“找不到网页入口”。不适用的说明都指向“远程打包”。

Flutter 项目即使有 `build/web/index.html` 也判不适用（Flutter 网页产物在壳里能不能跑没验证过，保守处理）。

## 6. 收集文件（`collectWebFiles`）

- 不收：以 `.` 开头的文件和目录（`.git`、`.lopicode`、`.env`…）；任何层级的 `node_modules`；网页目录**顶层**的 `build` 目录和 `.apk` 文件（打包产物自己）；
  低代码项目顶层的 `page.lc.json` 和 `export/`；这次的输出文件和它的临时文件；指到网页目录外面的符号链接、链接到目录的符号链接、断掉的链接。
  指到网页目录里面普通文件的符号链接按文件内容收。
- 上限（自定）：总大小 ≤ 100MB、文件数 ≤ 5000、单个文件 ≤ 50MB。超了报明确的错，不截断。
  依据：打包全程在内存里做（网页内容 + 压缩后的条目 + 最终安装包，签名时还要再过一遍），峰值大约是网页总大小的 3～4 倍，100MB 的项目要占 300～400MB 内存，
  再大手机上容易被系统杀掉。真机上的实际内存占用**没有测过**，这个上限可能还要调。
- 路径统一成 `/`，按路径排序，放进 `assets/www/`。入口文件必须在收集到的文件里。
- `assets/lopi_shell.json`：以模板里那份为底，把 `entry` 改成这次的入口（模板里其他设置原样保留）。

## 7. 输入校验的数值

| 项 | 规则 | 依据 |
| --- | --- | --- |
| 包名 | 至少两段；每段字母开头，只含字母、数字、下划线 | AOSP `ParsingPackageUtils.validateName`（已核对源码：字母可在任意位置，数字和下划线不能在段首，必须有 `.`）；[官方清单文档](https://developer.android.com/guide/topics/manifest/manifest-element#package) 同样说法（未重新打开核对） |
| 包名长度 | ≤ 223 | 同一个函数里的 `MAX_FILE_NAME_SIZE = 223`（已核对源码） |
| 包名的段不能是 Java 关键字 | 自定（任务要求）| 安卓系统本身不查这个；壳是预编好的，不受影响。保留是为了以后同一个包名拿去正经工程里不出问题 |
| 应用名 | 非空、首尾无空格、无控制字符、无残缺的表情，≤ 50 个字（按字数不按码元） | 自定。Google Play 的标题上限是 30（未核对），这里放宽 |
| 版本名 | 非空、首尾无空格、无控制字符，≤ 50 个字 | 自定，安卓没有限制 |
| 版本号 | 1 ～ 2100000000 | 官方文档 [Version your app](https://developer.android.com/studio/publish/versioning)：“The greatest value Google Play allows for versionCode is 2100000000.”（已核对） |
| 图标 | 是 PNG（签名、IHDR、IEND 都在）、正方形、边长正好是 48/72/96/144/192 之一；给就五张给齐；单张 ≤ 1MB | 约定 + 自定 |
| 权限名 | 形如 `a.b.C`，≤ 255 | 自定（防乱填） |

## 8. 用官方工具验证时碰到的两个“不是 bug”

- `apksigner verify --min-sdk-version 24` 会报 `Verified using v1 scheme (JAR signing): false`、整体 `Verifies`：安卓 7.0 起系统只看 v2，apksigner 就不去验 v1。
  测试另用 `--min-sdk-version 21` 再验一遍，那里 v1 是 `true`。
- `aapt2 dump badging` 打印应用名时会把双引号显示成 `\"`。这是它打印时的转义（清单里存的是原样），测试比对时还原回来。

## 9. 开发机上一次打包要多久（2026-11-26 实测，机器同时在跑别的任务，数字会抖）

- 小项目（3～6 个文件，含一张 1.2MB 的图）：0.1～1.8 秒。
- 大一点的项目（323 个文件、共 30MB：20 张 1MB 压不动的图 + 300 个 JS）：10～30 秒，安装包 20.1MB。
  时间主要花在算校验值、压缩和最后算安装包的 SHA-256 上（都是纯 Dart）。手机上的耗时**没有测过**。
