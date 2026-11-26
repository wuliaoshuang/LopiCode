// 聊天正文渲染 Markdown / HTML 的界面测试（390×844，浅 / 深色）。
//   LOPI_SHOTS=1 flutter test test/md_ui_test.dart   # 同时写截图（LOPI_SHOT_DIR 指定目录，默认 docs/screenshots）
// 网页视图是平台控件，这里用 HtmlPreview.debugViewBuilder 顶替：只能证明“交给视图的是什么、视图报回来的东西怎么处理”，
// 证明不了真 WebView 的隔离。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/markdown/html_preview_doc.dart';
import 'package:lopicode/markdown/md_document.dart';
import 'package:lopicode/markdown/md_image_loader.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/html_preview.dart';
import 'package:lopicode/ui/message_text.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/md_samples.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? 'docs/screenshots';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  if (!writeShots || !fontsLoaded) return;
  final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// 聊天页的样子：上面一条我的消息（气泡），下面 Agent 的正文（通栏）。
class _Stage extends StatelessWidget {
  const _Stage({this.mine, this.agent, this.streaming = false, this.muted});
  final String? mine;
  final String? agent;
  final bool streaming;
  final String? muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('stage-list'),
          padding: const EdgeInsets.all(Space.x4),
          children: [
            if (mine != null)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  margin: const EdgeInsets.only(bottom: Space.x4),
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.lg)),
                  child: MessageText(mine!, mine: true),
                ),
              ),
            if (muted != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x4),
                child: MessageText(muted!, muted: true),
              ),
            if (agent != null) MessageText(agent!, streaming: streaming),
          ],
        ),
      ),
    );
  }
}

