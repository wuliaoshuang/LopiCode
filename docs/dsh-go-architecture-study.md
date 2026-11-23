# dsh-Go 架构学习笔记，与 LopiCode 的对照

> 写于 2026-11-23。只读了两边的源码，没有运行任何东西，也没有改任何代码。
> dsh-Go 是 AGPL-3.0 项目，这里只学做法、用自己的话讲，不搬它的代码、文案和素材。
> 对照的 LopiCode 版本是 HEAD `6de1de3`（写这份笔记时工作区里还有一个没提交的新文件 `lib/ui/push_drawer.dart`，不算在内）。
> 哪些地方没读到、哪些只是粗看，都写在最后的“没读到和不确定的地方”一节。

先说结论，三句话：

1. dsh-Go 的界面代码量是我们的十几倍（`app/lib` 约 49 万行、1200 多个文件，其中约 11 万行是脚本生成的文案；我们约 2.3 万行、74 个文件），它能不散架，靠的不是特别严的代码检查规则，而是三样东西：**状态统一放一处、每个状态只有一个主人**；**一个“谁能引用谁”的守门测试**；**一千多个测试文件加一千张截图基准图，每次改动由机器自动跑**。
2. LopiCode 现在的状态管理是“手写服务对象 + ChangeNotifier + 每个页面自己 setState”，功能都能用，但有几处实打实的隐患：存盘不是原子写入、一个 1451 行的大对象管了所有事、任何小变化都让整页重画、过期的网络结果没有统一的丢弃办法。
3. 换成 Riverpod 可以分五步做，估计 10–14 个工作日；但**最该先做的几件事和 Riverpod 无关**（存盘安全、更严的检查规则、引用方向守门、一键检查脚本）。

---

## 1. dsh-Go 用了哪些库、哪些原生能力

### 1.1 Flutter / Dart 库（`app/pubspec.yaml`，应用版本 1.3.0，Dart SDK ^3.13.4；CI 用 Flutter 3.47.7）

| 库 | 版本 | 做什么 |
|---|---|---|
| flutter_riverpod | ^3.4.3（锁定 3.4.3） | **状态管理**，全应用只有这一套 |
| clock | ^1.1.3 | 可替换的时钟（实际只在一个文件里用到，见 2.5） |
| shared_preferences | ^2.5.6 | 普通设置（开关、阈值之类） |
| flutter_secure_storage | ^11.2.0 | API Key 等密钥，只进系统安全存储 |
| sqlite3 | ^3.9.1 | 本地数据库（会话搜索、酒馆数据等） |
| path_provider | ^2.1.6 | 找应用自己的目录 |
| http | ^1.6.0 | 网络请求 |
| crypto / cryptography / pointycastle | ^3.0.7 / ^2.9.0 / ^4.0.0 | 哈希、加密（远程连接的加密通道、备份加密） |
| xterm | ^4.0.0 | 终端界面（和我们用的是同一个） |
| dartssh2 | 4.1.0（**放在仓库里的副本**，带自己的补丁） | SSH 连接 |
| webview_flutter / webview_flutter_android | ^4.14.1 | 内嵌网页（官方 Web 界面兜底、插件网页） |
| gpt_markdown | ^1.4.0 | 聊天里的 Markdown 渲染 |
| val_latex_flutter | ^0.1.3 | 数学公式 |
| re_highlight | ^0.0.3 | 代码高亮（我们也用） |
| scrollable_positioned_list | ^0.3.8 | 能跳到指定条目的长列表（聊天列表） |
| url_launcher | ^6.3.3 | 打开外部链接 |
| share_plus | ^13.3.1 | 系统分享 |
| connectivity_plus | ^7.3.2 | 监听网络变化（断网重连） |
| image_picker / file_picker | ^1.2.4 / ^13.1.0 | 选图、选文件 |
| mobile_scanner | ^7.5.0 | 扫二维码（远程配对） |
| flutter_webrtc | ^1.6.3 | 远程连接的点对点通道 |
| sherpa_onnx（及四个 Android 架构包） | 1.13.4 | 本机语音识别 |
| archive / image / html / yaml / timezone | ^4.6.0 / 4.12.0 / ^0.15.6 / ^3.1.4 / ^0.11.2 | 压缩包、图片处理、HTML 解析、YAML、时区 |
| flutter_localizations + intl | SDK 自带 / any | 中英文界面 |
| dsh_client / dsh_remote / dsh_tavern | 仓库内的包 | 见第 3 节 |

开发用的只有：`flutter_test`、`flutter_lints ^6.0.0`、两个平台接口包（测试里造假的存储和 WebView）。**没有用代码生成**（没有 riverpod_generator、freezed、build_runner），状态类全是手写的。

### 1.2 原生（Android Kotlin）能力

Kotlin 一共 356 个文件、约 7 万行（我们是 2 个文件、124 行）。按目录分：

| 目录 | 做什么 |
|---|---|
| `runtime/`（39 个文件，约 9400 行） | **本机引擎的全部生命周期**：解压安装 Ubuntu（`RuntimeInstaller`、`TarExtractor`）、用 PRoot 启动进程（`DshProcess`）、状态机和“运行代次”（`RuntimeController`）、前台服务保活（`DshService`）、崩溃分类与安全模式（`CrashClassifier`、`SafeMode`）、升级事务（`EngineUpgrade`）、“上一次能用的版本”恢复（`LastKnownGood`）、日志打码（`LogRedactor`） |
| `phone/` | 手机操控：无障碍读屏和点按、Shizuku / ADB 特权通道、虚拟屏、最终审批门 |
| `update/` | 应用自更新：下载、校验、安装 |
| `pet/`、`companion/` | 桌面宠物悬浮窗、伙伴小组件和提醒 |
| `notify/`、`tile/`、`shortcuts/`、`icons/`、`launch/` | 通知、快捷设置磁贴、桌面快捷方式、换图标、开屏 |
| `files/`、`media/`、`nativemedia/`、`share/`、`links/` | 文件选择保存、相册、音视频、接收分享、深链 |
| `voice/`、`speech/`、`mlkit/` | 语音输入、朗读、文字识别 |

用到的系统能力（从清单文件看）：前台服务（特殊用途、位置、屏幕投射三种类型）、通知、悬浮窗、安装应用、忽略电池优化、唤醒锁、录音、相机、读写存储、开机自启、Shizuku。

Dart 和 Kotlin 之间走“平台通道”，每个功能域一条，名字都以 `dsh/` 开头（`dsh/runtime` 加事件流 `dsh/runtime/events`、`dsh/phone`、`dsh/update`、`dsh/files` 等二十来条）。`dsh/runtime` 上有三十多个方法：查状态、安装、启动、停止、取日志、重置、恢复上一个能用的版本、安全模式预检、电池优化豁免等。

打包上的几个做法：
- PRoot 等可执行文件改名成 `lib*.so` 放进 `jniLibs`，并开 `useLegacyPackaging`，这样安装后在系统的原生库目录里、可以执行。**这点我们和它一样。**
- 按架构分两种包（arm64 真机、x64 模拟器），各只带自己的运行时。
- `minSdk 26`、`targetSdk 28`。targetSdk 故意压在 28，文档里说是和 Termux 一样，为了避开 Android 10 起对“在应用私有目录里执行程序”的限制。
- **本机引擎的真实状态以 Kotlin 那边为准**，Dart 只是照着事件流抄一份“镜像”。

