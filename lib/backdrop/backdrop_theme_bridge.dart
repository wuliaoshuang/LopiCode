// 背景图片 ↔ 主题导出文件里 `background` 一节的对接（很薄的一层，只用 Map 和字节，不引用主题那边的类型）。
//
// 主题那边（docs/themes-design.md 第四、六节）的 ThemeBackground 有：mime、bytes、cropX/Y/W/H（占**原图**的比例）、
// dim（0–1）、blur（0–40）；图最多 8MB。这里交出去 / 收进来的 Map 就用这些键名，另外多带几项那边还没有的
// （turns、fit、tile、maskColor、brightness）——那边的规矩是“不认识的字段跳过”，带不带都不坏。
//
// 和我们自己的设置怎么对：
// - crop：我们存的是相对**旋转后**的图。主题那边没有“转了几个 90°”这一项，所以转过的图导出时把旋转直接画进图里
//   （重存成 PNG，turns 交出去一律是 0），裁剪区域原样交出去；收进来的数据万一带了 turns，按它换算回去。
// - dim ＝ 遮罩深浅（0–100 → 0–1）；blur 我们最多 30，收进来超了就收到 30。
// - 图超过 8MB：缩小长边重新存成 PNG 再试几档，还超就说明原因、不带图。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/safe_file.dart';

/// 主题导出文件里背景图最多多少字节（主题那边定的）。
const int kThemeBackdropMaxBytes = 8 * 1024 * 1024;

/// 主题那边模糊的上限。
const double kThemeBackdropBlurMax = 40;

/// 图太大时依次试的长边（像素）。
const List<int> kThemeBackdropShrinkSides = [2048, 1600, 1280, 1024];

/// 导出的结果：[data] 有值＝可以带上；没有＝带不了，[error] 是原因。[notes] 是成功但要告诉用户的话。
class BackdropThemeExport {
  const BackdropThemeExport.ok(Map<String, Object?> this.data, {this.notes = const []}) : error = null;
  const BackdropThemeExport.fail(String this.error) : data = null, notes = const [];

  final Map<String, Object?>? data;
  final String? error;
  final List<String> notes;
}

/// 从导入数据还原出来的东西：入库好的图 + 该怎么摆。
class BackdropThemeImport {
  const BackdropThemeImport({required this.image, required this.look});
  final ImportedBackdrop image;

  /// 已经带上图、裁剪、旋转和各项效果的一份样子。
  final BackdropLook look;
}

String _mimeOf(BackdropFormat f) => switch (f) {
  BackdropFormat.jpg => 'image/jpeg',
  BackdropFormat.png => 'image/png',
  BackdropFormat.webp => 'image/webp',
  BackdropFormat.gif => 'image/gif',
};

/// 旋转后的裁剪区域 → 原图上的区域。
CropRect cropToOriginal(CropRect r, int turns) => switch (turns % 4) {
  1 => CropRect(r.top, 1 - r.left - r.width, r.height, r.width),
  2 => CropRect(1 - r.left - r.width, 1 - r.top - r.height, r.width, r.height),
  3 => CropRect(1 - r.top - r.height, r.left, r.height, r.width),
  _ => r,
};

/// 原图上的区域 → 旋转 [turns] 之后的区域。
CropRect cropFromOriginal(CropRect r, int turns) => switch (turns % 4) {
  1 => CropRect(1 - r.top - r.height, r.left, r.height, r.width),
  2 => CropRect(1 - r.left - r.width, 1 - r.top - r.height, r.width, r.height),
  3 => CropRect(r.top, 1 - r.left - r.width, r.height, r.width),
  _ => r,
};

String _mb(int bytes) => bytes % (1024 * 1024) == 0 ? '${bytes ~/ (1024 * 1024)}MB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';

CropRect _snap(CropRect r) {
  double c(double v) => v.clamp(0.0, 1.0);
  final l = c(r.left), t = c(r.top);
  return CropRect(l, t, r.width.clamp(0.0, 1 - l), r.height.clamp(0.0, 1 - t));
}