void main() {
  late TestEnv env;
  final copied = <String>[];
  final requests = <HtmlPreviewRequest>[];

  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<void> boot(WidgetTester tester, Widget home, {ThemeMode mode = ThemeMode.light}) async {
    usePhoneViewport(tester);
    copied.clear();
    requests.clear();
    mdDebugClearCache();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    HtmlPreview.debugViewBuilder = (request) {
      requests.add(request);
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text('（假的网页视图）', style: TextStyle(color: Colors.black)),
        ),
      );
    };
    addTearDown(() => HtmlPreview.debugViewBuilder = null);
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, home, mode: mode, font: fontsLoaded ? kTestFont : null));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder rich(String s) => find.textContaining(s, findRichText: true);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('全部语法的一条长消息 · ${mode.name}', (tester) async {
      await boot(
        tester,
        const _Stage(mine: '帮我看看 `main.dart`，**尽快**\n- 第一\n- 第二\n\n```sh\nflutter run\n```', agent: kMdEverything),
        mode: mode,
      );
      expect(tester.takeException(), isNull);
      // 标记符号不再露出来
      expect(rich('**粗体**'), findsNothing);
      expect(rich('# 一级标题'), findsNothing);
      expect(rich('一级标题'), findsOneWidget);
      expect(rich('粗体'), findsWidgets);
      // 我的气泡里也渲染了
      expect(rich('**尽快**'), findsNothing);
      expect(find.byKey(const Key('md-code-block')), findsWidgets);
      await shot(tester, 'md-all-top-${mode.name}');

      final list = find.byKey(const Key('stage-list'));
      await tester.drag(list, const Offset(0, -520));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await shot(tester, 'md-all-mid-${mode.name}');
      await tester.drag(list, const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await shot(tester, 'md-all-end-${mode.name}');
      // 脚本标签当文字显示，不执行
      await tester.dragUntilVisible(rich('alert(1)'), list, const Offset(0, -200));
      expect(rich('<script>'), findsOneWidget);
    });
  }

  testWidgets('表格可以横着滚，不撑破屏幕；代码块长行横着滚', (tester) async {
    await boot(
      tester,
      const _Stage(
        agent: '| 名称 | 说明 | 数量 | 备注 | 再一列 |\n|---|---|---|---|---|\n| 苹果 | 一种很长很长很长很长很长很长很长很长的说明 | 12 | 没有 | 还是没有 |\n\n```js\nconst veryLongLine = "0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789";\n```',
      ),
    );
    expect(tester.takeException(), isNull);
    final scroll = find.byKey(const Key('md-table-scroll'));
    expect(scroll, findsOneWidget);
    expect(tester.getSize(scroll).width, lessThanOrEqualTo(390));
    final before = tester.getTopLeft(rich('苹果').first).dx;
    await tester.drag(scroll, const Offset(-120, 0));
    await tester.pump();
    expect(tester.getTopLeft(rich('苹果').first).dx, lessThan(before));
    expect(tester.getSize(find.byKey(const Key('md-code-block'))).width, lessThanOrEqualTo(390));
    expect(tester.getSize(find.byKey(const Key('md-code-text'))).width, greaterThan(390), reason: '长行不折行，靠横向滚动');
  });

  testWidgets('代码块：语言标签、高亮、复制拿原文、超过 30 行先折着', (tester) async {
    final long = List.generate(45, (i) => 'line$i();').join('\n');
    await boot(tester, _Stage(agent: '```dart\nvoid main() {\n\tprint("hi");\n}\n```\n\n```\n$long\n```'));
    expect(tester.takeException(), isNull);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text('代码'), findsOneWidget, reason: '没写语言的显示“代码”');
    // 高亮：关键字和字符串颜色不一样
    final text = tester.widget<Text>(find.byKey(const Key('md-code-text')).first);
    final colors = <Color?>{};
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) colors.add(span.style?.color);
      return true;
    });
    expect(colors.length, greaterThan(1), reason: '上了色');
    await tester.tap(find.byKey(const Key('md-code-copy')).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied.single, 'void main() {\n\tprint("hi");\n}', reason: '复制的是原文（制表符还在）');
    // 折叠
    expect(rich('line29();'), findsOneWidget);
    expect(rich('line30();'), findsNothing);
    final expand = find.byKey(const Key('md-code-expand'));
    await tester.ensureVisible(expand);
    await tester.pump();
    expect(find.text('展开全部（45 行）'), findsOneWidget);
    await tester.tap(expand);
    await tester.pump(const Duration(milliseconds: 300));
    expect(rich('line44();'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('点链接：先弹出完整网址，只有“复制链接”，不会自己打开', (tester) async {
    await boot(tester, const _Stage(agent: '看[这里](https://example.com/a/b?token=1#frag)吧'));
    await tester.tapOnText(find.textRange.ofSubstring('这里'));
    await tester.pumpAndSettle();
    expect(find.text('网页链接'), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('md-link-url'))).data, 'https://example.com/a/b?token=1#frag');
    expect(find.text('打开'), findsNothing);
    expect(copied, isEmpty);
    await tester.tap(find.byKey(const Key('md-link-copy')));
    await tester.pumpAndSettle();
    expect(copied.single, 'https://example.com/a/b?token=1#frag');
    expect(find.byKey(const Key('md-link-url')), findsNothing);
    // 取消：什么都不做
    copied.clear();
    await tester.tapOnText(find.textRange.ofSubstring('这里'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('md-link-cancel')));
    await tester.pumpAndSettle();
    expect(copied, isEmpty);
  });

  testWidgets('图片：网络图片点一下才去下；http 的不加载；data: 直接显示；下载失败能重试', (tester) async {
    var hits = 0;
    var fail = true;
    final old = MdImageLoader.instance;
    addTearDown(() => MdImageLoader.instance = old);
    MdImageLoader.instance = MdImageLoader(
      clientFactory: () => MockClient((req) async {
        hits++;
        if (fail) return http.Response('', 500);
        return http.Response.bytes(Uri.parse('data:image/png;base64,$kTinyPng').data!.contentAsBytes(), 200, headers: {'content-type': 'image/png'});
      }),
    );
    await boot(tester, const _Stage(agent: '![猫](https://img.example/cat.png)\n\n![旧图](http://img.example/old.png)\n\n![点](data:image/png;base64,$kTinyPng)\n\n![外面](../../etc/secret.png)'));
    expect(tester.takeException(), isNull);
    expect(hits, 0, reason: '没点之前不联网');
    expect(find.text('猫 · 点一下加载（img.example）'), findsOneWidget);
    expect(rich('没加密的 http'), findsOneWidget);
    expect(find.byKey(const Key('md-image')), findsOneWidget, reason: 'data: 图片直接显示');
    expect(rich('没有打开工作区'), findsOneWidget);

    await tester.tap(find.byKey(const Key('md-image-load')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(hits, 1);
    expect(rich('图片没加载出来'), findsOneWidget);
    expect(rich('500'), findsOneWidget);
    fail = false;
    await tester.tap(find.byKey(const Key('md-image-retry')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(hits, 2);
    expect(find.byKey(const Key('md-image')), findsNWidgets(2));
  });

  testWidgets('内联 HTML：排版标签生效；脚本、事件属性、未知标签不执行，当文字显示；details 能展开', (tester) async {
    await boot(
      tester,
      const _Stage(
        agent: '<b>加粗的</b>和<u>下划线</u><br>第二行\n\n<span onclick="alert(1)" style="position:fixed">带事件的</span>\n\n<script>alert("x")</script>\n\n<iframe src="https://evil.example"></iframe>\n\n<blink>不认识的</blink>\n\n<details><summary>细节</summary>\n\n里面的内容\n\n</details>\n\n<p>没收尾的段落',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(rich('<b>'), findsNothing);
    expect(rich('加粗的'), findsOneWidget);
    expect(rich('onclick'), findsNothing, reason: '事件属性丢掉');
    expect(rich('position:fixed'), findsNothing, reason: 'style 属性丢掉');
    expect(rich('带事件的'), findsOneWidget);
    expect(rich('<script>'), findsOneWidget, reason: '当文字显示');
    expect(rich('<iframe'), findsOneWidget);
    expect(rich('<blink>'), findsOneWidget);
    expect(find.byType(HtmlPreviewBox), findsNothing);
    expect(rich('里面的内容'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('md-details-toggle')));
    await tester.tap(find.byKey(const Key('md-details-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rich('里面的内容'), findsOneWidget);
  });

  testWidgets('html 代码块：点“预览”才建视图；默认不联网；被拦后“允许这次联网”；链接走确认；全屏', (tester) async {
    await boot(tester, const _Stage(agent: kMdHtmlBlock));
    expect(tester.takeException(), isNull);
    expect(requests, isEmpty, reason: '没点预览之前不建视图');
    expect(rich('onclick'), findsOneWidget, reason: '代码照常显示');
    await shot(tester, 'md-html-code');
    await tester.tap(find.byKey(const Key('md-code-preview')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('html-preview-box')), findsOneWidget);
    expect(requests.last.document, contains(kHtmlPreviewCspOffline));
    expect(requests.last.document, startsWith('<!DOCTYPE html><meta http-equiv="Content-Security-Policy"'));
    expect(requests.last.scrollable, isFalse);
    expect(tester.getSize(find.byKey(const Key('html-preview-box'))).height, 200);
    // 网页报高度：跟着变，但有上下限
    requests.last.onHeight(300);
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('html-preview-box'))).height, 300);
    requests.last.onHeight(5000);
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('html-preview-box'))).height, kHtmlPreviewMaxHeight);
    requests.last.onHeight(10);
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('html-preview-box'))).height, kHtmlPreviewMinHeight);
    // 有资源被拦
    expect(find.byKey(const Key('html-preview-allow')), findsNothing);
    requests.last.onBlocked();
    await tester.pump();
    expect(find.byKey(const Key('html-preview-allow')), findsOneWidget);
    await shot(tester, 'md-html-preview');
    await tester.tap(find.byKey(const Key('html-preview-allow')));
    await tester.pump();
    expect(requests.last.document, contains(kHtmlPreviewCspOnline));
    expect(requests.last.document, isNot(contains(kHtmlPreviewCspOffline)));
    expect(find.byKey(const Key('html-preview-allow')), findsNothing);
    // 网页里点链接：不跳，弹确认
    requests.last.onLink('https://example.com/next');
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('md-link-url'))).data, 'https://example.com/next');
    await tester.tap(find.byKey(const Key('md-link-cancel')));
    await tester.pumpAndSettle();
    // 全屏
    await tester.tap(find.byKey(const Key('html-preview-full')));
    await tester.pumpAndSettle();
    expect(find.text('预览'), findsWidgets);
    expect(requests.last.scrollable, isTrue);
    expect(requests.last.document, contains(kHtmlPreviewCspOnline), reason: '全屏沿用刚才“允许这次联网”');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // 回到看代码
    await tester.tap(find.byKey(const Key('md-code-preview')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('html-preview-box')), findsNothing);
    expect(rich('onclick'), findsOneWidget);
  });

  testWidgets('整条回复就是一份网页：当成 html 代码块，可以预览；同时最多 2 个预览', (tester) async {
    await boot(tester, const _Stage(agent: '<!DOCTYPE html>\n<html><body><p>hi</p></body></html>'));
    expect(find.byKey(const Key('md-code-preview')), findsOneWidget);
    expect(find.text('html'), findsOneWidget);

    const three = '```html\n<p>1</p>\n```\n\n```html\n<p>2</p>\n```\n\n```html\n<p>3</p>\n```';
    await tester.pumpWidget(appFor(env, const _Stage(agent: three), font: fontsLoaded ? kTestFont : null));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 3; i++) {
      final button = find.byKey(const Key('md-code-preview')).at(i);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('html-preview-box'), skipOffstage: false), findsNWidgets(kHtmlPreviewMaxLive));
    expect(find.byKey(const Key('html-preview-reopen'), skipOffstage: false), findsOneWidget, reason: '最早开的那个收起了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('还在往外冒：末尾有光标块；前面排好的块不重建；没收尾的代码块不给预览', (tester) async {
    final text = ValueNotifier('第一段已经写完了。\n\n第二段写到一');
    await boot(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: text,
        builder: (_, v, _) => _Stage(agent: v, streaming: true),
      ),
    );
    expect(rich('▍'), findsOneWidget);
    Widget firstPiece() => tester.widget(find.descendant(of: find.byType(MessageText), matching: find.byKey(const ValueKey(0))));
    final first = firstPiece();
    text.value = '第一段已经写完了。\n\n第二段写到一半，有**没收尾的粗体';
    await tester.pump();
    expect(identical(firstPiece(), first), isTrue, reason: '第一块是同一个控件对象，没有重建');
    expect(rich('**没收尾的粗体'), findsOneWidget, reason: '半截的强调先按纯文字');
    expect(rich('▍'), findsOneWidget);
    text.value = '第一段已经写完了。\n\n第二段写到一半，有**收尾的粗体**。\n\n```html\n<p>还在写';
    await tester.pump();
    expect(identical(firstPiece(), first), isTrue);
    expect(rich('**收尾的粗体**'), findsNothing);
    expect(find.byKey(const Key('md-code-block')), findsOneWidget, reason: '没收尾的围栏当成开着的代码块');
    expect(find.byKey(const Key('md-code-preview')), findsNothing, reason: '没写完不给预览');
    expect(rich('▍'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'md-streaming');
    text.value = '第一段已经写完了。\n\n第二段写到一半，有**收尾的粗体**。\n\n```html\n<p>还在写</p>\n```\n\n| a | b |\n|---|';
    await tester.pump();
    expect(find.byKey(const Key('md-table-scroll')), findsNothing, reason: '半截表格先按纯文字');
    expect(tester.takeException(), isNull);
  });

  testWidgets('思考全文：同一套排版，小字灰色，标题不放大', (tester) async {
    await boot(tester, const _Stage(muted: '# 想法\n先看 `a.dart`，**再**改。', agent: '# 回答\n好的。'));
    expect(tester.takeException(), isNull);
    expect(rich('# 想法'), findsNothing);
    double size(String s) => tester.getSize(rich(s).first).height;
    expect(size('想法'), lessThan(size('回答')));
  });

  testWidgets('超过上限的消息按纯文字显示', (tester) async {
    final huge = '**a** ' * (kMdMaxChars ~/ 6 + 10);
    await boot(tester, _Stage(agent: huge));
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == huge), findsOneWidget);
  });

  testWidgets('性能冒烟：四万多字、三百多块的消息，首次排出来和来回滚都不慢', (tester) async {
    final b = StringBuffer();
    for (var i = 0; i < 110; i++) {
      b
        ..writeln('## 第 $i 节')
        ..writeln()
        ..writeln('这是第 $i 节的正文，有**粗体**、`code` 和[链接](https://example.com/$i)。${'再凑一些字。' * 40}')
        ..writeln()
        ..writeln('```dart\nvoid f$i() {\n  print($i);\n}\n```')
        ..writeln();
    }
    final text = b.toString();
    expect(text.length, greaterThan(40000));
    final watch = Stopwatch()..start();
    await boot(tester, _Stage(agent: text));
    final first = watch.elapsedMilliseconds;
    final list = find.byKey(const Key('stage-list'));
    watch.reset();
    for (var i = 0; i < 20; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump();
    }
    final scroll = watch.elapsedMilliseconds;
    expect(tester.takeException(), isNull);
    // 阈值放得很宽（这台机器慢、还同时跑着别的）：只为抓“慢了一个数量级”的问题
    expect(first, lessThan(60000), reason: '首次排版 $first ms');
    expect(scroll, lessThan(30000), reason: '滚 20 屏 $scroll ms');
    // 同一条消息再建一次：走缓存，是同一份解析结果
    expect(identical(mdParseCached(text), mdParseCached(text)), isTrue);
  });
}
