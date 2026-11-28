import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'wait.dart';

export 'wait.dart';

const Size kPhone = Size(390, 844);

/// 平板尺寸（2026-11-28 平板适配）：竖屏、横屏，再加一个刚够“中”档的小平板 / 分屏。
const Size kTabletPortrait = Size(800, 1280);
const Size kTabletLandscape = Size(1280, 800);
const Size kTabletSmall = Size(600, 960);
const String kTestFont = 'LopiCJK';

/// 测试用的应用环境：临时目录里的设置和项目仓库，内存密钥。
class TestEnv {
  TestEnv._(this.tmp, this.services);
  final Directory tmp;
  final AppServices services;

  static Future<TestEnv> create({ChatClient Function()? chatClient, http.Client? quotaHttp}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_ui_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    await settings.load();
    final services = AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), chatClientFactory: chatClient, quotaHttp: quotaHttp);
    // 真实文件读写只能在 runAsync 里完成：先把渠道配置和自动化任务读好。
    await services.ready();
    // “没配好模型”的引导弹窗默认当作已经弹过，免得每个界面测试一进聊天页就被它挡住；
    // 专门测它的用例（test/model_setup_test.dart）自己把这个开关拨回去。
    services.modelSetupPrompted = true;
    return TestEnv._(tmp, services);
  }

  Future<void> dispose() async {
    services.dispose();
    await pendingWrites();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

/// 加载真实字体（中文、等宽、图标），否则截图里全是方块。
/// 找不到字体文件就返回 false（截图测试据此跳过）。
Future<bool> loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final regular = Platform.isWindows ? 'C:/Windows/Fonts/msyh.ttc' : '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
  final bold = File(Platform.isWindows ? 'C:/Windows/Fonts/msyhbd.ttc' : '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc');
  final mono = Platform.isWindows ? 'C:/Windows/Fonts/consola.ttf' : '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf';
  final fonts = <String, String>{kTestFont: regular, 'monospace': mono, if (flutterRoot != null) 'MaterialIcons': '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'};
  for (final entry in fonts.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) return false;
    final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }
  if (bold.existsSync()) {
    await (FontLoader(kTestFont)..addFont(Future.value(ByteData.sublistView(bold.readAsBytesSync())))).load();
  }
  return fonts.length == 3;
}

