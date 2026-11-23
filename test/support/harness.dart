import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

const Size kPhone = Size(390, 844);
const String kTestFont = 'LopiCJK';

/// 测试用的应用环境：临时目录里的设置和项目仓库，内存密钥。
class TestEnv {
  TestEnv._(this.tmp, this.services);
  final Directory tmp;
  final AppServices services;

  static Future<TestEnv> create({ChatClient Function()? chatClient}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_ui_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    await settings.load();
    final services = AppServices(
      settings: settings,
      secrets: MemorySecretStore(),
      projects: ProjectStore(p.join(tmp.path, 'projects')),
      chatClientFactory: chatClient,
    );
    // 真实文件读写只能在 runAsync 里完成：先把渠道配置和自动化任务读好。
    await services.ready();
    return TestEnv._(tmp, services);
  }

  void dispose() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

/// 加载真实字体（中文、等宽、图标），否则截图里全是方块。
/// 找不到字体文件就返回 false（截图测试据此跳过）。
Future<bool> loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final fonts = <String, String>{
    kTestFont: '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    'monospace': '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf',
    if (flutterRoot != null) 'MaterialIcons': '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  };
  for (final entry in fonts.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) return false;
    final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }
  // 粗体：同一个字体族再加一份 Bold
  final bold = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc');
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

final GlobalKey shotKey = GlobalKey();

Widget appFor(TestEnv env, Widget home, {ThemeMode mode = ThemeMode.light, String? font}) => RepaintBoundary(
  key: shotKey,
  child: LopiCodeApp(services: env.services, home: home, fontFamily: font, forceThemeMode: mode),
);

/// 界面里有真实的文件 / 进程 IO：让真实异步跑一会儿，再推几帧。
Future<void> settle(WidgetTester tester, {int rounds = 4, int ms = 60}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(const Duration(milliseconds: 120));
  }
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
ChatDelta call(int index, String name, String args) =>
    ChatDelta(toolCalls: [ToolCallDelta(index: index, id: 'call_${name}_$index', name: name, arguments: args)]);