---

## 2. 状态管理怎么写

### 2.1 总的规矩（写在它的 `docs/architecture.md` 里）

- 全应用只有一个 `ProviderScope`，在 `main.dart`。
- **一个状态只有一个主人。** 跨页面的状态一律放 `lib/state/`（约 140 个文件）；只有某一页自己用的才留在页面文件里。
- 界面不直接改状态，只能调主人的方法（写法是“读到主人，再调它的方法”）。
- 全部手写 `Notifier` / `AsyncNotifier`，不用代码生成。

数一下实际用量（`app/lib` 全部）：

| 种类 | 个数 | 用来干什么 |
|---|---|---|
| 普通 `Provider`（含 family / autoDispose 变体） | 约 375 | 提供一个对象或一个算出来的值；很多是“可替换的接缝”（见 2.5） |
| `NotifierProvider`（含变体） | 约 162 | 有状态、有方法的“主人” |
| `FutureProvider`（含变体） | 约 101 | 一次性的异步读取 |
| `AsyncNotifierProvider`（含变体） | 16 | 异步初始化、还带方法的主人（比如连接） |
| `StreamProvider`（含变体） | 17 | 持续的事件流 |
| `StateProvider` / `ChangeNotifierProvider` | 0 | 不用老式写法 |

界面一侧：340 个文件用了 `ConsumerWidget` / `ConsumerStatefulWidget`；`ref.watch` 约 1750 处、`ref.read` 约 2300 处、`ref.listen` 约 180 处、`.select(` 511 处。

### 2.2 Notifier、family、autoDispose 各怎么用

用“余额”和“单个会话的用量”两个文件举例（`state/balance_state.dart`、`state/usage_state.dart`）：

- **状态是一个不可变的小对象**（比如余额状态：查到没有、金额、什么时候查的、提醒线、是否加载中），要改就用 `copyWith` 造一个新的整体换掉。界面拿到的永远是一份完整、前后一致的快照。
- **Notifier 是主人**：它的 `build()` 负责算出初始状态，并在里面“订阅”自己依赖的别的状态。比如余额的主人订阅了“设置里的 API Key”——Key 一变，`build()` 自动重跑，旧的查询记录作废。
- **family = 按参数分身**。用量主人按“会话 id”分身，每个会话各有一份；聊天主人也是按会话 id 分身；连接按“主机”分身。
- **autoDispose = 没人看就回收**。会话页关掉，那个会话的用量主人就销毁，销毁时自动取消它订阅的事件流（在 `build()` 里登记“销毁时做什么”）。全局只有一份、要一直活着的（余额、设置、主机列表）不加 autoDispose。聊天主人是 autoDispose，但正在跑的那一轮会手动“保活”，免得切页面把回复掐断。
- **不同种类各管一摊**：只读的衍生值用普通 Provider（比如“当前该用哪条连接”就是看“当前主机”再转给本机或远程连接）；要等的初始化用 AsyncNotifier（连接建立）；事件流用 StreamProvider（连接状态）。

### 2.3 Provider 怎么组织

- 文件按“域”命名：`xxx_state.dart` 里放这个域的状态类、主人类、以及文件末尾的 provider 定义。
- 依赖关系是一条链，方向固定。以连接为例：主机列表 → 当前主机 → 该主机的链路 → 该主机的连接 → “当前连接”。上游一变，下游自动重算，不用手工通知。
- 有“唯一装配点”的说法：比如三种连接方式（本机、SSH、中继）只在一个函数里拼装，别处不许自己拼。

### 2.4 怎么防“旧数据覆盖新数据”

这是它最值得学的部分，一共四招，层层叠加：

1. **代次（generation）**。主人里放一个整数。发请求前记下当时的代次；请求回来时先比一下，对不上就**直接丢掉结果**。余额主人就是这样：API Key 一换，代次加一，用旧 Key 发出去还没回来的那次查询回来后被丢弃，不会把旧账号的余额写到新账号头上。
2. **“还活着吗”检查**。每个 `await` 之后、写状态之前，先问一句“我还没被销毁吧”（`ref.mounted`）。全库有 420 多处。聊天主人里更严，一个操作要同时满足“我还活着、连接还是那条连接、代次还是那一代”才允许写回。
3. **序号（seq）**。服务器推来的每条更新都带序号。用量主人给每个字段各记“上次是第几号更新的”，来了更小或相同的序号就不理。这样“先发的慢请求晚到”不会盖掉“后发的快更新”。
4. **票号（ticket）和纪元（epoch）**。同一类读取连发多次时，每次领一个递增的票号，回来时只有最新票号的结果作数。另有一个全局的“凭据纪元”计数器：改凭据**之前**先把它加一，所有依赖凭据的缓存自动作废——哪怕改凭据那一步后来失败了也照样作废，宁可多刷新一次。

配套的还有两招“省请求”：
- **同一时间只发一个**：正在查的时候又有人要查，直接把正在跑的那个结果给他，不另发。
- **节流**：余额最多每分钟问一次；换了 Key 则立刻清零重来。

原生一侧同样的思路：Kotlin 的 `RuntimeController` 有“运行代次”和“停止代次”两个数，所有后台线程回来时都要核对“我这一代还是不是当前这一代、有没有被停止过”，对不上就什么都不做。

### 2.5 怎么做到可测试

- **把“外部世界”都做成可替换的接缝**。真正发网络请求的函数不直接调用，而是通过一个 provider 拿（比如“余额获取器”）；测试时一行就能换成假的。时间、设备信息、HTTP 客户端、SSH 传输工厂都是这个套路。测试目录里“替换 provider / 新建容器”的写法出现了 4200 多次。
- **时钟可换**，但做法不统一，三种并存：有的是主人类上一个可改的静态“现在几点”函数（余额就是这种，测试结束要记得还原）；有的是专门的时钟 provider；有的是构造函数参数。`clock` 这个库只在一个文件里用到。**这点不必照抄，我们统一成一种更好。**
- **纯逻辑单独成函数**。余额那里，“把接口返回的文字解析成金额”“把 HTTP 状态码归类成三种结果”都是不碰界面、不碰网络的纯函数，可以直接单测。
- **结果用“封闭的几种类型”表达**（成功 / Key 无效 / 暂时拿不到），处理的地方必须每种都写到，漏一种编译就不过。
- **不依赖界面的包整个拎出去**（`dsh_client` 等，见第 3 节），用最普通的 Dart 测试就能跑，不需要启动界面。

### 2.6 界面怎么订阅

- 页面继承 `ConsumerWidget`（或有状态版），在 `build` 里“看”（watch）它需要的状态。
- **只看需要的那一小块**：用 `select` 挑出一个字段，只有这个字段变了才重画。聊天页有明文规定——页面外壳只看一小组挑出来的值，完整的聊天状态只在消息列表那一个部件里看；侧边抽屉滑动时聊天区不许重画。
- “看”用于画界面；“读”（read）用于按钮回调里调方法；“听”（listen）用于做一次性的事（弹提示、跳页面）。
- 改动走主人的方法，不在界面里直接改状态对象。