void usePhoneViewport(WidgetTester tester, {double pixelRatio = 1}) {
  tester.view.physicalSize = kPhone * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

/// 把测试窗口设成 [size]（逻辑像素）。测试中途再调一次＝拖窗口 / 转屏。
void useViewport(WidgetTester tester, Size size, {double pixelRatio = 1}) {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

final GlobalKey shotKey = GlobalKey();

Widget appFor(TestEnv env, Widget home, {ThemeMode mode = ThemeMode.light, String? font}) => RepaintBoundary(
  key: shotKey,
  child: LopiCodeApp(services: env.services, home: home, fontFamily: font, forceThemeMode: mode),
);

/// 不带应用外壳的小测试台（直接用 MaterialApp 的那几个）用：代码区域（看代码、原始 CSS）要读“代码字号”，
/// 这里给一份没有文件的空设置，读到的全是默认值。应用里永远有外壳给的那一份。
Widget bareScope(Widget child) =>
    ProviderScope(overrides: [settingsStoreProvider.overrideWithValue(SettingsStore(File(p.join(Directory.systemTemp.path, 'lopicode-bare-settings-does-not-exist.json'))))], child: child);

/// 界面里有真实的文件 / 进程 IO：让真实异步跑一会儿、推几帧，**再等排着队的存盘全部写完**。
///
/// 这里分两部分：
/// - 固定的那部分（[rounds] 轮、每轮真等 [ms] 毫秒再让测试时钟走 120 毫秒）只负责“让界面动画和一连串很短的异步接力走完”。
///   它是安全的，因为它后面的断言不该靠它等磁盘或后台任务：页面切换、面板滑出最长 300 毫秒，四轮测试时钟是 480 毫秒，够了；
///   测试时钟不受机器忙不忙影响。
/// - 存盘那部分是“等到条件成立”：所有经 `safe_file.dart` 排队的写入（设置、项目、对话、低代码与后端文档…）都落盘了才返回，
///   机器再忙也不会读到写了一半的文件。最多等 [kWaitLimit]，到了就报出来。
///
/// 调用方要等的是**别的事**（下载完、进程起来、扫描完、某行字出现）：不要靠加轮数，用 [waitUntil]。
Future<void> settle(WidgetTester tester, {int rounds = 4, int ms = 60}) async {
  // 真实文件读写的每一步（建目录、写临时文件、改名…）都要“真等一下 + 让测试时钟走一下”才能接着往下走。
  // 存盘改成原子写以后步数变多了，所以每一轮里再细分成几小步，免得靠调轮数去凑。
  const hops = 6;
  final each = Duration(milliseconds: (ms / hops).ceil());
  for (var i = 0; i < rounds; i++) {
    for (var k = 0; k < hops; k++) {
      await tester.runAsync(() => Future<void>.delayed(each));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 120));
  }
  await waitWritesDone(tester);
}

/// 等所有排着队的存盘写完（界面测试用）。写入是在根 Zone 里跑的，所以要放进 runAsync 里等；写完后推两帧，让“写完了”的回调跑到界面上。
Future<void> waitWritesDone(WidgetTester tester, {Duration limit = kWaitLimit}) async {
  final ok = await tester.runAsync(() => pendingWrites().then((_) => true).timeout(limit, onTimeout: () => false));
  if (ok == false) fail('等了 ${limit.inSeconds} 秒，还有存盘没写完');
  await tester.pump();
  await tester.pump();
}

/// 界面测试里“等到条件成立”：每一小步真等一下（让文件、进程、网络往前走）再让测试时钟走一下（让界面跟上），
/// 条件成立就返回；到了上限（真实时间）就失败，并报出等的是什么（[what]）。
///
/// [cond] 里可以看界面（`find.text(...).evaluate().isNotEmpty`）、看状态对象、看磁盘（`File(...).existsSync()`）。
/// [pump] 是每一步让测试时钟走多少：界面上有“停手多久才做”的计时器时调大一点。
Future<void> waitUntil(WidgetTester tester, bool Function() cond, String what, {Duration limit = kWaitLimit, Duration pump = const Duration(milliseconds: 20)}) async {
  final watch = Stopwatch()..start();
  while (!cond()) {
    if (watch.elapsed > limit) fail('等了 ${limit.inSeconds} 秒也没等到：$what');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(pump);
  }
  await tester.pump();
}

/// 低代码搭建页“停手 0.4 秒才存盘”：把这段时间走完，再等真实的写盘做完（顶栏小字不再是“正在保存…”）才返回。
/// 不靠“等固定的一小会儿”：机器忙的时候写盘可能很慢，读早了会读到写了一半的文件。最多等 10 秒（真实时间）。
Future<void> waitLowcodeSaved(WidgetTester tester) async {
  // 这 500 毫秒是测试时钟（不是真实时间）：只为走完“停手 0.4 秒才存盘”那个计时器，机器忙不忙都一样。
  await tester.pump(const Duration(milliseconds: 500));
  await waitUntil(tester, () => find.textContaining('正在保存', skipOffstage: false).evaluate().isEmpty, '低代码页面存盘写完（顶栏不再是“正在保存…”）');
  await waitWritesDone(tester);
}

/// 脚本化的模型客户端（不走网络）。
class ScriptedChatClient implements ChatClient {
  ScriptedChatClient(this.turns);
  final List<List<ChatDelta>> turns;
  int calls = 0;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    final turn = calls < turns.length ? turns[calls] : [ChatDelta(content: '完成。', finishReason: 'stop')];
    calls++;
    for (final d in turn) {
      yield d;
    }
  }
}

ChatDelta say(String text) => ChatDelta(content: text);
ChatDelta call(int index, String name, String args) => ChatDelta(
  toolCalls: [ToolCallDelta(index: index, id: 'call_${name}_$index', name: name, arguments: args)],
);
