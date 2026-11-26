// “预览”一段 HTML 时，真正交给网页视图的那份文档怎么拼（纯文字处理，好测）。
//
// 做法（事实来源见 docs/api-notes.md“消息里的 HTML 预览”）：
// - 在文档**最前面**放一条 Content-Security-Policy（内容安全策略）。它在页面自己的任何内容之前生效，页面改不掉。
//   默认不联网：除了写在页面里的脚本 / 样式和 data: 图片，什么外部资源都不让加载，也不让发请求、提交表单。
//   她点了“允许这次联网”才换成“只许 https”的那一条。
// - 文档末尾加一小段脚本，把页面高度（一个数字）报给应用，好让预览框跟着内容变高；
//   有资源被上面那条策略拦下时报一个 -1。应用那头只收数字，别的一概不理。

/// 应用和预览页面之间唯一的一条通道的名字。只收数字。
const String kHtmlPreviewChannel = 'LopiPreviewSize';

/// 通道里表示“有外部资源被拦下了”的那个数。
const double kHtmlPreviewBlockedSignal = -1;

const String kHtmlPreviewCspOffline =
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; font-src data:; form-action 'none'; base-uri 'none'";
const String kHtmlPreviewCspOnline =
    "default-src https: data: blob: 'unsafe-inline' 'unsafe-eval'; form-action 'none'; base-uri 'none'";

/// 能点“预览”的代码块语言。
bool htmlPreviewable(String lang) => const {'html', 'htm', 'xhtml', 'svg'}.contains(lang.toLowerCase());

final RegExp _doctype = RegExp(r'^\s*<!doctype[^>]*>', caseSensitive: false);

String buildPreviewDocument(String code, {String lang = 'html', bool allowNetwork = false}) {
  final csp = allowNetwork ? kHtmlPreviewCspOnline : kHtmlPreviewCspOffline;
  var body = code.replaceFirst(_doctype, '');
  if (lang.toLowerCase() == 'svg') body = '<body style="margin:0">$body</body>';
  const script =
      '<script>(function(){var c=window.$kHtmlPreviewChannel;if(!c)return;'
      'function r(){try{c.postMessage(String(Math.ceil(document.documentElement.scrollHeight)))}catch(e){}}'
      "document.addEventListener('securitypolicyviolation',function(){try{c.postMessage('-1')}catch(e){}});"
      "window.addEventListener('load',r);try{new ResizeObserver(r).observe(document.documentElement)}catch(e){}r();})()</script>";
  return '<!DOCTYPE html><meta http-equiv="Content-Security-Policy" content="$csp">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '$body$script';
}

/// 通道里收到的东西：只认一个不长的数字，其余返回 null（不理）。
double? parsePreviewSignal(String message) {
  if (message.length > 12) return null;
  final n = double.tryParse(message.trim());
  if (n == null || n.isNaN || n.isInfinite) return null;
  if (n == kHtmlPreviewBlockedSignal) return n;
  if (n < 0) return null;
  return n;
}