---

## 3. 代码怎么分层分包、谁依赖谁

### 3.1 仓库层面

```
app/               Flutter 应用（界面 + 状态 + 各平台原生代码）
packages/
  dsh_client/      纯 Dart：和引擎通信（登录、请求、长连接、事件流、把事件折叠成聊天记录）
  dsh_remote/      纯 Dart：远程连接（账号、加密通道、中继/点对点）
  dsh_tavern/      纯 Dart：角色扮演引擎
  dartssh2/        第三方 SSH 库的仓库内副本 + 补丁
runtime/           引擎运行时的构建脚本、补丁、桥接代码（Node / Python / shell）
sdk/plugin-kit/    插件开发工具
tooling/           构建、发版、真机脚本
docs/              架构、设计、维护合同、测试记录、用户指南
```

依赖方向（箭头表示“依赖”）：

```
app ──> dsh_client      （67 个文件，128 个测试文件；只依赖 crypto、sqlite3）
app ──> dsh_remote ──> dsh_client   （22 个文件，35 个测试文件）
app ──> dsh_tavern      （203 个文件，297 个测试文件；不依赖 Flutter）
app ──> dartssh2
```

要点：**三个自己写的包都不依赖 Flutter，也不反过来依赖 app**。和引擎说话的全部细节（协议、重连、去重、序号）都关在 `dsh_client` 里，界面那边换成什么样都不影响它，它也能脱离手机单独测试。`dsh_remote` 通过实现 `dsh_client` 里的一个“传输通道”抽象，把远程连接伪装成和本机连接一样的东西，所以上层代码不用分本机还是远程。

### 3.2 app 内部

```
ui/        界面（738 个文件，约 25 万行，按功能分 40 个子目录）
state/     跨页面的状态（约 140 个文件，约 4.2 万行）
runtime/ phone/ update/ plugins/ remote/ ...   各功能域的非界面逻辑和平台通道
l10n/      中英文文案（由脚本生成，不手改）
```

边界规则只有一条硬的：**`ui/` 可以引用任何目录；`ui/` 以外的任何文件都不许引用 `ui/`**（`main.dart`、`app.dart` 两个入口除外）。也就是：界面知道状态，状态不知道界面。

这条规则不是靠自觉，是靠一个测试守着（见 4.4）。它自己也承认不完美：历史上已经有 56 条违规的引用，测试里列成白名单，**只许减少、不许增加**；`ui/` 内部互相引用不管（文档里直说已经有循环）。

数据流（一次对话）：界面输入 → 聊天主人的发送方法 → `dsh_client` 发请求 → 引擎的事件流 → `dsh_client` 把事件折叠成聊天记录 → 聊天主人更新状态 → 界面重画。

---

## 4. 它靠什么防止代码腐化

### 4.1 代码检查规则（lint）——**比预想的松**

如实说：`app/analysis_options.yaml` 只有十行，就是 Flutter 官方推荐规则集（`flutter_lints`）原样，加一条“每行最长 120 字符”，再排除 `build/`、`android/`、`ios/`。**应用本体没有额外开任何严格项。**

严格项开在三个纯 Dart 包里（`dsh_client`、`dsh_remote`、`dsh_tavern` 三份一模一样）：

| 开关 | 意思 |
|---|---|
| `strict-casts: true` | 不许把“不确定类型”的东西悄悄当成某个具体类型用，必须明写转换 |
| `strict-raw-types: true` | 用列表、映射时必须写清楚里面装的是什么类型 |
| `prefer_final_locals` | 不会再改的局部变量必须标成不可变 |
| `unawaited_futures` | 发起了一个异步操作却没等它，必须明确写“我故意不等”，否则报错 |

所以它的策略是：**越底层、越被大家依赖的代码，规则越严**；界面层靠测试兜底。

### 4.2 测试分层

| 层 | 规模 | 说明 |
|---|---|---|
| 纯 Dart 包的单元测试 | 128 + 35 + 297 个测试文件 | 不启动界面，最快 |
| app 的单元测试和界面测试 | 1354 个测试文件，目录结构和 `lib/` 一一对应 | 状态主人用“容器 + 替换 provider”测；界面用部件测试 |
| golden 截图比对 | 1006 张基准图，分散在各功能目录的 `goldens/` 下 | 界面渲染出来和基准图逐像素比；CI 固定了字体的具体版本，否则不同机器画出来不一样 |
| 架构测试 | `test/arch/` | 引用方向守门（4.4） |
| 集成 | `test/integration/` 有一个接线测试；`integration_test/` 里只有一个 iOS 引擎检查 | 很薄，真机上的事靠人 |
| Kotlin 单元测试 | 290 个测试文件 | 不需要手机，在电脑的 Java 环境里跑 |
| 引擎桥和补丁测试 | `runtime/tests/` 下的 Node、Python 测试 | 每个补丁配一个同名测试 |
| 真机验证记录 | `docs/testing/` 14 篇 | 不是自动测试，是“某功能在哪台手机上怎么验的”的记录 |

所有测试文件开跑前都会先过一个公共入口（`flutter_test_config.dart`）：装好真字体（缺字体直接算失败，不许用方块字凑合）、把全局开关复位成固定值（语言固定中文、随机提示固定第一条、不读真设备信息）。这是截图能稳定比对的前提。

### 4.3 CI 门禁（`.github/workflows/`）

`ci.yml` 是主门禁，PR 上只跑改动涉及的部分，合进主分支后跑全量，最后汇总成一个叫 `CI OK` 的总开关：

| 任务 | 检查什么 |
|---|---|
| 生成物同步 | 文案、用户指南、插件教学技能、回放查看器这几样“由脚本生成的文件”是否和源头一致（重新生成一遍，看有没有差异） |
| 工具脚本自测 | `tooling/`、`app/tool/`、`runtime/tests/` 下所有 Python 脚本的单元测试 |
| 插件 SDK、市场、官网、分享服务 | 各自的测试和类型检查 |
| Flutter analyze | 静态检查；再生成一遍文案，确认没人手改生成结果 |
| Flutter 测试 | 分 3 片并行。PR 上把一个目录的测试“打包”成一个进程跑（省编译时间）；包里失败的再单独跑一次，以单独跑为准；主分支上每个文件各跑各的。失败时把截图差异图存下来供人看 |
| Dart 包 | 四个包并排做静态检查和测试 |
| 运行时和桥 | 引擎补丁、桥接路由的测试，包括对一个真的引擎进程测 |
| Android JVM | Kotlin 单元测试 |
| Android 启动策略 | 进程清理和启动策略的脚本测试 |

其它几个：
- `pr-gate.yml`：外部人提的 PR 自动关闭（它现在不收外部代码）。
- `goldens.yml`：手动触发，重新渲染截图基准图，把变了的图打包给人审，**不自动替换**。
- `runtime.yml`、`ios-*.yml`、`ohos-compile.yml`：运行时构建、iOS 和鸿蒙的编译检查。

