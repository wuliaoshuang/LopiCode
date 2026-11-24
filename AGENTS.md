# LopiCode 工程规矩

给以后改这个工程的人和 AI 助手看的。先读这一页再动手。这里写的规矩大多有测试或检查守着（`tool/check.sh`），
改了规矩要同时改守它的测试。

来历：2026-11-23 读了 dsh-Go 的工程做法后定的，对照过程见 [docs/dsh-go-architecture-study.md](docs/dsh-go-architecture-study.md)。
dsh-Go 是 AGPL：只学做法，**不许复制它的代码、文案、素材**。

## 提交前

```
tool/check.sh          # 排版 + 静态检查 + 架构守门 + 全量测试，四步都过才提交
tool/check.sh --quick  # 改到一半想快速看看：不跑全量测试
tool/check.sh --fix    # 先自动排版
```

- `flutter analyze` 必须**零问题**。规则在 `analysis_options.yaml`；要放过某一行用 `// ignore: 规则名` 并写原因，不要整条关掉。
- 跑全量测试要把 `TMPDIR` 指到工程里（脚本已经做了）：有的机器 `/tmp` 只有 512MB，会写满。
- 提交只在本地：`git -c user.name=LopiCode -c user.email=lopicode@local commit`。推不推、推到哪由霜霜定。
- 发给霜霜的安装包一律是 `flutter build apk --release --target-platform android-arm64`（瘦身包），不发 debug 包。

## 目录各管什么

| 目录 | 管什么 | 可以依赖 |
| --- | --- | --- |
| `lib/core/` | 最底层：存盘（`stores.dart`、`safe_file.dart`）、项目目录、路径守卫、错误日志（`crash_log.dart`）、第三方清单 | 只有 `core` |
| `lib/theme/` | 颜色、间距、字号这些设计 tokens 和主题 | 只有 `theme` |
| `lib/agent/` | Agent：各协议的客户端、工具、模型与渠道配置、服务商预设、额度与用量、自动化、团队、技能、联网搜索 | `core`、`agent` |
| `lib/preview/` | 本机预览服务器 | `core` |
| `lib/format/` | 代码格式化器（JSON / CSS / JS·JSX / HTML / Vue），纯 Dart，排完和原文对不上就原样返回 | 只依赖自己 |
| `lib/terminal/` | 终端会话与后端接口、原生伪终端的封装 | `core`、`terminal` |
| `lib/runtime/` | Ubuntu 运行环境：下载、解压、PRoot 启动、诊断 | 下面各层 |
| `lib/ssh/`、`lib/build/`、`lib/lowcode/` | SSH、打包、低代码（各自的逻辑 + 自己的 `*_screen.dart`） | 下面各层 |
| `lib/app_services.dart`、`lib/project_session.dart`、`lib/automation_scheduler.dart` | 把上面各块拼起来的“应用状态” | 逻辑各层，**不依赖界面** |
| `lib/ui/` | 界面：页面、面板、通用控件 | 什么都可以 |
| `lib/main.dart`、`lib/app.dart` | 入口和应用外壳 | 什么都可以 |

## 依赖方向（`test/architecture_test.dart` 守着）

1. **逻辑不依赖界面。** 不是界面文件的（不在 `lib/ui/`、`lib/theme/`，文件名也不是 `*_screen.dart` / `*_tab.dart` / `*_sheet.dart` 之类），
   不许 import 界面库（`material_ui`、`flutter/widgets` 等）、`lib/ui/`、`lib/theme/` 或别的界面文件。
   `flutter/foundation.dart`（`ChangeNotifier`、`ValueNotifier`）和 `flutter/services.dart` 可以。
2. **下层不依赖上层。** 见上表“可以依赖”。
3. 例外都登记在 `test/architecture_test.dart` 开头的清单里，每条写了原因；例外不成立了测试也会失败，提醒删掉。**不要为了让测试过而随手加例外。**
4. import 一律写 `package:lopicode/…`，不写相对路径（守门测试靠它判断方向）。

## 文件别太长

新文件不超过 600 行。已经超了的（`builder_screen.dart`、`project_session.dart`、`chat_screen.dart` 等）记在守门测试的清单里，**只许变短不许变长**：
往这些文件里加新功能之前，先把新功能写到新文件里。

## 状态怎么放（Riverpod；2026-11-23 霜霜批准迁移，2026-11-24 三轮迁完）

用的是 `flutter_riverpod` / `riverpod` 3.5。**已经迁完的**和**还没迁的**分开写，别搞混。

### 已经迁完的（新代码一律照这个写）

- **全应用只有一个状态容器**：`AppServices.container`。应用最外层用 `UncontrolledProviderScope` 把它交给界面；
  逻辑层（不是界面的代码）要读状态也从 `app.container` 读。别处不许再 `ProviderContainer(...)`（测试除外）。
