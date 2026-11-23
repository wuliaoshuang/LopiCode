// 设计约束（预览 · 390×844）
// - 工具行一行只做“怎么看”：宽度切换（手机 / 平板 / 桌面）在左，刷新在右。
// - 网页占满中间；平板 / 桌面宽度按比例缩小到屏幕宽，不出现横向滚动。
// - 控制台是次要信息：底部一行摘要（几条日志、几条报错），点开才展开面板。
// - 保存文件、Agent 改文件、低代码改动后自动刷新。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/preview/preview_server.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/state/workspace_preview.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PreviewTab extends ConsumerStatefulWidget {
  const PreviewTab({super.key, required this.session, required this.active});
  final ProjectSession session;
  final bool active;

  /// 测试 / 截图用：WebView 是平台视图，测试环境里画不出来，用它顶替。
  static Widget Function(Uri uri)? debugViewBuilder;

  @override
  ConsumerState<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends ConsumerState<PreviewTab> {
  WebViewController? _web;
  String? _error;
  bool _ready = false;
  bool _stale = false;
  bool _consoleOpen = false;
  int _width = 0; // 0 = 跟屏幕一样宽

  PreviewNotifier get _preview => ref.read(previewProvider(widget.session).notifier);
  PreviewServer get server => _preview.server;

  @override
  void initState() {
    super.initState();
    // 别处改了项目文件就跟着刷新（页面销毁时自动取消订阅）
    ref.listenManual(filesRevProvider(widget.session), (_, _) => _onFilesChanged());
    _start();
  }

  @override
  void didUpdateWidget(PreviewTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && _stale) _reload();
  }

  Future<void> _start() async {
    try {
      await _preview.start();
      // 服务器没起来：原因在状态里，下面 build 会显示
      if (!mounted || ref.read(previewProvider(widget.session)).error != null) return;
      if (PreviewTab.debugViewBuilder == null) {
        final web = _web = WebViewController();
        await web.setJavaScriptMode(JavaScriptMode.unrestricted);
        await web.loadRequest(server.baseUri);
      }
      if (mounted) setState(() => _ready = true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _onFilesChanged() {
    if (widget.active) {
      _reload();
    } else {
      _stale = true;
    }
  }

  void _reload() {
    _stale = false;
    server.clearLogs();
    _web?.loadRequest(server.baseUri);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // 服务器起没起来、控制台日志变没变：从这里订阅
    final error = ref.watch(previewProvider(widget.session)).error ?? _error;
    if (error != null) {
      return EmptyState(icon: Icons.error_outline, title: '预览服务器没启动成功', message: error);
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final errors = server.logs.where((l) => l.level == 'error').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x2, Space.x2),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('手机')),
                    ButtonSegment(value: 768, label: Text('平板')),
                    ButtonSegment(value: 1280, label: Text('桌面')),
                  ],
                  selected: {_width},
                  onSelectionChanged: (s) => setState(() => _width = s.first),
                ),
              ),
              const SizedBox(width: Space.x2),
              IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.symmetric(horizontal: BorderSide(color: c.border)),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final view = PreviewTab.debugViewBuilder?.call(server.baseUri) ?? WebViewWidget(controller: _web!);
                if (_width == 0 || _width <= box.maxWidth) return view;
                // 用更宽的逻辑宽度排版，再整体缩小到屏幕宽。
                final scale = box.maxWidth / _width;
                return FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: _width.toDouble(), height: box.maxHeight / scale, child: view),
                );
              },
            ),
          ),
        ),
        InkWell(
          onTap: () => setState(() => _consoleOpen = !_consoleOpen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 16, color: errors > 0 ? c.danger : c.textFaint),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      server.logs.isEmpty ? '控制台 · 没有输出' : '控制台 · ${server.logs.length} 条${errors > 0 ? '，其中 $errors 条报错' : ''}',
                      style: t.bodySmall?.copyWith(color: errors > 0 ? c.danger : c.textMuted),
                    ),
                  ),
                  Icon(_consoleOpen ? Icons.expand_more : Icons.expand_less, size: 18, color: c.textFaint),
                ],
              ),
            ),
          ),
        ),
        if (_consoleOpen)
          Container(
            height: 180,
            width: double.infinity,
            color: c.codeBg,
            child: server.logs.isEmpty
                ? Center(child: Text('页面里的 console.log 和报错会显示在这里', style: t.bodySmall))
                : ListView.builder(
                    padding: const EdgeInsets.all(Space.x3),
                    itemCount: server.logs.length,
                    itemBuilder: (context, i) {
                      final log = server.logs[i];
                      final color = switch (log.level) {
                        'error' => c.danger,
                        'warn' => c.warning,
                        _ => c.text,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Space.x1),
                        child: SelectableText(
                          log.message,
                          style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: color),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