细节上的讲究：所有第三方 CI 动作都钉死到具体的提交号，不用“最新版”；装依赖时强制按锁文件来（`--enforce-lockfile`），防止悄悄升版本。

### 4.4 自定义守门脚本

| 脚本 | 守什么 |
|---|---|
| `app/tool/import_graph.dart` + `app/test/arch/import_direction_test.dart` | **引用方向**：扫 `lib/` 里所有引用关系，`ui/` 以外引用 `ui/` 的边必须在白名单里；白名单只减不增。脚本还能单独运行，列出现状和最大的循环引用 |
| `app/tool/l10n_merge.py`（带 `--check`） | 中英文文案：两种语言的条目一一对应、键名唯一、占位符一致；生成结果不许手改 |
| `app/tool/l10n_scan.py`、`l10n_catalog.py` | 扫代码里漏翻译的写死文字、整理文案目录 |
| `app/tool/guide_sync.py`（带 `--check`） | 用户指南和应用里内置的“教学技能”保持同步 |
| `app/tool/bundle_tests.py` + `app/test/bundle_solo.txt` | 把测试按目录打包；“打包跑不过、单独跑能过”的文件登记在案，等于一份“这些测试互相有干扰”的欠账清单 |
| `tooling/check_runtime_bundle.py` | 打包前检查运行时文件齐不齐、校验值对不对（PRoot 那四个文件必须都在） |
| `tooling/check_apk_jni.py` | 打好的安装包里，原生代码要用的几个类有没有被混淆工具误删 |
| `tooling/build_number.py`、`apk_delta.py`、`release_assets.py` | 版本号生成、增量包、发版物料 |
| `tooling/dev-run.sh` | 真机热重载；特意不用会“失败就先卸载”的命令，免得清掉手机上的数据 |
| `runtime/patches/pins.json` | 每个引擎补丁的“打之前、打之后”校验值都记着，对不上就拒绝构建 |

这些脚本自己也都有测试（`test_*.py`），CI 里会跑。

### 4.5 文档约定

- `docs/architecture.md` 是总入口：全景图、目录地图、状态主人表、通道表、“要改什么先读哪里、改完跑什么”的导航表。开头就写明“以代码为准，发现过时直接改这里”。
- `docs/design/`：改某个子系统前要读的设计说明。
- `docs/maintenance/`（现有 105 篇，其中大多数叫 `*-contract.md`）：**“合同”**——某个行为或某个补丁必须满足什么、边界在哪、怎么复现、对应哪个测试、哪些没验证。改一个补丁必须同时改四样：补丁文件、校验值、同名测试、同名合同。（架构文档里写的是 61 篇，数字已经过时，这也印证了它自己那句“以代码为准”。）
- `docs/testing/`：真机验证记录。
- PR 模板要求填：为什么改、要提醒的事、改动概要、**实际跑了哪些检查和结果**——明确写着“跳过、中止、失败不能记成通过，没验证的范围要写清”。

### 4.6 给 AI 助手的规则文件

`CLAUDE.md` 是指向 `AGENTS.md` 的链接，只维护一份。主要规矩：

- **先读再改**：改之前读贡献说明和架构文档。
- **按改动面选检查**，并在报告里写实际执行的命令和结果。
- **不手改生成的文件**，改源头再跑生成器。
- **改协议要看另一头**：客户端、桥、插件协议改一处，要查另一端的调用方和旧版本兼容。
- **危险操作以对方的真实回答为准**（删会话、权限、凭据），不用本地推断代替；失败要有稳定的错误码，不许悄悄吞掉。
- **凭据**：不记录、不回显、不保存完整的 Key、令牌、登录态；日志外发前人工看一遍，自动打码不算保证。
- **Git 安全**：开工前先同步到最新；只暂存明确的路径，不许一把全加；没要求不提交、不推送、不打标签；不强推主分支；别人的未提交改动不许丢。
- **真机验证**：手机操控、PRoot、启动、更新安装这类改动必须真机验；没跑的要明写“未运行”和原因；编译通过不等于能用。
- **审查原则**：防回归优先、避免过度设计、严格控制范围、只报本次改动引入的实质问题并说明位置和触发条件。
- **“过度防御也是缺陷”**：只对说得出触发条件的失败加防护；新增的状态标记必须写清“谁置位、谁清除、清不掉会怎样”，写不清就别加；错误只有两种出口——能恢复的给出可执行的结果，不能恢复的明确失败。
- **先做最短能跑通的**：不建 v1 / v2 并行目录；出问题先读真实输出找根因，不靠加重试掩盖。
- 另有五个流程技能（提 PR、审查、缺陷报告、安全检查、大范围审计）放在 `.agents/skills/`。

---

## 5. 逐条对照 LopiCode 现状（HEAD 6de1de3）

### 5.1 用的库

| | dsh-Go | LopiCode | 差在哪 / 建议 |
|---|---|---|---|
| 状态管理 | flutter_riverpod 3.4.3 | **没有专门的库**，Flutter 自带的 ChangeNotifier | 见 5.2 和第 6 节 |
| 普通设置 | shared_preferences | 自己写的一个 JSON 文件（`lib/core/stores.dart`） | 可以不换，但写入方式要加固（5.2 第 1 条） |
| 密钥 | flutter_secure_storage 11.2.0 | 同款同版本，还多了“不可用时退回内存并如实标注” | 一致，我们略好 |
| 终端 | xterm 4.0.0 | xterm 4.0.0 + flutter_pty 0.4.2 | 一致 |
| SSH | dartssh2 4.1.0（仓库内副本 + 补丁） | dartssh2 ^4.1.0（直接用官方包） | 目前不需要副本；哪天要打补丁再学它 |
| 网络 | http | http | 一致 |
| 时钟 | clock（基本没用上） | 没有 | 建议自己定一个统一的“现在几点”入口（5.5） |
| 代码检查 | flutter_lints 6 | flutter_lints 6 | 一致，都偏松（5.4） |
| 我们独有 | — | shelf（预览服务器）、re_editor（编辑器）、material_ui | — |

### 5.2 状态管理（如实评估）

**现在的写法**是三种混着用：

1. **手写服务对象 + ChangeNotifier**。8 个类继承了 ChangeNotifier：`AppServices`（`lib/app_services.dart`）、`ProjectSession`（`lib/project_session.dart`）、`QuotaStore`（`lib/agent/quota.dart`）、`LinuxRuntime`（`lib/runtime/linux_runtime.dart`）、`RuntimeDiagnostics`（`lib/runtime/runtime_diagnostics.dart`）、`TerminalSession`（`lib/terminal/terminal_session.dart`）、`BuildJob`（`lib/build/build_controller.dart`），以及界面用的抽屉控制器。全库 `notifyListeners()` 68 处。
2. **“全家桶”对象往下传**。`AppServices` 把设置、密钥、项目仓库、模型配置、预设、技能、自动化、额度、运行环境、调度器全挂在自己身上，通过 `AppScope` 放进界面树，页面用 `AppScope.of(context)` 取（71 处）。测试时整个替换。
3. **页面自己 setState**。136 处 `setState`；页面在 `initState` 里手工 `addListener`、`dispose` 里手工 `removeListener`（各十几处），收到通知就整页 `setState(() {})`。