/// 把图解成长边 [side] 像素、按 [look] 的旋转摆正以后重新存成 PNG。
Future<Uint8List?> _renderPng(Uint8List bytes, BackdropLook look, int side) async {
  final long = look.width > look.height ? look.width : look.height;
  final k = side / long;
  final tw = (look.width * k).round().clamp(1, side);
  final th = (look.height * k).round().clamp(1, side);
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: tw, targetHeight: th);
  ui.Image img;
  try {
    img = (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
  final turns = look.turns % 4;
  if (turns != 0) {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    switch (turns) {
      case 1:
        c.translate(th.toDouble(), 0);
        c.rotate(math.pi / 2);
      case 2:
        c.translate(tw.toDouble(), th.toDouble());
        c.rotate(math.pi);
      case 3:
        c.translate(0, tw.toDouble());
        c.rotate(-math.pi / 2);
    }
    c.drawImage(img, ui.Offset.zero, ui.Paint());
    final pic = rec.endRecording();
    final turned = await pic.toImage(turns.isOdd ? th : tw, turns.isOdd ? tw : th);
    pic.dispose();
    img.dispose();
    img = turned;
  }
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 把 [look] 这张背景导出成能嵌进主题导出文件的数据。没有图、图读不出来、怎么缩都超过上限时回失败和原因。
/// [maxBytes]、[shrinkSides] 只给测试改小用。
Future<BackdropThemeExport> exportBackdropForTheme(BackdropStore store, BackdropLook look, {int maxBytes = kThemeBackdropMaxBytes, List<int> shrinkSides = kThemeBackdropShrinkSides}) async {
  final name = look.file;
  if (!look.hasImage || name == null) return const BackdropThemeExport.fail('现在没有背景图片可以带上。');
  Uint8List bytes;
  try {
    bytes = await store.imageFile(name).readAsBytes();
  } on FileSystemException catch (e) {
    return BackdropThemeExport.fail('背景图片读不出来（${e.osError?.message ?? e.message}）。');
  }
  var format = sniffBackdropFormat(bytes);
  if (format == null || format == BackdropFormat.gif) return const BackdropThemeExport.fail('背景图片的文件坏了，带不上。');
  final notes = <String>[];
  // 主题文件里没有“转了几个 90°”这一项：转过的图导出时直接把旋转画进图里（存成 PNG），那边不用知道转没转过。
  final baked = look.turns % 4 != 0;
  if (baked || bytes.length > maxBytes) {
    // 太大：缩小长边存成 PNG 再试（裁剪区域是比例，不受影响）
    final long = look.width > look.height ? look.width : look.height;
    Uint8List? fit;
    int? side;
    try {
      for (final s in [if (baked) long, ...shrinkSides.where((s) => s < long)]) {
        final png = await _renderPng(bytes, look, s);
        if (png != null && png.length <= maxBytes) {
          fit = png;
          side = s;
          break;
        }
      }
    } on Exception {
      return const BackdropThemeExport.fail('背景图片解不开，带不上。');
    }
    if (fit == null || side == null) {
      return BackdropThemeExport.fail('背景图片太大了（${_mb(bytes.length)}），主题文件里最多带 ${_mb(maxBytes)} 的图，缩小以后还是放不下。这次导出不带图。');
    }
    if (side < long) notes.add('背景图片超过 ${_mb(maxBytes)}，导出时缩小到了长边 $side 像素。');
    bytes = fit;
    format = BackdropFormat.png;
  }
  // 交出去的图已经是转好的样子，所以裁剪区域就是我们存的那个（相对旋转后的图），turns 一律是 0
  final crop = _snap(look.crop);
  return BackdropThemeExport.ok({
    'mime': _mimeOf(format),
    'bytes': bytes,
    'cropX': crop.left,
    'cropY': crop.top,
    'cropW': crop.width,
    'cropH': crop.height,
    'dim': look.maskOpacity / 100,
    'blur': look.blur.toDouble(),
    // 下面几项主题那边现在还没有（不认识会跳过）
    'turns': 0,
    'fit': look.fit.name,
    'tile': look.tilePercent,
    'maskColor': look.maskFollowsTheme ? null : look.maskColor & 0xFFFFFF,
    'brightness': look.brightness,
  }, notes: notes);
}

/// 把导入数据里的图校验后搬进私有目录，并算出该怎么摆（接在 [base] 现有的效果参数上）。
/// 只入库、不改设置；用不用由调用方决定（BackdropNotifier.applyThemeBackground）。出错抛 [BackdropImportException]（人话）。
Future<BackdropThemeImport> importBackdropFromTheme(BackdropStore store, Map<Object?, Object?> data, {BackdropLook base = const BackdropLook()}) async {
  final raw = data['bytes'];
  if (raw is! List<int> || raw.isEmpty) throw const BackdropImportException('主题文件里的背景图片是空的。');
  if (raw.length > kThemeBackdropMaxBytes) {
    throw const BackdropImportException('主题文件里的背景图片太大了（上限 ${kThemeBackdropMaxBytes ~/ (1024 * 1024)}MB）。');
  }
  final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  final format = sniffBackdropFormat(bytes);
  final mime = data['mime'];
  if (format == null || format == BackdropFormat.gif) throw const BackdropImportException('主题文件里的背景图片不是 JPG、PNG 或 WebP。');
  if (mime is String && mime != _mimeOf(format)) throw const BackdropImportException('主题文件里的背景图片和它写的格式对不上。');

  // 先落成私有目录里的一个临时文件，再走和选图一样的入库（校验、缩小、按内容起名）
  final tmp = store.imageFile('incoming-${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await writeFileAtomic(tmp, bytes);
  } on FileSystemException catch (e) {
    throw BackdropImportException('存不下这张图（${e.osError?.message ?? e.message}）。手机存储空间可能不够了。');
  }
  final image = await store.importFile(tmp);

  double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  int? i(Object? v) => v is num && v.isFinite ? v.round() : null;
  final turns = (i(data['turns']) ?? 0).clamp(0, 3);
  final x = n(data['cropX']), y = n(data['cropY']), w = n(data['cropW']), h = n(data['cropH']);
  // 裁剪范围不合理（缺、出界、是 0）当作没裁
  final ok = x != null && y != null && w != null && h != null && w > 0 && h > 0 && x >= 0 && y >= 0 && x + w <= 1 + 1e-6 && y + h <= 1 + 1e-6;
  final crop = ok ? _snap(cropFromOriginal(CropRect(x, y, w, h), turns)) : CropRect.full;
  final fit = data['fit'];
  final color = i(data['maskColor']);
  final dim = n(data['dim']);
  final blur = n(data['blur']);
  final look = base
      .withImage(file: image.file, width: image.width, height: image.height, crop: crop, turns: turns)
      .copyWith(
        fit: BackdropFit.values.where((f) => f.name == fit).firstOrNull,
        tilePercent: i(data['tile']),
        maskFollowsTheme: data.containsKey('maskColor') ? color == null : null,
        maskColor: color == null ? null : 0xFF000000 | (color & 0xFFFFFF),
        maskOpacity: dim == null ? null : (dim.clamp(0.0, 1.0) * 100).round(),
        blur: blur?.clamp(0.0, kBackdropBlurMax.toDouble()).round(),
        brightness: i(data['brightness']),
      );
  return BackdropThemeImport(image: image, look: look);
}
