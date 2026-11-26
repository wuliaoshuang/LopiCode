/// 主题文件的读和写（第 1 版格式，见 docs/themes-design.md）。
///
/// 读的规矩：只把文件当数据看，**绝不执行里面的任何东西**；类型、颜色写法、数值范围、名字长度、总大小都查；
/// 不认识的字段跳过；缺的字段从“同明暗的默认主题”补；有问题就返回一句人话，不抛异常。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 文件开头的记号。
const String kThemeFormatTag = 'lopicode-theme';

/// 一份主题（不含背景图）最大多少字节。
const int kThemeMaxBytes = 256 * 1024;

/// 导入的文件（含附带的背景图）最大多少字节。
const int kThemeImportMaxBytes = 12 * 1024 * 1024;

/// 附带的背景图解码后最大多少字节。
const int kThemeBackgroundMaxBytes = 8 * 1024 * 1024;

const int kThemeNameMax = 40;
const int kThemeAuthorMax = 40;

final RegExp _idRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');

/// 标识能不能用（也用来保证它当文件名是安全的）。
bool isValidThemeId(String id) => _idRe.hasMatch(id);

/// '#RRGGBB' / '#AARRGGBB' → ARGB 整数；写法不对返回 null。
int? parseThemeColor(Object? value) {
  if (value is! String) return null;
  final m = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(value.trim());
  if (m == null) return null;
  final hex = m[1]!;
  final n = int.parse(hex, radix: 16);
  return hex.length == 6 ? 0xFF000000 | n : n;
}

/// ARGB 整数 → '#RRGGBB'（不透明）或 '#AARRGGBB'。
String formatThemeColor(int argb) {
  final v = argb & 0xFFFFFFFF;
  final hex = v.toRadixString(16).padLeft(8, '0').toUpperCase();
  return (v >> 24) == 0xFF ? '#${hex.substring(2)}' : '#$hex';
}

/// 导出文件里附带的背景图（可选）。主题本身不带图；图怎么存、怎么显示由背景图那部分管。
///
/// [fit]、[tile]、[maskFollowsTheme] / [maskColor]、[brightness] 是后加的可选项：文件里没写就是 null，
/// 导入的人那边这几项保持原样。
class ThemeBackground {
  const ThemeBackground({
    required this.mime,
    required this.bytes,
    this.cropX = 0,
    this.cropY = 0,
    this.cropW = 1,
    this.cropH = 1,
    this.dim = 0,
    this.blur = 0,
    this.fit,
    this.tile,
    this.maskFollowsTheme,
    this.maskColor,
    this.brightness,
  });

  /// image/jpeg、image/png、image/webp 之一。
  final String mime;
  final Uint8List bytes;

  /// 显示哪一块：左上角和宽高，都是占原图的比例（0–1）。
  final double cropX;
  final double cropY;
  final double cropW;
  final double cropH;

  /// 压暗多少（0–1）和模糊多少（0–40）。
  final double dim;
  final double blur;

  /// 适配方式：[kThemeBackgroundFits] 之一（铺满 / 完整显示 / 平铺）。
  final String? fit;

  /// 平铺时一格占屏幕宽的百分之几（10–100）。
  final int? tile;

  /// 遮罩颜色：true＝跟随主题；false＝用 [maskColor]（0xRRGGBB）；null＝文件里没写。
  final bool? maskFollowsTheme;
  final int? maskColor;

  /// 亮度：−100（全黑）…100（全白）。
  final int? brightness;
}

/// `background.fit` 认的三种写法。
const Set<String> kThemeBackgroundFits = {'cover', 'contain', 'tile'};

/// `background.maskColor` 写这个词表示“跟随主题”。
const String kThemeBackgroundMaskTheme = 'theme';

/// 背景图那一节写成 JSON 对象（导出用）。
Map<String, Object?> encodeThemeBackground(ThemeBackground b) => {
  'mime': b.mime,
  'data': base64Encode(b.bytes),
  'crop': {'x': b.cropX, 'y': b.cropY, 'w': b.cropW, 'h': b.cropH},
  'dim': b.dim,
  'blur': b.blur,
  if (b.fit != null) 'fit': b.fit,
  if (b.tile != null) 'tile': b.tile,
  if (b.maskFollowsTheme == true) 'maskColor': kThemeBackgroundMaskTheme else if (b.maskColor != null) 'maskColor': formatThemeColor(0xFF000000 | (b.maskColor! & 0xFFFFFF)),
  if (b.brightness != null) 'brightness': b.brightness,
};

/// 读背景图那一节。成功时第一项有值；用不了时第二项是原因（人话）。
(ThemeBackground?, String?) decodeThemeBackground(Object? raw) => _decodeBackground(raw);

