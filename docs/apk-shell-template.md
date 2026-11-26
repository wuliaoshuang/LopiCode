# 网页壳模板：给打包器的改动指南

对象：`assets/apk_shell/shell.apk`（源码和设计理由在 [shell_template/README.md](../shell_template/README.md)）。
这一页只讲“打包器要动哪里、怎么动才装得上”。模板的具体数字以 `assets/apk_shell/shell.json` 为准，打包器应当先核对
`sha256` 和 `templateVersion` 再动手。

核对状态的写法：**实测**＝2026-11-26 在开发机上用官方工具（build-tools 36.0.0 的 aapt2 / zipalign / apksigner）看到的；
**文档**＝对着安卓官方文档核对过（附网址）；**未核对**＝按通行理解写的，没有找到官方出处核对。真机上一概没有验证过。

## 这份指南自己验过没有

验过一遍（实测，2026-11-26）：用一段临时脚本照本页的写法直接改二进制——包名换成 `com.shuang.demo.app2`、应用名换成带中文的名字、
版本改成 77 / `2.3.4-测试`、加了 CAMERA 和两个定位权限、五个图标全换、放进带中文路径的网页和设置文件——然后对齐、用临时钥匙签名。
结果：`zipalign -c -v 4` 报 “Verification successful”，`apksigner verify` 报 “Verifies”，`aapt2 dump badging` 读出的包名、版本、
权限、应用名都是改后的值，图标路径不变。**但没有装到手机上**，所以“系统装不装、装上后壳能不能起来”仍然没有验证。

## 模板里有什么（实测）

| 条目 | 存放方式 | 说明 |
| --- | --- | --- |
| `AndroidManifest.xml` | 压缩 | 二进制清单，2696 字节 |
| `classes.dex` | 压缩 | 壳的代码 |
| `resources.arsc` | **原样存放，4 字节对齐** | 资源表，打包器不要改 |
| `res/mipmap-mdpi/ic_launcher.png` | 原样存放 | 48×48 |
| `res/mipmap-hdpi/ic_launcher.png` | 原样存放 | 72×72 |
| `res/mipmap-xhdpi/ic_launcher.png` | 原样存放 | 96×96 |
| `res/mipmap-xxhdpi/ic_launcher.png` | 原样存放 | 144×144 |
| `res/mipmap-xxxhdpi/ic_launcher.png` | 原样存放 | 192×192 |

没有 `META-INF/`（未签名），没有 `assets/`。文件名标志位是 UTF-8（通用标志第 11 位），没有附加字段以外的东西
（对齐用的填充由 zipalign 写在本地文件头的附加字段里），没有数据描述符。

## 打包器要放进去的

- 网页：`assets/www/<相对路径>`。入口默认 `assets/www/index.html`。
- 设置：`assets/lopi_shell.json`（可以不放；各键见 README 的「lopi_shell.json」）。入口不是 `index.html` 时必须放，写 `{"entry": "..."}`。
- 文件名含中文等非 ASCII 字符时，ZIP 条目名用 UTF-8 并置通用标志第 11 位（未核对：安卓读 assets 时按 UTF-8 认名字）。
- `assets/` 下的文件压缩或原样存放都能读（壳用 `AssetManager.open`，不用 `openFd`）。已经压过的格式
  （png / jpg / webp / mp3 / mp4 / woff2 等）原样存放更省事。

## 装得上的硬条件

1. `resources.arsc` 必须**原样存放**且数据起点按 **4 字节对齐**。targetSdk 30 及以上，资源表被压缩或没对齐的安装包装不上。
   （文档：<https://developer.android.com/about/versions/11/behavior-changes-11> 的 “Compressed resource files”。）
2. 其余原样存放的条目也按 4 字节对齐（`zipalign -c 4` 的要求；实测模板和冒烟产物都通过）。
3. 先对齐、再签名。v2 签名之后不能再改 ZIP 的任何字节。（文档：<https://developer.android.com/tools/zipalign>，用 apksigner 时必须在签名前对齐。）
4. minSdk 是 24，所以只要 v2 签名系统就认（安卓 7.0 起支持 v2）；v1 一起做是为了兼容老工具。（实测：`apksigner verify --min-sdk-version 24` 通过。）

## 改二进制清单

清单的结构（实测，逐块列出）：

```
文件头       类型 0x0003，头长 8，总长 2696
字符串池     @8     类型 0x0001，头长 28，块长 1520，41 个字符串，0 个样式，标志 0（UTF-16、未排序）
资源号表     @1528  类型 0x0180，18 项（对应字符串 #0–#17）
命名空间开始 @1608  前缀 android（#23），网址 #31
元素……
命名空间结束
```

