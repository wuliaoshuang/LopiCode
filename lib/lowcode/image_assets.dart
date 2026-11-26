/// 页面里的图片文件：从相册选来的拷进项目、列出项目里已有的、把图片地址认成“网址还是项目里的文件”。
///
/// - 图片放在项目的 `images/` 目录（和 index.html 同一层），图片组件的地址写相对路径 `images/xxx.jpg`：
///   导出的网页、预览直接就能显示，不用改页面文件的格式（地址本来就是一个字符串）。
/// - 重名不覆盖：内容一样就直接用已有的那个；不一样就在名字后面加序号。
/// - 地址想跑出项目目录的（`../`、绝对路径）一律当坏图，不去读。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

/// 图片放在项目里的哪个目录。
const String kLcImageDir = 'images';

/// 认得的图片后缀。
const Set<String> kLcImageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'};

/// 列项目里的图片时最多看多少个文件 / 最多列多少张（项目很大时不把手机拖死）。
const int kLcImageScanMax = 4000;
const int kLcImageListMax = 200;

/// 这个地址是不是网上的（http / https / data），不是项目里的文件。
bool lcIsRemoteSrc(String src) {
  final s = src.trimLeft().toLowerCase();
  return s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:') || s.startsWith('//');
}

/// 项目里的图片地址 → 真实文件路径。网址、空的、跑出项目的、不是图片后缀的都返回 null。
String? lcResolveImage(PathGuard guard, String src) {
  final s = src.trim();
  if (s.isEmpty || lcIsRemoteSrc(s) || s.contains(':')) return null;
  final clean = s.split(RegExp('[?#]')).first;
  if (!kLcImageExts.contains(p.extension(clean).toLowerCase())) return null;
  try {
    return guard.resolve(Uri.decodeComponent(clean));
  } on PathGuardException {
    return null;
  } on ArgumentError {
    return null; // 百分号写坏了
  }
}

String _safeName(String name) {
  var ext = p.extension(name).toLowerCase();
  if (!kLcImageExts.contains(ext)) ext = '.jpg';
  var base = p.basenameWithoutExtension(name).replaceAll(RegExp(r'[^A-Za-z0-9_\-\u4e00-\u9fff]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'image';
  if (base.length > 40) base = base.substring(0, 40);
  return '$base$ext';
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 把一张图片存进项目的 images/ 目录，返回写进图片组件的相对地址（`images/名字.jpg`）。
Future<String> lcImportImage(PathGuard guard, String name, Uint8List bytes) async {
  final safe = _safeName(name);
  final base = p.basenameWithoutExtension(safe), ext = p.extension(safe);
  for (var i = 1; ; i++) {
    final rel = '$kLcImageDir/${i == 1 ? base : '$base-$i'}$ext';
    final file = File(guard.resolve(rel));
    if (await file.exists()) {
      if (_sameBytes(await file.readAsBytes(), bytes)) return rel; // 同一张：直接用
      continue;
    }
    await writeFileAtomic(file, bytes);
    return rel;
  }
}

/// 项目里已有的图片（相对地址，images/ 里的排前面，其余按名字）。不看隐藏目录和 node_modules、build。
Future<List<String>> lcListProjectImages(PathGuard guard) async {
  final out = <String>[];
  var seen = 0;
  Future<void> walk(Directory dir, int depth) async {
    if (depth > 6 || seen > kLcImageScanMax) return;
    final List<FileSystemEntity> items;
    try {
      items = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // 没权限读的目录跳过
    }
    for (final e in items) {
      if (++seen > kLcImageScanMax) return;
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (name == 'node_modules' || name == 'build' || name == 'export') continue;
        await walk(e, depth + 1);
      } else if (e is File && kLcImageExts.contains(p.extension(name).toLowerCase())) {
        out.add(guard.relative(e.path));
      }
    }
  }

  await walk(Directory(guard.root), 0);
  int rank(String s) => s.startsWith('$kLcImageDir/') ? 0 : 1;
  out.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.compareTo(b));
  return out.take(kLcImageListMax).toList();
}

/// 页面（连同自定义组件）里用到的项目图片地址，不重复、按出现的顺序。网址不算。
List<String> lcLocalImageSrcs(LcDocument doc) {
  final out = <String>{};
  void walk(LcNode n) {
    final src = n.type == 'image' ? n.strProp('src')?.trim() : null;
    if (src != null && src.isNotEmpty && !lcIsRemoteSrc(src)) out.add(src);
    n.children.forEach(walk);
  }

  walk(doc.root);
  for (final c in doc.components) {
    walk(c.root);
  }
  return out.toList();
}

/// 导出 Vue / React 时把页面用到的项目图片拷到 `<dir>/public/` 下面（保持原来的相对路径），返回拷了几张。
/// 放进工程的 public 目录以后，代码里写的相对地址就能显示。读不到的、地址不对的跳过。
Future<int> lcCopyExportImages(PathGuard guard, String dir, LcDocument doc) async {
  var n = 0;
  for (final src in lcLocalImageSrcs(doc)) {
    final from = lcResolveImage(guard, src);
    if (from == null || !await File(from).exists()) continue;
    final to = File(guard.resolve('$dir/public/${guard.relative(from)}'));
    await writeFileAtomic(to, await File(from).readAsBytes());
    n++;
  }
  return n;
}
