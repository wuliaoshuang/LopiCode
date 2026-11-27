// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 主题变量：集中在文件末尾的 LcVars 里，改那里一处，用到的地方全跟着变。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。
// 断点：按屏幕宽度取样子（平板 ≥768、桌面 ≥1024），见各页的 build。
// 没有导出的：
// · 样式绑定里的 letter-spacing（Flutter 这边只认底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条；别的 CSS 属性没有对得上的写法）。
import 'package:flutter/material.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => LivePageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class LivePageState extends State<LivePage> {
  Object? s_on = false;
  Object? s_pick = 'a';
  Object? s_city = '';
  Object? s_note = '';
  Object? s_n = 2;
  Object? s_tint = '#FF0000';
  Object? s_photo = '';
  Object? get s_twice => (_lcNum(s_n) * _lcNum(2));
  final Map<String, TextEditingController> _lcFields = {};
  final _lcChanged = ValueNotifier<int>(0);

  /// 改状态都走这里：`update(() => s_xxx = 新值)`。
  void update(void Function() change) {
    setState(change);
    _lcChanged.value++;
  }

  @override
  void dispose() {
    for (final c in _lcFields.values) {
      c.dispose();
    }
    _lcChanged.dispose();
    super.dispose();
  }

  /// 双向绑定的输入框用的控制器：状态被别处改了，下一帧把框里的字对齐（正在打的字不打断）。
  TextEditingController _lcField(String id, Object? value, {bool number = false}) {
    final text = _lcText(value);
    final c = _lcFields.putIfAbsent(id, () => TextEditingController(text: text));
    final same = number ? _lcNum(c.text) == _lcNum(value) : c.text == text;
    if (!same) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.text != text) c.text = text;
      });
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    // 按屏幕宽度取样子：从宽到窄，先对上哪一档用哪一档。
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 768) return _buildTablet(context);
    return _buildPhone(context);
  }

  /// 手机的样子。
  Widget _buildPhone(BuildContext context) {
    return Scaffold(
        backgroundColor: Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          title: Text(_lcText((_lcText('数到 ') + _lcText(s_n)))),
          centerTitle: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Container(
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // 网格：2 列等宽。lcGridW 是一格的宽度。
                        final lcGridW = ((box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width) - LcVars.spaceSm * 1) / 2;
                        return Wrap(
                          spacing: LcVars.spaceSm,
                          runSpacing: 8,
                          children: [
                            SizedBox(width: _lcCell(lcGridW, 2, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '甲（跨两列）',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '乙',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '丙',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        );
                      },
                    ),
                  ),
                  Switch(value: _lcBool(s_on), onChanged: (value) => update(() => s_on = value)),
                  if (_lcBool(s_on)) Text(
                    '开着',
                    style: TextStyle(height: 1.5),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => update(() => s_pick = 'a'), child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_lcEq(s_pick, 'a') ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                          SizedBox(width: 8),
                          Flexible(child: Text('甲项')),
                        ],
                      )),
                      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => update(() => s_pick = 'b'), child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_lcEq(s_pick, 'b') ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                          SizedBox(width: 8),
                          Flexible(child: Text('乙项')),
                        ],
                      )),
                    ],
                  ),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: [
                      ButtonSegment(value: 'a', label: Text('按钮甲')),
                      ButtonSegment(value: 'b', label: Text('按钮乙')),
                    ],
                    selected: _lcPick(s_pick, ['a', 'b']),
                    onSelectionChanged: (value) => update(() => s_pick = value.isEmpty ? '' : value.first),
                  ),
                  Text(
                    _lcText((_lcText('选了：') + _lcText(s_pick))),
                    style: TextStyle(height: 1.5),
                  ),
                  DropdownMenu<String>(
                    initialSelection: _lcPickOne(s_city, ['bj', 'sh']),
                    onSelected: (value) => update(() => s_city = value ?? ''),
                    hintText: '选城市',
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(value: 'bj', label: '北京'),
                      DropdownMenuEntry(value: 'sh', label: '上海'),
                    ],
                  ),
                  Text(
                    _lcText((_lcText('城市：') + _lcText(s_city))),
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _lcField('ta', s_note),
                      onChanged: (value) => update(() => s_note = value),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '备注',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  if (_lcBool(!_lcEq(s_note, ''))) Text(
                    _lcText((_lcText('备注：') + _lcText(s_note))),
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _lcField('num', s_n, number: true),
                      onChanged: (value) => update(() => s_n = _lcNum(value)),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '数字',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Color(0xFFFF0000), width: 2)),
                      ),
                    ),
                  ),
                  Text(
                    _lcText((_lcText('双倍：') + _lcText(s_twice))),
                    style: TextStyle(fontSize: _lcPx((_lcText((_lcNum(s_n) * _lcNum(10))) + _lcText('px')), 14), color: _lcColor(s_tint, Color(0xFF222435)), height: 1.5),
                  ),
                  (_lcBool(!_lcBool(s_on)) ? FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorAccent, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? Color(0xFFCCCCCC) : (states.contains(WidgetState.pressed) ? LcVars.colorAccent : LcVars.colorAccent)), foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? Color(0xFFFFFF00) : Color(0xFFFFFFFF)))),
                    child: Text('提交'),
                  ) : FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorAccent, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? Color(0xFFCCCCCC) : (states.contains(WidgetState.pressed) ? LcVars.colorAccent : LcVars.colorAccent)), foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? Color(0xFFFFFF00) : Color(0xFFFFFFFF)))),
                    child: Text('提交'),
                  )),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: _lcImage(_lcText(s_photo), height: 40, fit: BoxFit.cover, semanticLabel: '照片', errorBuilder: (context, error, stack) => Icon(Icons.broken_image_outlined)),
                  ),
                  Text(
                    '只在手机上',
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 平板（屏幕宽度 ≥ 768）的样子。
  Widget _buildTablet(BuildContext context) {
    return Scaffold(
        backgroundColor: Color(0xFFFFFFFF),
        appBar: AppBar(
          primary: true,
          automaticallyImplyLeading: false,
          title: Text(_lcText((_lcText('数到 ') + _lcText(s_n)))),
          centerTitle: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Container(
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // 网格：4 列等宽。lcGridW 是一格的宽度。
                        final lcGridW = ((box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width) - LcVars.spaceSm * 3) / 4;
                        return Wrap(
                          spacing: LcVars.spaceSm,
                          runSpacing: 8,
                          children: [
                            SizedBox(width: _lcCell(lcGridW, 2, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '甲（跨两列）',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '乙',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, LcVars.spaceSm), child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '丙',
                                    style: TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        );
                      },
                    ),
                  ),
                  Switch(value: _lcBool(s_on), onChanged: (value) => update(() => s_on = value)),
                  if (_lcBool(s_on)) Text(
                    '开着',
                    style: TextStyle(height: 1.5),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => update(() => s_pick = 'a'), child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_lcEq(s_pick, 'a') ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                          SizedBox(width: 8),
                          Flexible(child: Text('甲项')),
                        ],
                      )),
                      GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => update(() => s_pick = 'b'), child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_lcEq(s_pick, 'b') ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                          SizedBox(width: 8),
                          Flexible(child: Text('乙项')),
                        ],
                      )),
                    ],
                  ),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: [
                      ButtonSegment(value: 'a', label: Text('按钮甲')),
                      ButtonSegment(value: 'b', label: Text('按钮乙')),
                    ],
                    selected: _lcPick(s_pick, ['a', 'b']),
                    onSelectionChanged: (value) => update(() => s_pick = value.isEmpty ? '' : value.first),
                  ),
                  Text(
                    _lcText((_lcText('选了：') + _lcText(s_pick))),
                    style: TextStyle(height: 1.5),
                  ),
                  DropdownMenu<String>(
                    initialSelection: _lcPickOne(s_city, ['bj', 'sh']),
                    onSelected: (value) => update(() => s_city = value ?? ''),
                    hintText: '选城市',
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(value: 'bj', label: '北京'),
                      DropdownMenuEntry(value: 'sh', label: '上海'),
                    ],
                  ),
                  Text(
                    _lcText((_lcText('城市：') + _lcText(s_city))),
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _lcField('ta', s_note),
                      onChanged: (value) => update(() => s_note = value),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '备注',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  if (_lcBool(!_lcEq(s_note, ''))) Text(
                    _lcText((_lcText('备注：') + _lcText(s_note))),
                    style: TextStyle(height: 1.5),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _lcField('num', s_n, number: true),
                      onChanged: (value) => update(() => s_n = _lcNum(value)),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '数字',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Color(0xFFFF0000), width: 2)),
                      ),
                    ),
                  ),
                  Text(
                    _lcText((_lcText('双倍：') + _lcText(s_twice))),
                    style: TextStyle(fontSize: _lcPx((_lcText((_lcNum(s_n) * _lcNum(10))) + _lcText('px')), 14), color: _lcColor(s_tint, Color(0xFF222435)), height: 1.5),
                  ),
                  (_lcBool(!_lcBool(s_on)) ? FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorAccent, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? Color(0xFFCCCCCC) : (states.contains(WidgetState.pressed) ? LcVars.colorAccent : LcVars.colorAccent)), foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? Color(0xFFFFFF00) : Color(0xFFFFFFFF)))),
                    child: Text('提交'),
                  ) : FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: LcVars.colorAccent, foregroundColor: Color(0xFFFFFFFF)).copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? Color(0xFFCCCCCC) : (states.contains(WidgetState.pressed) ? LcVars.colorAccent : LcVars.colorAccent)), foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.disabled) ? null : (states.contains(WidgetState.pressed) ? Color(0xFFFFFF00) : Color(0xFFFFFFFF)))),
                    child: Text('提交'),
                  )),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: _lcImage(_lcText(s_photo), height: 40, fit: BoxFit.cover, semanticLabel: '照片', errorBuilder: (context, error, stack) => Icon(Icons.broken_image_outlined)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 弹窗「5」：要打开它的时候调用（比如放在按钮的 onPressed 里）。
  Future<void> showDialog_dlg(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ListenableBuilder(listenable: _lcChanged, builder: (context, child) => AlertDialog(
        title: Text(_lcText((_lcText('现在是 ') + _lcText(s_n)))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('正文'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('确定')),
        ],
      )),
    );
  }
}