- **provider 只定义在 `lib/state/`**，那里只 import `package:riverpod/riverpod.dart`（不带界面）。
  `flutter_riverpod`（`ConsumerWidget`、`ref.watch` 这些界面部分）只许界面文件用。守门测试会拦。
- **界面怎么用**：
  - 要“跟着变”的：`ConsumerWidget` / `ConsumerStatefulWidget` / `Consumer` 里 `ref.watch(某个 provider)`；
    小块重画可以用 `Consumer`，或 `lib/ui/app_ref.dart` 里的 `QuotaBuilder`。只订阅自己关心的那一个，别订阅一大片。
  - 只是取个“干活的对象”（存设置、调接口）：`appOf(context)`，它不订阅任何东西。
  - 界面不直接改底层对象的字段；要改就调 Notifier 或存储对象的方法。
  - **不许在搭界面的过程中改状态**（`build`、`initState`、`didChangeDependencies` 里直接改会报错）：放到按钮回调里，
    或者像 `QuotaNotifier.refresh` 那样用 `Future.microtask` 推后一拍。
- **现在有哪些**（都在 `lib/state/`）：
  - `app_providers.dart`：`appServicesProvider`、`settingRevProvider(键)`（某个设置键变了）、`settingsAnyRevProvider`（只给设置总览页）。
    `SettingsStore.set` 写完会自己通知，**不用也不许再手动“通知全应用”**（`AppScope`、`app.touch()` 已删，守门测试不让回来）。
  - `ui_prefs.dart`：`themeModeProvider`（外观）、`chatPrefsProvider`（开场建议、显示用量）。
  - `quota_state.dart`：`quotaProvider`——额度上限和余额。这是**标准样板**：状态是不可变对象，只有 `QuotaNotifier` 能改。
  - `presets_state.dart`：`presetsProvider`——Agent 预设与个人偏好（完整版：不可变快照 + `PresetsNotifier`）。
  - `skills_state.dart`：`skillsProvider(工作区目录)`——技能清单（完整版；异步扫描带代次，没人看就释放）。
  - `models_state.dart`：`modelsProvider`——渠道与模型、新对话默认用哪个（完整版）。`Channel` / `ModelSpec` 不可变，
    改就用 `copyWith` 造一份新的交给 `ModelsNotifier.upsert`；设置页的表单只改自己手里的草稿，不改拿到的对象。
  - `automations_state.dart`：`automationsProvider`——自动化任务清单、运行历史、哪些正在跑（完整版）。`Automation` 不可变；
    调度器要推进时间、记结果都走 `AutomationStore` 的方法（按 id），不许直接改字段。
  - `config_providers.dart`：Agent 设置、技能文件、联网搜索、SSH 主机的“变了”计数（这几样本来就只是设置键或一个开关，计数就够）。
  - `runtime_state.dart`：`runtimeProvider`、`runtimeDiagnosticsProvider`——运行环境和一键诊断（完整版）。
    干活的还是 `LinuxRuntime` / `RuntimeDiagnostics`（管进程和文件，终端和 Agent 的命令直接用它们），但它们不再是 `ChangeNotifier`：
    每次有变化拍一张不可变快照（`lib/runtime/runtime_snapshot.dart` 的 `RuntimeView` / `DiagnosticsView`）；界面只读快照，要做什么调 Notifier 的方法。
  - `runtime_extras.dart`：`runtimeDiskUsageProvider`（环境占多大）、`runtimePackVersionsProvider`（已装语言的版本号）——“运行环境”页现算的只读信息，
    只读文件、不起进程；算不出来就是 null / 空，界面不显示，不编数字。
  - `team_state.dart`：`teamProvider((工作区, 主对话 id))`——团队任务板（完整版）。`TeamTask` / `TeamMember` 不可变，
    `TeamBoard` 每次变化换一份 `TeamView`；校验不过就抛错、什么都不改。
  - 一个工作区的状态（都按 `ProjectSession` 分身，工作区关掉并收完尾后释放）：
    - `workspace_files.dart`：`filesRevProvider`——工作区文件变了。
    - `workspace_terminals.dart`：`terminalsProvider`——开了哪些终端、当前哪个。
    - `workspace_preview.dart`：`previewProvider`——预览服务器起没起来、日志。
    - `backend_run.dart`：`backendRunProvider`——后端点“运行”以后替她配工具的那一段（等环境 / 核对 / 等她点头 / 正在装 / 没装成）。
      带代次：取消、工作区关掉以后回来的结果一律丢掉，不启动、不写状态。同一时间只受理一次。
    - `workspace_conversations.dart`：`conversationsProvider`——对话目录（`Conversation` 不可变）、当前是哪段、项目规则。
    - `workspace_chat.dart`：`chatRunProvider((工作区, 对话 id))`——一段对话的条目（`ChatItem` 全部不可变）、忙不忙、这一轮用量；
      `activeChatProvider`——当前那段；`pendingCardsProvider`——确认卡 / 提问卡 / “本对话都允许”；`sendQueueProvider`——排队和插话的消息、交还输入框的草稿。
  - `ProjectSession`（`lib/project_session.dart`）现在**不是状态对象**了：它是“一个工作区的 Agent 引擎 + 对外方法的门面”，
    自己不通知任何人，状态全在上面这些 provider 里。界面要跟着变就订阅 provider，别想着监听它。
    它现在只是薄组装层（约 430 行，已从超长清单拿掉）；活都在 `lib/session/` 里：`session_core.dart`（共用的底子）、`turn_runner.dart`（跑一轮）、
    `toolbox_builder.dart`（组装工具）、`subagents.dart`（派子代理）、`send_flow.dart`（发送 / 排队 / 插话 / 停止）、`chat_export.dart`（导出）、`attachments.dart`（附件）。
    新功能加到对应的小文件里，别往门面里塞。