**好的地方**（应该保留）：
- 外部依赖基本都能在测试里替换（模型客户端工厂、查余额的网络、伪终端创建方式、运行环境宿主），`test/support/harness.dart` 一行就能搭出测试环境。
- `agent/` 和 `core/` 基本不依赖界面，能脱离界面测试。
- `QuotaStore` 已经有可替换的时钟、同一时间只发一个请求、一分钟节流——和 dsh-Go 余额主人的三招里对上了两招半。
- `AutomationScheduler.tick(now)` 把“现在几点”做成参数，好测。
- `ProjectSession` 销毁后不再通知（`_disposed` 那个保护）。

**隐患**（按严重程度排）：

1. **存盘不安全，坏一次可能丢全部设置。** `lib/core/stores.dart` 的 `SettingsStore`：读文件时只要出一点错（比如上次写到一半手机没电，文件是半截的），就**悄悄当成“什么设置都没有”**；之后任何一次保存都会把这个几乎空的内容整个写回去——渠道列表、模型、预设、额度记录全在这一个文件里，一起没了。写入本身也不是“先写临时文件再改名”，而是直接覆盖；多处同时保存时也没有排队。同样的写法还在：`lib/project_session.dart`（`_saveRun`、`_saveIndex`，聊天记录和对话索引；`_readMessages` 读坏了当空对话，下一轮保存就盖掉原记录）、`lib/core/project_store.dart`（`_saveRegistry`、`_writeMeta`）、`lib/agent/automation.dart`（`save`）、`lib/agent/team.dart`（`_changed`）。**这是最该先修的，而且和用不用 Riverpod 无关。**

2. **`ProjectSession` 是个 1451 行的“什么都管”的对象**（`lib/project_session.dart`）。对话列表、每段对话的运行状态、消息存盘、确认卡、提问卡、排队和插话、子代理、团队任务板、自动化任务、终端列表、预览服务器、附件、压缩、导出，都在这一个类里，33 处通知。后果：
   - 任何一处变化（哪怕只是终端切了个标签）都会通知所有监听者；
   - 模型每吐一小段字，`_execute` 里就通知一次，`lib/ui/chat_screen.dart` 的 `_onSession` 就把**整个聊天页**重画一次，`lib/ui/project_shell.dart` 也跟着重画。对话一长会卡；
   - 聊天条目是可变对象（比如回复条目的文字直接被追加修改），界面没法判断“到底哪条变了”，只能全画；
   - 新功能只能继续往这个类里加，越加越难改。

3. **全应用重画的“touch”**。`AppServices.touch()` 会让 `lib/app.dart` 里包着整个应用的那层重建。设置页、模型页、自动化页共 15 处调用；更要注意的是 `lib/automation_scheduler.dart` 的 `tick` 每 30 秒无条件调一次——也就是**应用开着时每半分钟整个界面树重建一遍**，不管有没有自动化任务。目前页面少感觉不到，但这是白花的开销，也可能打断正在进行的动画或输入。

4. **过期结果没有统一的丢弃办法。**
   - `lib/agent/quota.dart` 的 `_refresh`：请求发出后，如果用户改了这个渠道的 Key、或点了“重新开始计算”，旧请求回来照样写入并累加“已用”。没有代次检查。
   - `lib/project_session.dart` 的 `selectConversation`、`loadChat`、`openRun`：中间有等待，等待期间对象被销毁或又切了一次，后面的代码照样往下走（通知被 `_disposed` 挡住了，但存盘、查余额这些副作用没挡）。
   - 界面里靠 129 处手写的“还在不在界面上”检查（`mounted`）兜着，每一处都是可能漏写的地方。

5. **时间没有统一入口。** `DateTime.now()` 直接调用 41 处（`project_session.dart` 13 处、`automation.dart` 5 处、`automation_screen.dart` 5 处等），只有 `QuotaStore` 和调度器的 `tick` 可以在测试里换时间。跟时间有关的逻辑（自动化到点、对话排序、文件名）测起来要靠真等或绕路。

6. **页面里自己管的状态太多。** `lib/ui/settings_ai.dart` 22 处 setState、`lib/lowcode/builder_screen.dart` 15 处、`lib/ui/files_tab.dart` 和 `lib/ui/automation_screen.dart` 各 14 处。其中一部分其实是“跨页面都该知道”的数据（比如渠道列表），现在的做法是改完后调一下 `touch()` 让全应用刷新——等于用“全部重画”代替“谁关心谁更新”。

7. **手工订阅容易漏。** `addListener` 18 处、`removeListener` 16 处，数目不相等。我没有逐一核对每一对（有的监听对象随页面一起销毁，不取消也没事），但这类手工配对正是 Riverpod 能自动管掉的。

### 5.3 分层分包

| | dsh-Go | LopiCode |
|---|---|---|
| 纯逻辑单独成包 | 3 个不依赖 Flutter 的包 | 没有 `packages/`，全在 `lib/` |
| 界面与逻辑的边界 | `ui/` 外不许引用 `ui/`，有测试守门 | **没有规则也没有守门** |

LopiCode 的现状：
- `lib/agent/`（13 个文件）和 `lib/core/` 基本是纯逻辑，这点是好的。例外：`agent/quota.dart` 引了 Flutter 的基础库（为了 ChangeNotifier），`core/secure_secret_store.dart` 引了 Flutter 的服务库（平台插件需要，合理）。
- **界面和逻辑混放在同一个功能目录里**：`lib/build/`（`build_controller.dart` 是逻辑，`build_screen.dart` 是页面）、`lib/runtime/`（`runtime_screen.dart` 是页面）、`lib/ssh/`（`ssh_connect_screen.dart`）、`lib/lowcode/`（`builder_screen.dart` 1534 行）、`lib/terminal/terminal_input.dart`（是个界面部件）。这些页面都引用了 `lib/ui/` 里的公共部件，所以“`ui/` 外不引用 `ui/`”这条规则在我们这里现在是不成立的。
- `lib/build/build_controller.dart`（逻辑）引用了界面库；`lib/app_services.dart`（服务）为了主题模式也引用了界面库。
- `lib/project_session.dart` 和 `lib/automation_scheduler.dart` 直接放在 `lib/` 根上，不属于任何一层。
- `lib/build/build_screen.dart` 引用了 `lib/lowcode/builder_screen.dart` 里的一个部件——页面之间横向引用。

建议（由轻到重）：
1. 先定规矩并加守门测试：逻辑目录（`agent/`、`core/`、以及各功能目录里不叫 `*_screen.dart` 的文件）不许引用界面库和 `ui/`；现有违规列白名单，只减不增。
2. 把 `*_screen.dart` 和界面部件逐步挪到 `ui/<功能>/` 下。
3. 等 `agent/` 稳定后，再考虑拎成 `packages/lopi_agent` 这样的纯 Dart 包（它已经基本满足条件，只差 `quota.dart` 那一处）。这步不急。

### 5.4 代码检查规则