/// 主题变量：全应用只此一处。改这里的值，用到它的地方都跟着变。
abstract final class LcVars {
  /// color-accent（--color-accent）
  static const Color colorAccent = Color(0xFF058654);

  /// 小间距（--space-sm）
  static const double spaceSm = 8;
  // --font-family-x: serif（不是长度也不是颜色，Flutter 这边用不上）
}

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

/// 当成“是 / 否”（空的、0、空串是“否”）。
bool _lcBool(Object? v) => switch (v) {
  null || false => false,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};

/// 等于：类型一样直接比，不一样都转成文字再比。
bool _lcEq(Object? a, Object? b) {
  String kind(Object? v) => v is num ? 'n' : (v is String ? 's' : (v is bool ? 'b' : (v == null ? 'u' : 'o')));
  if (kind(a) != kind(b)) return _lcText(a) == _lcText(b);
  return a is List || a is Map ? identical(a, b) : a == b;
}

/// `120px` / 120 → 120；认不出来是 null。
double? _lcPxOrNull(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final t = _lcText(v).trim();
  final d = double.tryParse(t.endsWith('px') ? t.substring(0, t.length - 2) : t);
  return d != null && d.isFinite ? d : null;
}

/// `120px` / 120 → 120；认不出来用 fallback。
double _lcPx(Object? v, [double fallback = 0]) => _lcPxOrNull(v) ?? fallback;

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