- **不等写完盘的设置**：按钮回调、后台顺手记一笔这类没法 `await` 的地方用 `SettingsStore.setLater`（内存立刻生效，写盘失败只记错误日志）。
  不要写 `unawaited(settings.set(...))`——写盘失败会变成没人接的异常。
- **留在后台的页面**（底部导航的五个页面用 `IndexedStack` 保活）不会因为“从别的页面回来”而重建：
  它显示的东西只要能在别处被改，就必须订阅对应的 provider。排查清单和测试见 `test/settings_refresh_test.dart`。
- **防旧数据盖新数据**（照 `QuotaNotifier` 写）：
  - **代次**：每个渠道一个代次号；发请求时记下，回来时号变了（比如换了 Key）就整个丢掉，不写状态。
  - **销毁后不写**：`await` 之后先查 `ref.mounted`；逻辑层查 `app.disposed`。销毁后还可能被读的，留一份本地快照（`QuotaNotifier._snap`）。
  - 同一件事只发一个请求：进行中的 `Future` 存起来复用，不要写会等待自己的 Future。
  - 换 Key 后：旧请求作废、旧余额不显示、“上次余额”清掉，新 Key 第一次查到的余额当新起点（不和旧账号相减）。
- 每个新 Notifier 都要在 `test/` 里有单元测试（参考 `test/state_providers_test.dart`、`test/quota_usage_test.dart`）：
  用 `ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services), …])` 建一个独立容器。

### 留着的旧写法（只许减少，不许照着新增）

- `PushDrawerController`：侧边栏开合动画的控制器，纯界面，留着。
- `TerminalSession`、`BuildJob` 是页面 / 列表自己建自己丢的“干活对象”，只留一个 `onChanged` 回调位，不是全局状态。
- 清单在 `test/architecture_test.dart` 的 `_legacyNotifiers`：迁走一个删一个；**不许再新增 `ChangeNotifier` / 全局 `ValueNotifier` 状态**。

### 一直有效的规矩

- 只属于一个页面的：`State` 里的字段 + `setState`。
- `await` 之后要用 `context` 或 `setState`，先查 `mounted`（`use_build_context_synchronously` 是 error 级）。
- `Future` 要么 `await`，要么明确写 `unawaited(...)` 并说明为什么不等（`unawaited_futures` 是 error 级）。
- 订阅（`StreamSubscription`）、`Timer`、控制器要在 `dispose` 里取消 / 释放（`cancel_subscriptions`、`close_sinks` 是 error 级）。
- 测试收尾删临时目录前，如果被测代码有“不等它写完”的存盘，先 `await pendingWrites()`（`lib/core/safe_file.dart`）。

## 存盘（`lib/core/safe_file.dart`）

- 写 JSON 存盘文件一律用 `writeJsonAtomic`（先写临时文件再改名），不许直接 `writeAsString(jsonEncode(...))`（守门测试会拦）。
- 读一律用 `readJsonFile`：文件坏了它会把原件另存成 `名字.bad-时间戳`（最多留 3 份）、记一笔日志、返回 null，调用方回退默认值。
  **读存盘文件不许抛异常让应用起不来。**
- 从 JSON 里取字段先判断类型（`x is String ? x : 默认`），不要 `as String`：旧版本 / 坏数据的类型不对时，`as` 抛的是 `TypeError`，
  `on Exception` 接不住。
- 加新的存盘文件要在 `test/safe_file_test.dart` 里补“读到坏内容不崩”的用例。

## 出错了怎么办

