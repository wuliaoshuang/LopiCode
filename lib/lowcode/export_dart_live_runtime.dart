/// Flutter 导出“会动的那一路”带进导出文件的小函数（用到哪个带哪个）。
///
/// 规矩和编辑器里算绑定的那套（bind_eval.dart）、导出的 JS 小工具（lcNum / lcText / lcEq）逐条一样：
/// 算术一律按数字算（转不了的当 0，除以 0 当 0）；等于＝类型一样直接比，不一样都转成文字再比。
library;

import 'package:lopicode/lowcode/export_dart_live_events.dart';

/// 名字 → 源码。
const Map<String, String> kDartLiveRuntime = {
  '_lcNum': r'''
/// 当成数字（转不了的当 0）。
num _lcNum(Object? v) {
  final n = switch (v) {
    final num x => x,
    final String s => num.tryParse(s.trim()),
    true => 1,
    false => 0,
    _ => null,
  };
  return n != null && n.isFinite ? n : 0;
}
''',
  '_lcText': r'''
/// 当成文字（整数不带小数点，空的是空串）。
String _lcText(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (!v.isFinite) return '$v';
    final r = double.parse(v.toDouble().toStringAsPrecision(12));
    return r == r.roundToDouble() && r.abs() < 1e15 ? '${r.round()}' : '$r';
  }
  if (v is List) return v.map(_lcText).join(',');
  if (v is Map) return '[object Object]';
  return '$v';
}
''',
  '_lcBool': r'''
/// 当成“是 / 否”（空的、0、空串是“否”）。
bool _lcBool(Object? v) => switch (v) {
  null || false => false,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};
''',
  '_lcEq': r'''
/// 等于：类型一样直接比，不一样都转成文字再比。
bool _lcEq(Object? a, Object? b) {
  String kind(Object? v) => v is num ? 'n' : (v is String ? 's' : (v is bool ? 'b' : (v == null ? 'u' : 'o')));
  if (kind(a) != kind(b)) return _lcText(a) == _lcText(b);
  return a is List || a is Map ? identical(a, b) : a == b;
}
''',
  '_lcDiv': r'''
/// 除（除以 0 当 0）。
num _lcDiv(Object? a, Object? b) {
  final d = _lcNum(b);
  return d == 0 ? 0 : _lcNum(_lcNum(a) / d);
}
''',
  '_lcMod': r'''
/// 取余（除以 0 当 0）。
num _lcMod(Object? a, Object? b) {
  final d = _lcNum(b);
  return d == 0 ? 0 : _lcNum(_lcNum(a).remainder(d));
}
''',
  '_lcList': r'''
/// 当成列表用：不是列表的（还没取到数据、填错了）当成空列表。
List<Object?> _lcList(Object? v) => v is List ? v : const [];
''',
  '_lcLen': r'''
/// 列表有几项。
int _lcLen(Object? v) => v is List ? v.length : 0;
''',
  '_lcAt': r'''
/// 记录里一格一格往下取；取不到是 null。
Object? _lcAt(Object? v, List<String> path) {
  for (final p in path) {
    final i = int.tryParse(p);
    v = v is Map ? v[p] : (v is List && i != null && i >= 0 && i < v.length ? v[i] : null);
  }
  return v;
}
''',
  '_lcPxOrNull': r'''
/// `120px` / 120 → 120；认不出来是 null。
double? _lcPxOrNull(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final t = _lcText(v).trim();
  final d = double.tryParse(t.endsWith('px') ? t.substring(0, t.length - 2) : t);
  return d != null && d.isFinite ? d : null;
}
''',
  '_lcPx': r'''
/// `120px` / 120 → 120；认不出来用 fallback。
double _lcPx(Object? v, [double fallback = 0]) => _lcPxOrNull(v) ?? fallback;
''',
  '_lcColor': r'''
/// `#RGB` / `#RRGGBB` / `#RRGGBBAA` → 颜色；认不出来用 fallback。
Color? _lcColor(Object? v, [Color? fallback]) {
  var t = _lcText(v).trim();
  if (!t.startsWith('#')) return fallback;
  t = t.substring(1);
  if (t.length == 3 || t.length == 4) t = t.split('').map((c) => '$c$c').join();
  final n = int.tryParse(t, radix: 16);
  if (n == null) return fallback;
  if (t.length == 6) return Color(0xFF000000 | n);
  if (t.length == 8) return Color(((n & 0xFF) << 24) | (n >> 8));
  return fallback;
}
''',
  '_lcAlpha': r'''
Color? _lcAlpha(Color? c, int alpha) => c?.withAlpha(alpha);
''',
  '_lcCell': r'''
/// 网格里跨 span 列的格子有多宽。
double _lcCell(double column, int span, double gap) {
  final w = column * span + gap * (span - 1);
  return w.isFinite && w > 0 ? w : 0;
}
''',
  '_lcImage': r'''
/// 地址是绑来的图片：网上的用 Image.network，项目里的用 Image.asset，空的画占位。
Widget _lcImage(String src, {double? height, double? width, BoxFit? fit, String? semanticLabel, ImageErrorWidgetBuilder? errorBuilder}) {
  if (src.isEmpty) return Container(height: height, width: width, color: const Color(0xFFD3DEE4), alignment: Alignment.center, child: Icon(Icons.image_outlined, semanticLabel: semanticLabel));
  final remote = src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:');
  return remote
      ? Image.network(src, height: height, width: width, fit: fit, semanticLabel: semanticLabel, errorBuilder: errorBuilder)
      : Image.asset(src, height: height, width: width, fit: fit, semanticLabel: semanticLabel, errorBuilder: errorBuilder);
}
''',
  '_lcPick': r'''
/// 单选组现在选中的那一项（值不在选项里＝都没选）。
Set<String> _lcPick(Object? v, List<String> options) => {
  for (final o in options)
    if (_lcEq(v, o)) o,
};
''',
  '_lcPickOne': r'''
/// 下拉选择现在选中的那一项（值不在选项里＝没选）。
String? _lcPickOne(Object? v, List<String> options) {
  for (final o in options) {
    if (_lcEq(v, o)) return o;
  }
  return null;
}
''',
  '_lcAlert': kDartLiveAlert,
  '_LcPress': r'''
/// 记着“手指按没按着”，按着时里面的东西换成“按下”的样子（只是看，不抢点击、滑动）。
class _LcPress extends StatefulWidget {
  const _LcPress({required this.builder});
  final Widget Function(BuildContext context, bool lcDown) builder;

  @override
  State<_LcPress> createState() => _LcPressState();
}

class _LcPressState extends State<_LcPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: widget.builder(context, _down),
  );
}
''',
};

/// [code] 里用到的小函数（连它们自己用到的），按上面的先后排。
String dartLiveRuntimeFor(String code) {
  final used = <String>{};
  var text = code;
  for (var grew = true; grew;) {
    grew = false;
    for (final e in kDartLiveRuntime.entries) {
      if (!used.contains(e.key) && RegExp('${e.key}\\b').hasMatch(text)) {
        used.add(e.key);
        text += e.value;
        grew = true;
      }
    }
  }
  return [
    for (final e in kDartLiveRuntime.entries)
      if (used.contains(e.key)) '\n${e.value}',
  ].join();
}