const Set<String> kThemeBackgroundMimes = {'image/jpeg', 'image/png', 'image/webp'};

/// 读一份主题的结果：成功时 [theme] 有值；失败时 [error] 是一句人话。
class ThemeDecodeResult {
  const ThemeDecodeResult.ok(ThemeSpec this.theme, {this.background, this.notes = const []}) : error = null;
  const ThemeDecodeResult.fail(String this.error) : theme = null, background = null, notes = const [];

  final ThemeSpec? theme;
  final ThemeBackground? background;
  final String? error;

  /// 读成功了但有话要说（比如跳过了不认识的字段、背景图没法用）。
  final List<String> notes;

  bool get ok => theme != null;
}

/// 把主题写成 JSON 对象。[background] 给了就一起带上。
Map<String, Object?> encodeTheme(ThemeSpec t, {ThemeBackground? background}) => {
  'format': kThemeFormatTag,
  'version': kThemeFormatVersion,
  'theme': {
    'id': t.id,
    'name': t.name,
    if (t.author != null) 'author': t.author,
    'dark': t.dark,
    for (final e in kThemeColorSections.entries)
      e.key: {
        for (final f in e.value)
          if (t.section(e.key)[f.key] != null) f.key: formatThemeColor(t.section(e.key)[f.key]!),
      },
    'tokens': {
      for (final f in kTokenFields)
        if (t.tokens[f.key] != null)
          f.key: {'color': t.tokens[f.key]!.color == null ? null : formatThemeColor(t.tokens[f.key]!.color!), 'bold': t.tokens[f.key]!.bold, 'italic': t.tokens[f.key]!.italic},
    },
    'metrics': {
      for (final f in kMetricFields)
        if (t.metrics[f.key] != null) f.key: t.metrics[f.key],
    },
  },
  if (background != null) 'background': encodeThemeBackground(background),
};

/// 导出成文本（给别人导入用）。
String encodeThemeText(ThemeSpec t, {ThemeBackground? background}) => const JsonEncoder.withIndent('  ').convert(encodeTheme(t, background: background));

/// 读一段主题文本。
ThemeDecodeResult decodeThemeText(String text) {
  final size = utf8.encode(text).length;
  if (size > kThemeImportMaxBytes) return ThemeDecodeResult.fail('文件太大了（${_mb(size)}），最多 ${_mb(kThemeImportMaxBytes)}。');
  if (text.trim().isEmpty) return const ThemeDecodeResult.fail('文件是空的。');
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const ThemeDecodeResult.fail('这不是主题文件：内容不是合法的 JSON。');
  }
  return decodeThemeJson(json);
}