两边的应用本体一样松：都是 `flutter_lints` 默认集。我们的 `analysis_options.yaml` 除了排除目录外，规则部分全是注释掉的样板。

建议直接抄它三个包里的四项，开在整个 LopiCode 上：`strict-casts`、`strict-raw-types`、`unawaited_futures`、`prefer_final_locals`。说明两点：
- 我们代码里 `dynamic` 出现 135 处（主要是 JSON 的 `Map<String, dynamic>`），`strict-casts` 一开预计会报出一批要改的地方。**具体多少条我没法给数，因为这次没有运行分析器。**
- `unawaited_futures` 对我们特别有用：存盘、通知这类“发起了没等”的地方会被逐个点出来，逼着每处都表态是“故意不等”还是“忘了等”。

### 5.5 测试

| | dsh-Go | LopiCode |
|---|---|---|
| 测试文件 | app 1354 个 + 三个包 460 个 | 21 个，全部平铺在 `test/` 一层（只有一个在 `test/terminal/`） |
| 目录是否对应源码 | 一一对应 | 不对应，按“阶段”和“大主题”命名（`stage2_test.dart`、`screens_test.dart`、`agent_system_test.dart` 844 行） |
| 截图比对 | 1006 张基准图，自动比 | `docs/screenshots/` 有 186 张图，但我在 `test/` 里**没找到和基准图自动比对的测试**（没有 `matchesGoldenFile`）。也就是图是“给人看的”，界面悄悄变样时机器不会报警 |
| 公共测试入口 | 有（字体、默认开关统一复位） | 没有 `flutter_test_config.dart`；字体由各测试自己调 `loadRealFonts()`，找不到字体就跳过截图 |
| 架构测试 | 有 | 没有 |
| 原生单元测试 | 290 个 Kotlin 测试文件 | 没有（Kotlin 只有 124 行，暂时也不需要） |
| 假服务器 | 有 | 有（`test/support/fake_model_server.dart`、`runtime_fakes.dart`），这点做得不错 |

建议：新测试按源码目录放（`test/agent/`、`test/core/`、`test/ui/`…），旧的大文件不急着拆；挑 10–15 个关键页面（聊天、设置、用量弹层、额度）改成真正的截图比对；加一个公共入口统一装字体，缺字体直接算失败而不是跳过。

### 5.6 CI 门禁与守门脚本

| | dsh-Go | LopiCode |
|---|---|---|
| 自动门禁 | GitHub Actions，9 类检查 | **没有**。没有 `.github/`，仓库也没有远程，所有检查靠每次手动跑 |
| 守门脚本 | 十来个，各有测试 | `tool/` 下只有一个生成样例的脚本 |
| 锁文件强制 | 有 | 没有 |

建议：仓库还没推到远程，先不谈 GitHub Actions。现在就能做的是**一个本地一键检查脚本**（比如 `tool/check.sh`）：静态检查 → 全量测试 → 架构守门测试，三步任何一步不过就停，输出一行总结果。以后每次交付前跑它，交付说明里贴它的结果。等定了 GitHub 仓库，再把同一个脚本挂到 Actions 上。

### 5.7 文档与给 AI 的规则

| | dsh-Go | LopiCode |
|---|---|---|
| 架构总览 | 有，500 行，带“改什么先读哪里” | 没有；`README.md` 写了功能和现状，`docs/` 里有 `api-notes.md`、`linux-runtime.md` |
| 行为合同 | 105 篇 | 没有成文的；规则散在 README 和测试里 |
| AI 规则文件 | `AGENTS.md`（`CLAUDE.md` 指向它） | **仓库里没有** |

我们 README 里“哪些测过、哪些没在真机验证”的如实清单，其实和 dsh-Go 的要求是同一个精神，这点已经做到了。

建议：在 LopiCode 仓库根上加一份 `AGENTS.md`，把已经在执行、但只存在于对话里的规矩落成文字。至少包括：安全规则写在代码里不靠提示词；密钥不进日志不进普通设置；改完跑一键检查并贴结果；真机没验的要明写；测试时把临时目录指到工作区；发包只发 release arm64 瘦身包；参考 dsh-Go 只学做法不抄代码；新状态放哪里、谁是主人。

### 5.8 原生层

| | dsh-Go | LopiCode |
|---|---|---|
| 规模 | 356 个 Kotlin 文件 | 2 个：`MainActivity.kt`（67 行）、`RuntimeKeepAliveService.kt`（57 行） |
| 运行环境谁说了算 | Kotlin（状态机 + 代次），Dart 抄镜像 | **Dart**（`lib/runtime/linux_runtime.dart`），Kotlin 只提供五个小方法：原生库目录、剩余空间、开 / 关保活服务、设备信息 |
| 前台服务 | 自己管引擎进程，被系统回收后能恢复 | 只挂一个常驻通知保活，不管进程；被杀后不自动重启（`START_NOT_STICKY`） |
| 崩溃恢复 | 崩溃分类、安全模式、回退到上一个能用的版本 | 连续启动失败两次退回本机 shell |
| targetSdk | 故意压在 28 | 用 Flutter 默认值 |

评价：我们这种“逻辑都在 Dart、原生只做 Dart 做不了的事”对现在的规模是合适的，好测、好改。差别带来的风险有两点，都需要真机才能下结论：
- 应用被系统回收后，终端和正在跑的命令会一起没掉，回来不会自动恢复。如果以后要“后台长时间跑服务”，才值得学它把进程交给服务管。
- targetSdk：我们没有像它那样压到 28。霜霜的真机诊断里 PRoot 进 Ubuntu 跑命令是成功的，说明当前做法在那台手机（Android 16）上可行；别的机型、别的系统版本我不确定，记一笔，出问题时先查这里。

---

## 6. 状态管理迁到 Riverpod 的方案（本轮不做）

### 6.0 先说要不要迁

Riverpod 能解决的：谁关心谁更新（不再整页重画）、订阅自动取消、上游变了下游自动重算、测试里一行替换依赖。
它**不能**自动解决的：存盘安全、`ProjectSession` 太大、过期结果丢弃——这些要自己写，只是在 Riverpod 的框架里写起来更顺手、位置更固定。

所以顺序应该是：先做和库无关的加固（第 0 步），再迁。即使最后决定不迁，第 0 步也不白做。

版本：建议用和 dsh-Go 一样的 `flutter_riverpod ^3.4.3`，手写 Notifier，不引入代码生成。**我没有联网核对它和我们当前 Flutter / Dart 版本的兼容性**（我们要求 Dart ^3.14，dsh-Go 是 ^3.13.4，按理没问题），加依赖那一步要实际解析一次确认。

下面的工作量是我的估计，不是承诺；单位是“一个熟手专心做的工作日”。

### 第 0 步：不依赖 Riverpod 的加固（1.5–2 天）

