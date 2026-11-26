// 设计约束（消息里 HTML 代码块的“预览” · 390×844）— 2026-11-26
// - 预览放在一个和应用隔开的网页视图里（见 html_preview_web_view.dart）：点了“预览”才创建，滚出屏幕就销毁；
//   同时最多留 2 个，再开第 3 个，最早的那个自动收起成一行“点这里重新预览”。
// - 预览框跟着网页内容变高，最矮 120、最高 360；想看全就点“全屏看”进一个单独的页面。
// - 默认不联网。网页想加载外部资源被拦下时，框下面多出一行说明和“允许这次联网”（只对这一个预览、这一次有效，不记住）。
// - 一行只做一件事：网页一块；（有拦截时）说明 + 允许按钮一行；“全屏看”一行。
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:lopicode/markdown/html_preview_doc.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/html_preview_web_view.dart';
import 'package:lopicode/ui/md_link.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 预览框的高度范围、同时存在的预览数（都是自己定的）。
const double kHtmlPreviewMinHeight = 120;
const double kHtmlPreviewMaxHeight = 360;
const int kHtmlPreviewMaxLive = 2;

/// 交给“真正画网页的那一层”的东西。
class HtmlPreviewRequest {
  const HtmlPreviewRequest({required this.document, required this.onHeight, required this.onBlocked, required this.onLink, this.scrollable = false});

  /// 已经拼好的完整文档（带内容安全策略，见 html_preview_doc.dart）。
  final String document;

  /// 网页报来的内容高度。
  final void Function(double height) onHeight;

  /// 有外部资源被拦下了。
  final VoidCallback onBlocked;

  /// 网页里点了链接 / 想跳转到别处：不跳，把网址交出来。
  final void Function(String url) onLink;

  /// 网页自己能不能上下滑（全屏时可以；嵌在聊天里时不抢聊天列表的滑动）。
  final bool scrollable;
}

typedef HtmlPreviewViewBuilder = Widget Function(HtmlPreviewRequest request);

abstract final class HtmlPreview {
  /// 测试 / 截图用：网页视图是平台控件，宿主机上画不出来，用它顶替。
  static HtmlPreviewViewBuilder? debugViewBuilder;

  static Widget view(HtmlPreviewRequest request) => (debugViewBuilder ?? _real)(request);

  static Widget _real(HtmlPreviewRequest request) =>
      HtmlPreviewWebView(request: request, gestureRecognizers: request.scrollable ? const {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)} : const {});
}

/// 现在开着的预览（从旧到新）。
final List<_HtmlPreviewBoxState> _live = [];

class HtmlPreviewBox extends StatefulWidget {
  const HtmlPreviewBox({super.key, required this.code, required this.lang});
  final String code;
  final String lang;

  @override
  State<HtmlPreviewBox> createState() => _HtmlPreviewBoxState();
}

class _HtmlPreviewBoxState extends State<HtmlPreviewBox> {
  bool _evicted = false;
  bool _allowNetwork = false;
  bool _blocked = false;
  double _height = 200;

  @override
  void initState() {
    super.initState();
    _enter();
  }

  void _enter() {
    _live.add(this);
    while (_live.length > kHtmlPreviewMaxLive) {
      _live.removeAt(0)._evict();
    }
  }

  void _evict() {
    if (mounted) setState(() => _evicted = true);
  }

  @override
  void dispose() {
    _live.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    if (_evicted) {
      return InkWell(
        key: const Key('html-preview-reopen'),
        onTap: () => setState(() {
          _evicted = false;
          _enter();
        }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          child: Text('同时最多开 $kHtmlPreviewMaxLive 个预览，这个先收起了。点这里重新预览', style: t.bodySmall?.copyWith(color: c.textMuted)),
        ),
      );
    }
    final document = buildPreviewDocument(widget.code, lang: widget.lang, allowNetwork: _allowNetwork);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const Key('html-preview-box'),
          height: _height.clamp(kHtmlPreviewMinHeight, kHtmlPreviewMaxHeight),
          // 网页默认是白底黑字，深色模式下也给它白底
          color: Colors.white,
          child: HtmlPreview.view(
            HtmlPreviewRequest(
              document: document,
              onHeight: (h) {
                if (mounted && (h - _height).abs() >= 1) setState(() => _height = h);
              },
              onBlocked: () {
                if (mounted && !_blocked) setState(() => _blocked = true);
              },
              onLink: (url) {
                if (mounted) showMdLinkSheet(context, url);
              },
            ),
          ),
        ),
        if (_blocked && !_allowNetwork)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x1, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('这个网页想加载外部的东西（图片、脚本、字体……），已经拦下了。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.4)),
                ),
                TextButton(key: const Key('html-preview-allow'), onPressed: () => setState(() => _allowNetwork = true), child: const Text('允许这次联网')),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('html-preview-full'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HtmlPreviewScreen(code: widget.code, lang: widget.lang, allowNetwork: _allowNetwork),
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: c.textMuted),
            icon: const Icon(Icons.open_in_full_rounded, size: 16),
            label: const Text('全屏看'),
          ),
        ),
      ],
    );
  }
}

/// 全屏预览。
class HtmlPreviewScreen extends StatefulWidget {
  const HtmlPreviewScreen({super.key, required this.code, required this.lang, this.allowNetwork = false});
  final String code;
  final String lang;
  final bool allowNetwork;

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  late bool _allowNetwork = widget.allowNetwork;
  bool _blocked = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PageBar(titleText: '预览', subtitle: _allowNetwork ? '已允许这次联网（只许 https）' : '没有联网'),
      body: BelowBar(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_blocked && !_allowNetwork)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x2, Space.x1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('这个网页想加载外部的东西，已经拦下了。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.4)),
                      ),
                      TextButton(key: const Key('html-preview-allow'), onPressed: () => setState(() => _allowNetwork = true), child: const Text('允许这次联网')),
                    ],
                  ),
                ),
              Expanded(
                child: ColoredBox(
                  color: Colors.white,
                  child: HtmlPreview.view(
                    HtmlPreviewRequest(
                      document: buildPreviewDocument(widget.code, lang: widget.lang, allowNetwork: _allowNetwork),
                      scrollable: true,
                      onHeight: (_) {},
                      onBlocked: () {
                        if (mounted && !_blocked) setState(() => _blocked = true);
                      },
                      onLink: (url) {
                        if (mounted) showMdLinkSheet(context, url);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
