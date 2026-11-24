import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/ui/chat_composer.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

/// 输入栏的几种样子叠在一张图里（只给截图用）：收起、收起带用量小环、有草稿展开。
class ComposerGallery extends StatefulWidget {
  const ComposerGallery({super.key, required this.brightness, this.font});
  final Brightness brightness;
  final String? font;

  @override
  State<ComposerGallery> createState() => _ComposerGalleryState();
}

class _ComposerGalleryState extends State<ComposerGallery> {
  final _texts = [TextEditingController(), TextEditingController(), TextEditingController(text: '把首页的按钮改成圆角')];
  final _nodes = [FocusNode(), FocusNode(), FocusNode()];

  @override
  void dispose() {
    for (final t in _texts) {
      t.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Widget _one(int i, {bool ring = false, String model = '选择模型'}) => ChatComposer(
    controller: _texts[i],
    focusNode: _nodes[i],
    busy: false,
    canSend: _texts[i].text.isNotEmpty,
    modelName: model,
    permission: PermissionLevel.workspace,
    voiceInput: GalleryVoice(),
    context_: ring ? const ContextUsage(42000, 128000, estimated: false) : null,
    onContext: ring ? () {} : null,
    onPlus: () {},
    onModel: () {},
    onPermission: () {},
    onSend: () {},
    onLongSend: () {},
    onStop: () {},
  );

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: shotKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(widget.brightness, fontFamily: widget.font),
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _one(0),
            const SizedBox(height: 16),
            _one(1, ring: true),
            const SizedBox(height: 16),
            _one(2, ring: true, model: 'DeepSeek Chat'),
          ],
        ),
      ),
    ),
  );
}

class GalleryVoice implements ChatVoiceInput {
  @override
  bool get isListening => false;
  @override
  Future<bool> initialize() async => false;
  @override
  Future<void> listen({required void Function(String words) onResult, required void Function(bool listening) onListeningChanged, required void Function(String message) onError}) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

Future<void> writeShot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}
