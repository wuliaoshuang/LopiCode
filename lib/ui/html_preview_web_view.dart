// 真正画网页的那一层：一个和应用隔开的系统网页视图。宿主机测试里画不出来（平台控件），所以单独一个文件，
// 测试用 HtmlPreview.debugViewBuilder 顶替它。**这里的隔离行为没法在测试里证明，只能真机上看。**
//
// 隔离做了这些（各项设置的出处见 docs/api-notes.md“消息里的 HTML 预览”）：
// - 内容用 loadHtmlString 直接塞进去，不带基准地址：页面的来源是 about:blank，不是应用自己的任何地址，
//   也不是预览服务器的地址；它没有自己的存储，读不到别的页面的数据。
// - 关掉读本机文件（file://）和读内容提供者（content://）。
// - 脚本可以跑（不然预览没意义），但只在这个视图里跑。应用只给它一条通道，而且只收数字（内容高度 / “有东西被拦下”）。
// - 任何跳转（点链接、脚本改地址、表单提交）一律不放行，只把网址交给外面去走“链接确认”。
// - 要权限（摄像头、麦克风、定位）一律拒绝；选文件一律返回空；媒体不自动播放。
// - 联不联网由文档开头的内容安全策略管（见 html_preview_doc.dart）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:lopicode/markdown/html_preview_doc.dart';
import 'package:lopicode/ui/html_preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class HtmlPreviewWebView extends StatefulWidget {
  const HtmlPreviewWebView({super.key, required this.request, this.gestureRecognizers = const {}});
  final HtmlPreviewRequest request;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  @override
  State<HtmlPreviewWebView> createState() => _HtmlPreviewWebViewState();
}

class _HtmlPreviewWebViewState extends State<HtmlPreviewWebView> {
  late final WebViewController _web;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController(onPermissionRequest: (request) => unawaited(request.deny()));
    unawaited(_setUp());
  }

  Future<void> _setUp() async {
    try {
      final platform = _web.platform;
      if (platform is AndroidWebViewController) {
        await platform.setAllowFileAccess(false);
        await platform.setAllowContentAccess(false);
        await platform.setGeolocationEnabled(false);
        await platform.setMediaPlaybackRequiresUserGesture(true);
        await platform.setOnShowFileSelector((_) async => const []);
      }
      await _web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _web.setBackgroundColor(Colors.white);
      await _web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (nav) {
            // 第一次把文档塞进去时地址是 about:blank；其余的都是页面想去别处
            if (nav.url == 'about:blank') return NavigationDecision.navigate;
            if (mounted && nav.isMainFrame) widget.request.onLink(nav.url);
            return NavigationDecision.prevent;
          },
        ),
      );
      await _web.addJavaScriptChannel(
        kHtmlPreviewChannel,
        onMessageReceived: (message) {
          final n = parsePreviewSignal(message.message);
          if (n == null || !mounted) return;
          if (n == kHtmlPreviewBlockedSignal) {
            widget.request.onBlocked();
          } else {
            widget.request.onHeight(n);
          }
        },
      );
      await _web.loadHtmlString(widget.request.document);
    } on Object catch (e) {
      // 这台设备上系统网页组件用不了（被停用 / 版本太旧）：说明原因，不让聊天页跟着崩
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void didUpdateWidget(HtmlPreviewWebView old) {
    super.didUpdateWidget(old);
    if (old.request.document != widget.request.document) {
      // 点了“允许这次联网”：换一份文档重新加载
      unawaited(_web.loadHtmlString(widget.request.document).catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('预览打不开：系统的网页组件没法用。\n$_error', style: const TextStyle(color: Colors.black87, fontSize: 13)),
        ),
      );
    }
    return WebViewWidget(controller: _web, gestureRecognizers: widget.gestureRecognizers);
  }
}