- 能预料的失败（网络、接口报错、文件不存在）：就地 `try/catch`，换成人话告诉用户，写清**真正的原因**，不要只说“请重试”。
- 没预料到的：`lib/main.dart` 装了三道兜底（`FlutterError.onError`、`PlatformDispatcher.onError`、`runZonedGuarded`），
  统一进 `CrashLog`（`lib/core/crash_log.dart`）→ 本地 `logs/errors.log` + 界面顶上一条可点开的提示 + “设置 › 关于 › 错误日志”可复制。
- `catch` 里不许是空的：至少写一句注释说明为什么可以不管（`empty_catches` 是 error 级）。
- **日志和报错里不许出现 Key / Token / 密码。** `CrashLog` 记之前会用 `redactSecrets` 抹一遍，但不要依赖它：
  报错时只带主机名和错误类型，不带请求头、不带完整网址参数。密钥只走 `SecretStore`（`lib/core/stores.dart`），不进设置文件。
- 不直接 `print` / `debugPrint`（守门测试会拦）。

## 网络请求

- **每个请求都要有超时。** 模型接口用 `sendChatRequest`（等响应头 60 秒）和 `guardChatStream`（流式中途 5 分钟没新内容算断）；
  GitHub 用 `kGitHubTimeout`；其他地方用 `.timeout(...)`。超时要报成人话。
- 接口地址、参数、返回字段先对着官方文档核对，记进 `docs/api-notes.md`（来源网址 + 核对日期 + 状态）。核对不了的写明“未核对”，不凭记忆写。
- 服务商预设（`lib/agent/provider_presets.dart`）：地址没对着官方文档核对过的不许加。

## 踩过的坑（别再踩）

- **原生流先 cast 再解码。** `flutter_pty`、`dartssh2` 给的是 `Stream<Uint8List>`，直接 `.transform(utf8.decoder)` 运行时报类型错误，
  而且宿主机测试用的假终端抓不到。一律 `stream.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true))`。
- 流的 `listen` 要带 `onError`（至少 `onError: (_) {}` 并说明），否则对端断开时是一个没人接的异常。
- `xterm` 4.0.0 的输入有坑（预编辑期间不写入终端等），输入由 `lib/terminal/terminal_input.dart` 接管，别绕过它。
- 放在 `MaterialApp.builder` 里的控件在 Navigator **外面**，没有 Overlay：不能用带 tooltip 的控件（`IconButton(tooltip:)`）、不能弹对话框。
  （2026-11-23 错误提示条就是这样把自己弄崩的，测试抓到了。）
- 界面测试里真实的文件读写要放进 `tester.runAsync`；自定义顶栏没有系统返回按钮，测试里用 `tester.binding.handlePopRoute()`，不要用 `pageBack()`。
- `ListView` 里靠后的项用 `scrollUntilVisible` 找到后，点之前再 `ensureVisible` 一次（它可能只是进了缓存区，还没真正露出来）。
- **顶栏全应用只有一套**（`lib/ui/top_bar.dart` 的 `PageBar`，外壳里用 `ShellAppBar`）：高 64、悬浮、没有底色。新页面的 Scaffold 一律
  `extendBodyBehindAppBar: true`，能滚的内容顶部留 `PageBar.insetOf(context)`，不能滚的正文包一层 `BelowBar`。不许用系统 `AppBar`、
  不许自己另画顶栏（`test/topbar_unified_test.dart` 守着）。Scaffold 正文里的 `viewPadding.top` 是 0（被 Scaffold 拿掉了），别自己拿它算状态栏。
- 手机上 `localhost` 指手机自己。
- 第三方组件（PRoot 等二进制、图标）不许改内容；来源、版本、校验值、许可证记在 `third_party/` 和 `lib/core/third_party.dart`，有测试核对校验值。

## 新功能必须带什么

1. **测试**：逻辑有单元测试；界面有界面测试（手机尺寸 390×844，用 `test/support/harness.dart`）；涉及存盘有“坏文件不崩”的用例；
   涉及网络有“超时 / 连不上 / 接口报错”的用例。
2. **截图**：新页面浅色、深色各一张放 `docs/screenshots/`（`LOPI_SHOTS=1 flutter test …` 生成），自己逐张看过。
3. **界面文件开头的“设计约束”注释**：这个页面一行放什么、主操作是什么。排法守“一行只做一件事”，挤不下的收进下拉 / 面板。
4. **如实的说明**：哪些验证过、哪些没有（尤其是真机）；哪些是照参考做的、哪些是自己定的。
5. 测试中发现潜在 bug：**立刻停下当场查清**，不要等跑完；汇报里单列。

## 不许做的

- 不推送、不部署、不花钱、不替霜霜注册账号——除非她明确说了。
- 不把 Key 写进代码、文档、日志、测试快照。
- 不为了让检查通过而删测试、加例外、加 `// ignore` 不写原因。