字符串池（序号＝字符串在池里的下标）：

| # | 字符串 | # | 字符串 |
| --- | --- | --- | --- |
| 0 | theme | 21 | action |
| 1 | label | 22 | activity |
| 2 | icon | 23 | android |
| 3 | name | 24 | android.intent.action.MAIN |
| 4 | exported | 25 | android.intent.category.LAUNCHER |
| 5 | configChanges | 26 | android.permission.INTERNET |
| 6 | value | 27 | android.webkit.WebView.MetricsOptOut |
| 7 | minSdkVersion | 28 | application |
| 8 | versionCode | 29 | category |
| 9 | versionName | **30** | **com.lopicode.shell**（包名） |
| 10 | windowSoftInputMode | 31 | http://schemas.android.com/apk/res/android |
| 11 | targetSdkVersion | 32 | intent-filter |
| 12 | allowBackup | 33 | lopi.shell.MainActivity |
| 13 | hardwareAccelerated | 34 | manifest |
| 14 | supportsRtl | 35 | meta-data |
| 15 | usesCleartextTraffic | 36 | package |
| 16 | compileSdkVersion | 37 | platformBuildVersionCode |
| 17 | compileSdkVersionCodename | 38 | platformBuildVersionName |
| **18** | **1.0**（版本名） | 39 | uses-permission |
| 19 | 15 | 40 | uses-sdk |
| **20** | **LopiApp**（应用名） | | |

**#0–#17 是带资源号的属性名**，和资源号表一一对应，顺序不能动、中间不能插：

```
#0 theme 0x01010000        #1 label 0x01010001         #2 icon 0x01010002
#3 name 0x01010003         #4 exported 0x01010010      #5 configChanges 0x0101001f
#6 value 0x01010024        #7 minSdkVersion 0x0101020c #8 versionCode 0x0101021b
#9 versionName 0x0101021c  #10 windowSoftInputMode 0x0101022b
#11 targetSdkVersion 0x01010270   #12 allowBackup 0x01010280
#13 hardwareAccelerated 0x010102d3 #14 supportsRtl 0x010103af
#15 usesCleartextTraffic 0x010104ec #16 compileSdkVersion 0x01010572
#17 compileSdkVersionCodename 0x01010573
```

系统认属性靠的是资源号，不是名字。所以**新字符串一律加在池的末尾**（#41 起），不要插到前面。
`package`、`platformBuildVersionCode`、`platformBuildVersionName` 这三个属性没有命名空间、没有资源号，是靠名字认的。

各属性的类型（实测；类型码：0x01 引用、0x03 字符串、0x10 十进制整数、0x11 十六进制整数、0x12 布尔）：

| 元素 | 属性 | 原始值(raw) | 类型 | 数据 |
| --- | --- | --- | --- | --- |
| manifest | android:versionCode | 无 | 0x10 | 1 |
| manifest | android:versionName | #18 | 0x03 | 18 |
| manifest | android:compileSdkVersion | 无 | 0x10 | 35 |
| manifest | android:compileSdkVersionCodename | #19 | 0x03 | 19 |
| manifest | package | #30 | 0x03 | 30 |
| manifest | platformBuildVersionCode | 无 | 0x10 | 35 |
| manifest | platformBuildVersionName | 无 | 0x10 | 15 |
| uses-sdk | android:minSdkVersion / targetSdkVersion | 无 | 0x10 | 24 / 35 |
| uses-permission | android:name | #26 | 0x03 | 26 |
| application | android:theme | 无 | **0x01** | **0x7f020000** |
| application | android:label | #20 | 0x03 | 20 |
| application | android:icon | 无 | **0x01** | **0x7f010000** |
| application | allowBackup / hardwareAccelerated / supportsRtl / usesCleartextTraffic | 无 | 0x12 | 假 / 真 / 真 / 真 |
| meta-data | android:name / android:value | #27 / 无 | 0x03 / 0x12 | 27 / 真 |
| activity | android:name | #33 | 0x03 | 33 |
| activity | exported / configChanges / windowSoftInputMode | 无 | 0x12 / 0x11 / 0x11 | 真 / 0x40003fff / 0x10 |
| action、category | android:name | #24、#25 | 0x03 | 24、25 |

字符串类型的属性里，“原始值”和“数据”两处都写着同一个字符串序号。

### 改包名