- 做一个统一的“安全写文件”小工具：先写临时文件、再改名；同一个文件的写入排队；读失败时**把坏文件改名留底**并拒绝覆盖，而不是当空的。
- 动的文件：新增 `lib/core/safe_file.dart`；改 `lib/core/stores.dart`、`lib/project_session.dart`（`_saveRun`、`_saveIndex`、`_readMessages`、规则文件）、`lib/core/project_store.dart`、`lib/agent/automation.dart`、`lib/agent/team.dart`。
- 统一时钟入口：新增一个可在测试里替换的“现在几点”，先替换 `project_session.dart`、`automation.dart` 里的直接调用。
- `QuotaStore._refresh` 加代次检查。
- 风险：低。存盘路径是所有功能共用的，要补“写到一半断电”“文件是坏的”两类测试。
- 回退：每项单独一个提交，出问题退那一个。

### 第 1 步：接入 Riverpod，新旧并存（0.5–1 天）

- `pubspec.yaml` 加依赖；`lib/main.dart` / `lib/app.dart` 最外层包一层 `ProviderScope`；新增 `lib/state/app_providers.dart`，里面只有一个“应用服务”provider，启动时用已经建好的 `AppServices` 实例填进去。`AppScope` 原样保留。
- `test/support/harness.dart` 的 `appFor` 同步包一层。
- 这一步之后，旧页面照旧工作，新页面可以开始用 Riverpod。
- 风险：很低，不改任何行为。回退：删掉这层包装和依赖。

### 第 2 步：迁“叶子”状态——额度、主题、聊天开关、运行环境（2–3 天）

- 额度最适合当第一个：`lib/agent/quota.dart` 的 `QuotaStore` 改成“不可变状态 + Notifier”，按渠道分身；带上代次、同一时间只发一个、节流。界面 `lib/ui/settings_quota.dart`、`lib/ui/usage_ui.dart`、`lib/ui/chat_screen.dart` 里的低余额提示改成订阅它。
- 主题模式、开场建议开关、用量显示开关：做成几个小 Notifier，`lib/app.dart` 只订阅主题这一项——**顺手就去掉了“整个应用重建”**。
- `LinuxRuntime`、`RuntimeDiagnostics`：先不重写，用一个“把 ChangeNotifier 转成 provider”的薄适配包起来，`lib/runtime/runtime_screen.dart`、`lib/ui/terminal_tab.dart` 改成订阅适配后的 provider。
- 测试：`test/quota_usage_test.dart`、`test/usage_ui_test.dart`、`test/runtime_screens_test.dart` 要跟着改写法。
- 风险：中低。额度有“到 100% 拦截请求”的硬规则，迁的时候拦截逻辑必须留在代码路径上（`AppServices.createChatClient` 那个把关点不动），并保留现有测试。
- 回退：额度、主题、运行环境各自一个提交。

### 第 3 步：迁全局配置——渠道与模型、预设、技能、自动化（2–3 天）

- `lib/agent/model_config.dart`、`presets.dart`、`skills.dart`、`automation.dart` 各配一个 Notifier（放 `lib/state/`），页面 `lib/ui/settings_ai.dart`、`settings_agent.dart`、`automation_screen.dart`、`settings_screen.dart` 改成订阅，**删掉全部 `app.touch()`**；`lib/automation_scheduler.dart` 改成只更新自动化状态，不再每 30 秒通知全应用。
- 做完后 `AppServices` 不再需要继承 ChangeNotifier。
- 风险：中。这几个设置页里手写的表单状态多（`settings_ai.dart` 22 处 setState），容易漏掉某个“改完没刷新”的角落；靠 `test/agent_ui_test.dart`、`test/screens_test.dart` 和截图比对兜。
- 回退：一个页面一个提交。

### 第 4 步：拆 `ProjectSession`（5–8 天，风险最高）

把一个大对象拆成几个各管一摊的主人（都按“项目 id”分身，聊天再按“对话 id”分身）：

| 新主人 | 管什么 | 从 `project_session.dart` 的哪部分来 |
|---|---|---|
| 对话列表 | 有哪些对话、当前是哪段、标题、排序、新建删除 | `conversations`、`selectConversation`、`newConversation`、`deleteConversation`、`_saveIndex` |
| 单段对话 | 消息、条目、是否在生成、这一轮用量、排队与插话、停止 | `ConvRun`、`_execute`、`sendToAgent`、`_afterRun`、`queue` |
| 待处理的卡片 | 确认卡、提问卡、“本对话都允许” | `_approvals`、`_questions`、`_autoAllow` |
| 终端列表 | 开了哪些终端、当前哪个 | `terminals`、`addTerminal` 等 |
| 文件变动信号 | 文件改了通知文件树和预览 | `fileRevision` |
| 子代理与团队 | 派子代理、任务板 | `_spawn`、`boardOf` |

做法：
- 先把聊天条目改成不可变（每次变化产生新的条目列表），这样界面能只重画变了的那一条——这是解决“每吐一个字整页重画”的关键。
- `ProjectSession` 先保留成一个“门面”，内部转调新主人，对外方法名不变，页面一个一个迁：`lib/ui/chat_screen.dart` → `chat_panels.dart` → `project_shell.dart` → `files_tab.dart`、`preview_tab.dart`、`terminal_tab.dart` → `team_screen.dart`、`usage_ui.dart`。全迁完再删门面。
- 每个主人里统一用“代次 + 还活着吗”两道检查处理所有等待之后的写回。
- 正在生成的对话要手动保活，否则切到别的标签页回复会被掐断（dsh-Go 的聊天主人就是这么做的）。
- 自动化任务在“没打开的项目”里跑的那条路（现在是临时建一个不带界面的 `ProjectSession`）要改成临时建一个独立的容器来跑，跑完销毁。
- 测试：`test/session_system_test.dart`（777 行）、`test/agent_system_test.dart`（844 行）、`test/agent_ui_test.dart`、`test/shell_test.dart` 都要适配。**这些测试守着权限三档、子代理限制、自动化确认卡等安全规则，迁移期间一条都不能删，只能改写法。**
- 风险：高。子代理并发、排队插话、中断并发送这些时序逻辑集中在这里，最容易改出“偶尔出现”的毛病。建议迁之前先给这些时序补几条专门的测试，迁完对比。
- 回退：门面在的时候，任何一个页面都可以单独退回旧写法；每拆出一个主人一个提交。

### 第 5 步：收尾（1 天）

- 删 `AppScope` 和不再需要的 ChangeNotifier；`BuildJob`、`TerminalSession` 这类“本来就是一个页面内部用”的可以保留不动。
- 加一条架构测试：`lib/` 里继承 ChangeNotifier 的类必须在白名单里，只减不增。
- 更新 `README.md` 和 `AGENTS.md` 里“状态放哪里”的说明。

### 合计与总体风险

- 合计约 12–18 天（含第 0 步）；只算迁移本身约 10–14 天。
- 最大的风险不在 Riverpod 本身，而在第 4 步的时序逻辑。
- 整个过程新旧可以并存，任何一步做完应用都是完整能用的；不存在“必须一口气做完”的阶段。
- 如果想控制投入：做完第 0–2 步就已经拿到大部分好处（存盘安全、去掉全应用重建、有了一个标准写法的样板），第 4 步可以等聊天页真的开始卡、或者下次要往 `ProjectSession` 里加大功能时再做。

---

## 没读到和不确定的地方