/// 网格里跨 span 列的格子有多宽。
double _lcCell(double column, int span, double gap) {
  final w = column * span + gap * (span - 1);
  return w.isFinite && w > 0 ? w : 0;
}

/// 地址是绑来的图片：网上的用 Image.network，项目里的用 Image.asset，空的画占位。
Widget _lcImage(String src, {double? height, double? width, BoxFit? fit, String? semanticLabel, ImageErrorWidgetBuilder? errorBuilder}) {
  if (src.isEmpty) return Container(height: height, width: width, color: const Color(0xFFD3DEE4), alignment: Alignment.center, child: Icon(Icons.image_outlined, semanticLabel: semanticLabel));
  final remote = src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:');
  return remote
      ? Image.network(src, height: height, width: width, fit: fit, semanticLabel: semanticLabel, errorBuilder: errorBuilder)
      : Image.asset(src, height: height, width: width, fit: fit, semanticLabel: semanticLabel, errorBuilder: errorBuilder);
}

/// 单选组现在选中的那一项（值不在选项里＝都没选）。
Set<String> _lcPick(Object? v, List<String> options) => {
  for (final o in options)
    if (_lcEq(v, o)) o,
};

/// 下拉选择现在选中的那一项（值不在选项里＝没选）。
String? _lcPickOne(Object? v, List<String> options) {
  for (final o in options) {
    if (_lcEq(v, o)) return o;
  }
  return null;
}
