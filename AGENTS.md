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

## 状态怎么放（现状，没迁移到 Riverpod）

- 全应用共享的：`AppServices`（`ChangeNotifier`），用 `AppScope.of(context)` 取。改了以后调 `app.touch()` 或对应的 `notifyListeners()`。
- 一个工作区的：`ProjectSession`（`ChangeNotifier`），页面用 `addListener` / `ListenableBuilder` 订阅，`dispose` 里必须 `removeListener`。
- 只属于一个页面的：`State` 里的字段 + `setState`。
- 规矩：
  - `await` 之后要用 `context` 或 `setState`，先查 `mounted`（`use_build_context_synchronously` 是 error 级）。
  - `Future` 要么 `await`，要么明确写 `unawaited(...)` 并说明为什么不等（`unawaited_futures` 是 error 级）。
  - **防旧数据盖新数据**：一个异步请求回来时，先确认“我还是最新的那一次”再写状态
    （例子：`QuotaStore.refresh` 用同一个进行中的 Future；`ProjectSession.loadChat` 用 `_loading ??=`）。不要写会等待自己的 Future。
  - 订阅（`StreamSubscription`）、`Timer`、控制器要在 `dispose` 里取消 / 释放（`cancel_subscriptions`、`close_sinks` 是 error 级）。
- 要不要整体迁到 Riverpod：方案、工作量、风险写在研究文档里，**等霜霜定，没定之前不要自己迁**。

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