- **没有运行任何东西**：两边的静态检查、测试都没跑。文中关于 LopiCode“开严格规则会报多少条”“测试数量”的说法，前者没有数，后者是数测试写法得出的近似（约 316 处测试定义；此前记录的通过数是 359，两个数口径不同）。
- dsh-Go 的 `state/chat_state.dart`（2361 行）、`state/connection_state.dart`（596 行）只按关键位置看了结构，没有逐行读；`balance_state.dart`、`usage_state.dart` 是全文读的。
- dsh-Go 的 Kotlin 层只看了目录、文件清单、清单文件、构建配置，以及 `RuntimeController`、`RuntimePlugin` 里和代次、通道方法有关的行；**PRoot 具体怎么拼启动命令（`DshProcess.kt`）、安装解压细节（`RuntimeInstaller.kt`）、前台服务内部（`DshService.kt`）没有细读**，第 1.2 节里对它们的描述来自它自己的架构文档和文件名。
- dsh-Go 的 `ci.yml`（510 行）读了任务列表和几个关键任务的步骤，没有逐行读；iOS、鸿蒙相关的工作流和代码没读。
- dsh-Go 的 `runtime/`（引擎补丁、桥）、`sdk/`、`market/`、`site/`、`services/` 没读，只引用了架构文档里的说明。
- dsh-Go 没有一份“测试总策略”文档；`docs/testing/` 是真机验证记录，`docs/maintenance/` 是行为合同。任务里说的 `docs/testing*`、`docs/maintenance*` 我是按这个实际情况写的。
- `clock` 库在 dsh-Go 里的实际用法：只查到一个文件引用它，状态层的时钟替换用的是别的三种办法。
- LopiCode 里 `addListener` 与 `removeListener` 数目不等（18 对 16），我没有逐对核实是否真有漏取消。
- LopiCode `docs/screenshots/` 那 186 张图是怎么生成的，我没在 `test/` 里找到对应代码（可能是我搜索的关键词没对上），所以“没有自动比对”这个判断只基于“没搜到比对用的写法”。
- flutter_riverpod 3.4.3 与 LopiCode 当前 Flutter / Dart 版本、以及 `material_ui` 这个包能否共存，没有实际解析依赖验证。
- LopiCode 的 targetSdk 取 Flutter 默认值，具体是多少我没查构建产物。

---

## 本轮已落地的加固

（2026-11-23，主任务填写。对应上面第 6 节的“第 0 步”，都不依赖 Riverpod。全应用迁 Riverpod **没有做**，等霜霜定。）

### 做了的

| 项 | 做法 | 学谁的 | 在哪 |
| --- | --- | --- | --- |
| 更严的静态检查 | 打开严格类型三项（strict-casts / strict-inference / strict-raw-types）和 30 多条规则；漏 await、漏取消订阅、空 catch、在 dynamic 上直接调用等升成 error 级。从 198 条问题修到零 | 思路自己定的——dsh-Go 的规则其实比较松（见 4.1），我们比它严 | `analysis_options.yaml`、`test/analysis_options.yaml` |
| 全局兜底 | 三道：界面框架报的、平台层报的、异步里没人接的，统一进本地日志 `logs/errors.log`（记之前抹掉 Key）；界面顶上出一条可点开的提示；“设置 › 关于 › 错误日志”可复制、可清空；某一块画不出来只换掉那一块；启动失败有“重试 / 复制错误信息”页 | 自己定的 | `lib/main.dart`、`lib/core/crash_log.dart`、`lib/ui/error_guard.dart` |
| 存盘安全 | 写：先写临时文件再改名，同一文件排队写。读：坏文件另存 `.bad-时间戳`（最多 3 份）后回退默认，绝不抛异常 | 原子写是 dsh-Go 的做法（见 2.x / 5.2 隐患 1）；备份坏文件是自己加的 | `lib/core/safe_file.dart`，设置、工作区清单、项目信息、对话索引、对话内容、自动化、团队、运行环境标记都换了 |
| 引用方向守门 | 一个测试扫所有 import：逻辑不依赖界面、下层不依赖上层、不许相对路径；例外要登记并写原因，例外失效也会报 | dsh-Go 的“谁能引用谁”守门测试（见 4.4），规则按我们的目录重写 | `test/architecture_test.dart` |
| 文件行数上限 | 新文件 600 行封顶；已超的 7 个登记在册，只许变短 | 自己定的 | 同上 |
| 其它守门 | 密钥库只许一个文件用；不许 print；存盘 JSON 不许绕过 safe_file | 自己定的 | 同上 |
| 一键检查 | 排版 → 静态检查 → 架构守门 → 全量测试 | dsh-Go 有类似的本地门禁脚本（见 4.4），内容自己写 | `tool/check.sh` |
| 给人和 AI 的规矩 | 目录职责、依赖方向、状态放哪、存盘、出错、网络、踩过的坑、新功能必须带什么 | dsh-Go 的 AGENTS.md 这个做法（见 4.6），内容全是我们自己的 | `AGENTS.md` |
| 排版统一 | 行宽定 200（工程一直是长行写法），全工程排一遍，以后由 check.sh 守着 | 自己定的 | `analysis_options.yaml` 的 formatter 节 |
| 网络超时 | 模型请求以前没有超时：现在等响应头 60 秒、流式中途 5 分钟没新内容算断；GitHub 请求 30 秒 / 下载 5 分钟 | 自己定的数 | `lib/agent/chat_client.dart`、`lib/agent/protocols.dart`、`lib/build/github_client.dart` |
| 流和订阅 | 进程输出、终端输出的监听补上出错处理；打包和装语言包的输出订阅用完取消 | 自己查的 | `command_runner.dart`、`linux_runtime.dart`、`terminal_session.dart`、`remote_exec.dart` |
| 就地修的状态隐患 | 5.2 隐患 3：自动化调度器每 30 秒无条件让全界面重建 → 只在真有变化时通知。文件页“文件被别处删了”时关标签可能拿到 -1 下标 → 先判断。预览页 WebView 的两个异步调用没人等 → 现在等了 | 自己查的 | `automation_scheduler.dart`、`files_tab.dart`、`preview_tab.dart` |

### 没做的（如实）

- **Riverpod 迁移**：没做，方案见第 6 节。
- **`discarded_futures` 规则**没开：试开有 57 处（多是按钮回调里直接调异步方法），要逐个判断。这些异常现在会被全局兜底接住并记日志。
- **golden 截图自动比对**没做：截图仍然是“生成出来人眼看”。
- **CI 门禁**没做：工程还没有远程仓库，`tool/check.sh` 只能在本地手动跑。
- **5.2 隐患 2（`ProjectSession` 太大）、隐患 4（过期结果统一丢弃，含额度查询的代次检查）、隐患 5（时间统一入口）**没动，只在 `AGENTS.md` 里立了规矩、在守门测试里把大文件登记成“只许变短”。
- 用户自己的项目文件（编辑器保存、Agent 写文件、导出、项目规则文件）仍是普通写入，没改成原子写：这些是用户内容不是应用存盘，且 Agent 写文件要保留原文件权限，留待下一轮。
- 真机上全局兜底的表现（尤其原生层崩溃——那是 Dart 接不到的）没验证。
