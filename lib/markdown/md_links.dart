// 链接和图片地址的规矩（纯逻辑）：哪些能加载、哪些不能、为什么。界面照着结果画，不自己判断。
import 'dart:convert';
import 'dart:typed_data';

import 'package:lopicode/core/path_guard.dart';

/// 网络图片：等这么久没下完算超时（自己定的）。
const Duration kMdImageTimeout = Duration(seconds: 15);

/// 网络图片最大 5MB；本机图片最大 20MB；data: 图片（解码后）最大 2MB（都是自己定的）。
const int kMdNetImageMaxBytes = 5 * 1024 * 1024;
const int kMdLocalImageMaxBytes = 20 * 1024 * 1024;
const int kMdDataImageMaxBytes = 2 * 1024 * 1024;

/// 网络图片最多跟着跳转几次（每一跳都必须还是 https）。
const int kMdImageMaxRedirects = 3;

const Set<String> _rasterExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

sealed class MdImageSource {
  const MdImageSource();
}

/// 工作区里的图片（[path] 是守卫核对过的绝对路径）。
class MdLocalImage extends MdImageSource {
  const MdLocalImage(this.path);
  final String path;
}

/// https 图片：要她点一下（或设置里开了自动加载）才去下。
class MdNetImage extends MdImageSource {
  const MdNetImage(this.uri);
  final Uri uri;
}

/// 写在消息里的 data: 图片。
class MdDataImage extends MdImageSource {
  const MdDataImage(this.bytes);
  final Uint8List bytes;
}

/// 不加载，[reason] 是给她看的原因。
class MdBlockedImage extends MdImageSource {
  const MdBlockedImage(this.reason);
  final String reason;
}

final RegExp _dataImage = RegExp(r'^data:image/(png|jpeg|jpg|gif|webp|bmp);base64,', caseSensitive: false);
final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

/// 判断一张图片从哪来、能不能加载。[guard] 是当前工作区的路径守卫（没有工作区就传 null）。
MdImageSource mdResolveImage(String src, PathGuard? guard) {
  final s = src.trim();
  if (s.isEmpty) return const MdBlockedImage('没有写图片地址');
  final lower = s.toLowerCase();
  if (lower.startsWith('https://')) {
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return const MdBlockedImage('图片地址写得不对');
    if (uri.userInfo.isNotEmpty) return const MdBlockedImage('图片地址里带了账号密码，不加载');
    return MdNetImage(uri);
  }
  if (lower.startsWith('http://')) return const MdBlockedImage('这是没加密的 http 图片，不加载');
  if (lower.startsWith('data:')) {
    final m = _dataImage.firstMatch(s);
    if (m == null) return const MdBlockedImage('这种内嵌图片不支持');
    final body = s.substring(m.end).replaceAll(RegExp(r'\s'), '');
    // base64 每 4 个字符是 3 个字节：先按长度挡掉太大的，不解码
    if (body.length ~/ 4 * 3 > kMdDataImageMaxBytes) return const MdBlockedImage('内嵌图片太大（超过 2MB），不显示');
    try {
      return MdDataImage(base64.decode(base64.normalize(body)));
    } on FormatException {
      return const MdBlockedImage('内嵌图片的数据坏了');
    }
  }
  if (_scheme.hasMatch(s) && !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s)) return MdBlockedImage('不加载 ${s.split(':').first}: 开头的图片');
  if (guard == null) return const MdBlockedImage('这里没有打开工作区，找不到这张图片');
  // 本机图片：去掉 ?query / #fragment，把 %20 这类写法换回来
  var rel = s.split('#').first.split('?').first;
  try {
    rel = Uri.decodeComponent(rel);
  } on ArgumentError {
    // 不是合法的百分号写法：按原样当文件名
  }
  // 运行环境里工作区挂在 /workspace：模型常写这种绝对路径，换成工作区内的相对路径
  if (rel == '/workspace' || rel.startsWith('/workspace/')) rel = rel.substring('/workspace'.length);
  while (rel.startsWith('/') && guard.root != '/') {
    // 其余以 / 开头的：只有本来就落在工作区里的才认
    if (rel.startsWith('${guard.root}/')) {
      rel = rel.substring(guard.root.length);
    } else if (src.trim().startsWith('/workspace')) {
      rel = rel.substring(1);
    } else {
      return const MdBlockedImage('只显示工作区里面的图片');
    }
  }
  while (rel.startsWith('./')) {
    rel = rel.substring(2);
  }
  final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
  if (!_rasterExt.contains(ext)) return const MdBlockedImage('只显示 png / jpg / gif / webp / bmp 图片');
  try {
    return MdLocalImage(guard.resolve(rel));
  } on PathGuardException {
    return const MdBlockedImage('只显示工作区里面的图片');
  }
}

/// 点链接时给她看的完整网址（控制字符换成可见的，免得藏东西）。
String mdVisibleUrl(String href) => href.replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '�');

/// 链接是哪一类（只用来在确认框里说明，不影响能不能复制）。
String mdLinkKind(String href) {
  final s = href.trim().toLowerCase();
  if (s.startsWith('https://')) return '网页链接';
  if (s.startsWith('http://')) return '网页链接（没加密的 http）';
  if (s.startsWith('mailto:')) return '邮箱地址';
  if (s.startsWith('#')) return '页内位置';
  if (_scheme.hasMatch(s)) return '${s.split(':').first}: 链接';
  return '工作区里的路径';
}