把字符串 **#30** 换成新包名。它只被 `manifest` 的 `package` 属性用到一次，别处没有任何依赖包名的写法
（组件名是 `lopi.shell.MainActivity`，和包名无关），所以只换这一个字符串。壳的代码不用动。
`resources.arsc` 里记的包名仍是 `com.lopicode.shell`，不用改：应用自己的资源号（0x7f……）照常能查到
（未核对：这是这类工具的通行做法，没有找到官方文档明说；真机未验证）。

### 改应用名

把字符串 **#20** 换成新名字。它只被 `application` 的 `android:label` 用到一次，是字面字符串，不涉及资源表。
桌面图标下面的名字、最近任务里的名字、系统设置里的名字都来自它。

### 改版本

- 版本号（versionCode）：改 `manifest` 元素上 `android:versionCode` 属性的**数据**（类型 0x10 的 32 位整数），不在字符串池里。
- 版本名（versionName）：把字符串 **#18** 换掉。它只被 `android:versionName` 用到一次。

注意：换字符串会改变字符串池的长度，池里的偏移表、块长、整个文件的总长都要跟着重算；池的块长要补到 4 的倍数。

### 增删权限

每个权限是 `manifest` 下的一对块（开始元素 56 字节＋结束元素 24 字节）：

```
开始元素：元素名 #39（uses-permission），1 个属性：
          命名空间 #31，属性名 #3（name），原始值＝权限字符串的序号，类型 0x03，数据＝同一个序号
结束元素：元素名 #39
```

- 加权限：把权限全名（如 `android.permission.CAMERA`）加到字符串池末尾，照上面的样子在现有 `uses-permission` 结束块后面插一对块。
- 去掉联网：删掉 @1908 起的那一对块（共 80 字节）；字符串 #26 留在池里没关系。
- 同一个权限不要声明两次。

固定可选表（`shell.json` 的 `supportedPermissions`）和壳的对应行为：

| 权限 | 壳怎么用 |
| --- | --- |
| INTERNET | 默认有。去掉后网页连不了任何外部网址（本地网页照常） |
| ACCESS_NETWORK_STATE | 网页的 `navigator.onLine` / 联网状态变化事件要它才准 |
| CAMERA | 声明了，网页要摄像头时才向用户申请 |
| RECORD_AUDIO | 声明了，网页要麦克风时才向用户申请 |
| ACCESS_FINE_LOCATION ＋ ACCESS_COARSE_LOCATION | 声明了，网页要定位时才申请。**两个要一起加**：安卓 12 起单独申请“精确位置”系统不理（文档：<https://developer.android.com/develop/sensors-and-location/location/permissions/runtime>，原话是 “the system ignores the request on some releases of Android 12”） |
| VIBRATE | 网页的 `navigator.vibrate` 要它 |
| WAKE_LOCK | 网页的屏幕常亮接口（Screen Wake Lock）要它（未核对）。只想常亮可以不要权限：设置文件里 `keepScreenOn: true` |

待定的一条建议见本页末尾。

## 换图标

把五个 PNG 条目的内容整个换掉，路径不变、仍然原样存放并 4 字节对齐。不用改清单，不用改资源表
（资源表里只记了路径，没记文件大小或校验值——实测：换掉 PNG 后 aapt2 照常读出）。

- 必须是 PNG，边长照表（48 / 72 / 96 / 144 / 192）。尺寸不对系统会自己缩放，不会装不上，但会糊。
- 五个都换。只换一部分的话，不同密度的手机上会看到不同的图标。

## 不要动的

- `classes.dex`、`resources.arsc`。
- 清单里的 `android:theme`、`android:icon`（引用资源号）、`activity` 的 `android:name`、`minSdkVersion`、`targetSdkVersion`。
- 不要往清单里加 `<provider>`、自定义 `<permission>` 或别的组件：壳里没有对应的代码。

## 给界面 / 预览的几个事实

- 网页在壳里的地址是 `https://lopi.invalid/<相对 www 的路径>`，是 https 安全环境。
- 找不到且不带扩展名的页面地址默认回退到入口（单页应用路由）；可用 `spaFallback: false` 关。
- 整页跳到外部网址默认交给系统浏览器。

## 待定（要霜霜或协调者定）

- **麦克风要不要连带 `MODIFY_AUDIO_SETTINGS`。** 网页录音 / 通话时，系统 WebView 会去调音频通路，这要 `MODIFY_AUDIO_SETTINGS`
  （安装即有的普通权限，不弹窗）。没有它多数情况下录音仍然能用，但可能出现声音走错通路（未核对，真机未验证）。
  建议：勾“麦克风”时连带加上，像定位连带“大概位置”一样。这不在约定的固定表里，所以先不加，等定。