/// 读一个已经解析好的 JSON 对象。
ThemeDecodeResult decodeThemeJson(Object? json) {
  if (json is! Map) return const ThemeDecodeResult.fail('这不是主题文件：最外层应该是一个对象。');
  if (json['format'] != kThemeFormatTag) return const ThemeDecodeResult.fail('这不是 LopiCode 的主题文件（缺少 "format": "lopicode-theme"）。');
  final version = json['version'];
  if (version is! int || version < 1) return const ThemeDecodeResult.fail('主题文件的版本号不对（"version" 应该是 1）。');
  if (version > kThemeFormatVersion) return ThemeDecodeResult.fail('这个主题文件是更新版本的应用导出的（格式第 $version 版），这个版本只认到第 $kThemeFormatVersion 版。先升级应用再导入。');
  final t = json['theme'];
  if (t is! Map) return const ThemeDecodeResult.fail('主题文件里没有 "theme" 这一节。');

  final dark = t['dark'];
  if (dark is! bool) return const ThemeDecodeResult.fail('主题文件没说自己是浅色还是深色（"dark" 应该是 true 或 false）。');
  final rawName = t['name'];
  if (rawName is! String || rawName.trim().isEmpty) return const ThemeDecodeResult.fail('主题没有名字（"name" 应该是一段文字）。');
  final name = rawName.trim();
  if (name.runes.length > kThemeNameMax) return ThemeDecodeResult.fail('主题的名字太长了（${name.runes.length} 个字），最多 $kThemeNameMax 个字。');
  final rawAuthor = t['author'];
  if (rawAuthor != null && rawAuthor is! String) return const ThemeDecodeResult.fail('“作者”应该是一段文字。');
  final author = (rawAuthor as String?)?.trim();
  if (author != null && author.runes.length > kThemeAuthorMax) return const ThemeDecodeResult.fail('作者的名字太长了，最多 $kThemeAuthorMax 个字。');
  final rawId = t['id'];
  final id = rawId is String && isValidThemeId(rawId) ? rawId : '';

  final base = defaultThemeFor(dark: dark);
  final notes = <String>[];
  var skipped = 0;

  final sections = <String, Map<String, int>>{};
  for (final entry in kThemeColorSections.entries) {
    final label = kThemeSectionLabels[entry.key]!;
    final raw = t[entry.key];
    if (raw != null && raw is! Map) return ThemeDecodeResult.fail('“$label”这一节的格式不对（应该是一组“名字: 颜色”）。');
    final out = {...base.section(entry.key)};
    if (raw is Map) {
      final known = {for (final f in entry.value) f.key: f};
      for (final e in raw.entries) {
        final f = known[e.key];
        if (f == null) {
          skipped++;
          continue;
        }
        final color = parseThemeColor(e.value);
        if (color == null) return ThemeDecodeResult.fail('“$label › ${f.label}”的值 ${_show(e.value)} 不是颜色。颜色要写成 #RRGGBB 或 #AARRGGBB。');
        out[f.key] = color;
      }
    }
    sections[entry.key] = out;
  }

  final tokens = {...base.tokens};
  final rawTokens = t['tokens'];
  if (rawTokens != null && rawTokens is! Map) return const ThemeDecodeResult.fail('“代码高亮”这一节的格式不对。');
  if (rawTokens is Map) {
    final known = {for (final f in kTokenFields) f.key: f};
    for (final e in rawTokens.entries) {
      final f = known[e.key];
      if (f == null) {
        skipped++;
        continue;
      }
      final v = e.value;
      if (v is String) {
        final color = parseThemeColor(v);
        if (color == null) return ThemeDecodeResult.fail('“代码高亮 › ${f.label}”的值 ${_show(v)} 不是颜色。颜色要写成 #RRGGBB 或 #AARRGGBB。');
        tokens[f.key] = TokenStyle(color: color);
        continue;
      }
      if (v is! Map) return ThemeDecodeResult.fail('“代码高亮 › ${f.label}”的格式不对（应该是 {"color": …, "bold": …, "italic": …}）。');
      final rawColor = v['color'];
      final color = rawColor == null ? null : parseThemeColor(rawColor);
      if (rawColor != null && color == null) return ThemeDecodeResult.fail('“代码高亮 › ${f.label}”的颜色 ${_show(rawColor)} 写法不对。颜色要写成 #RRGGBB 或 #AARRGGBB。');
      final bold = v['bold'];
      final italic = v['italic'];
      if ((bold != null && bold is! bool) || (italic != null && italic is! bool)) return ThemeDecodeResult.fail('“代码高亮 › ${f.label}”的粗体 / 斜体应该是 true 或 false。');
      tokens[f.key] = TokenStyle(color: color, bold: bold == true, italic: italic == true);
    }
  }

  final metrics = {...base.metrics};
  final rawMetrics = t['metrics'];
  if (rawMetrics != null && rawMetrics is! Map) return const ThemeDecodeResult.fail('“形状与密度”这一节的格式不对。');
  if (rawMetrics is Map) {
    final known = {for (final f in kMetricFields) f.key: f};
    for (final e in rawMetrics.entries) {
      final f = known[e.key];
      if (f == null) {
        skipped++;
        continue;
      }
      final v = e.value;
      if (v is! num || !v.isFinite) return ThemeDecodeResult.fail('“形状与密度 › ${f.label}”应该是一个数字。');
      if (v < f.min || v > f.max) return ThemeDecodeResult.fail('“形状与密度 › ${f.label}”是 $v，超出了范围（${_num(f.min)}–${_num(f.max)}）。');
      metrics[f.key] = v.toDouble();
    }
  }

  const knownTheme = {'id', 'name', 'author', 'dark', 'tokens', 'metrics'};
  skipped += t.keys.where((k) => !knownTheme.contains(k) && !kThemeColorSections.containsKey(k)).length;
  skipped += json.keys.where((k) => !const {'format', 'version', 'theme', 'background'}.contains(k)).length;
  if (skipped > 0) notes.add('跳过了 $skipped 个这个版本不认识的字段。');
  final theme = ThemeSpec(
    id: id,
    name: name,
    author: author == null || author.isEmpty ? null : author,
    dark: dark,
    ui: sections['ui']!,
    code: sections['code']!,
    tokens: tokens,
    terminal: sections['terminal']!,
    blocks: sections['blocks']!,
    lowcode: sections['lowcode']!,
    metrics: metrics,
  );
  if (utf8.encode(jsonEncode(encodeTheme(theme))).length > kThemeMaxBytes) return const ThemeDecodeResult.fail('主题数据太大了，超过了 256KB 的上限。');

  ThemeBackground? background;
  if (json['background'] != null) {
    final (bg, why) = _decodeBackground(json['background']);
    background = bg;
    if (why != null) notes.add('附带的背景图没法用，已经跳过：$why');
  }
  return ThemeDecodeResult.ok(theme, background: background, notes: notes);
}

(ThemeBackground?, String?) _decodeBackground(Object? raw) {
  if (raw is! Map) return (null, '格式不对。');
  final mime = raw['mime'];
  if (mime is! String || !kThemeBackgroundMimes.contains(mime)) return (null, '只支持 JPEG、PNG、WebP 图片。');
  final data = raw['data'];
  if (data is! String || data.isEmpty) return (null, '没有图片数据。');
  if (data.length > kThemeBackgroundMaxBytes * 4 ~/ 3 + 16) return (null, '图片太大了，最多 ${_mb(kThemeBackgroundMaxBytes)}。');
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    return (null, '图片数据坏了（不是合法的 base64）。');
  }
  if (bytes.length > kThemeBackgroundMaxBytes) return (null, '图片太大了，最多 ${_mb(kThemeBackgroundMaxBytes)}。');
  if (!_looksLike(mime, bytes)) return (null, '图片内容和它声称的格式对不上。');
  double numOr(Object? v, double fallback) => v is num && v.isFinite ? v.toDouble() : fallback;
  final crop = raw['crop'];
  var x = 0.0, y = 0.0, w = 1.0, h = 1.0;
  if (crop is Map) {
    x = numOr(crop['x'], 0);
    y = numOr(crop['y'], 0);
    w = numOr(crop['w'], 1);
    h = numOr(crop['h'], 1);
    final bad = x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > 1.0001 || y + h > 1.0001;
    if (bad) {
      // 裁剪范围不合理就当作没裁：图还是能用的。
      x = 0;
      y = 0;
      w = 1;
      h = 1;
    }
  }
  // 后加的四个可选项：没写＝null（导入的人那边保持原样）；写了就严格查，不对就整张图不用并说原因。
  String? fit;
  if (raw.containsKey('fit')) {
    final v = raw['fit'];
    if (v is! String || !kThemeBackgroundFits.contains(v)) return (null, '适配方式（fit）只能是 cover、contain、tile 之一。');
    fit = v;
  }
  int? whole(Object? v, int min, int max) => v is num && v.isFinite && v == v.roundToDouble() && v >= min && v <= max ? v.toInt() : null;
  int? tile;
  if (raw.containsKey('tile')) {
    tile = whole(raw['tile'], 10, 100);
    if (tile == null) return (null, '平铺大小（tile）应该是 10–100 的整数。');
  }
  bool? maskFollowsTheme;
  int? maskColor;
  if (raw.containsKey('maskColor')) {
    final v = raw['maskColor'];
    if (v == kThemeBackgroundMaskTheme) {
      maskFollowsTheme = true;
    } else {
      final argb = v is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v) ? parseThemeColor(v) : null;
      if (argb == null) return (null, '遮罩颜色（maskColor）应该是 #RRGGBB，或者写 theme 表示跟随主题。');
      maskFollowsTheme = false;
      maskColor = argb & 0xFFFFFF;
    }
  }
  int? brightness;
  if (raw.containsKey('brightness')) {
    brightness = whole(raw['brightness'], -100, 100);
    if (brightness == null) return (null, '亮度（brightness）应该是 −100 到 100 的整数。');
  }
  return (
    ThemeBackground(
      mime: mime,
      bytes: bytes,
      cropX: x,
      cropY: y,
      cropW: w,
      cropH: h,
      dim: numOr(raw['dim'], 0).clamp(0, 1).toDouble(),
      blur: numOr(raw['blur'], 0).clamp(0, 40).toDouble(),
      fit: fit,
      tile: tile,
      maskFollowsTheme: maskFollowsTheme,
      maskColor: maskColor,
      brightness: brightness,
    ),
    null,
  );
}

/// 只看文件头几个字节，判断是不是它声称的图片格式（不解码）。
bool _looksLike(String mime, Uint8List b) {
  bool starts(List<int> sig, [int at = 0]) {
    if (b.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[at + i] != sig[i]) return false;
    }
    return true;
  }

  return switch (mime) {
    'image/jpeg' => starts([0xFF, 0xD8, 0xFF]),
    'image/png' => starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    'image/webp' => starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8),
    _ => false,
  };
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// 报错时把值给人看一眼：太长的截短，免得一条报错里塞一大段。
String _show(Object? v) {
  final s = v is String ? '"$v"' : '$v';
  return s.length > 24 ? '${s.substring(0, 24)}…' : s;
}
