// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 页面自己的积木逻辑这一份不导出（那些按钮的 onPressed 是空的）；组件事件接的动作导出了，写在那个控件的 onPressed / onTap 里。在自己的代码里用 update(() => s_xxx = 新值) 改状态。
// 没有导出的：
// · 类名开关 on 的样子里的 font-weight（Flutter 这边只认底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条）。
import 'package:flutter/material.dart';

class CompTagsPage extends StatefulWidget {
  const CompTagsPage({super.key});

  @override
  State<CompTagsPage> createState() => CompTagsPageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class CompTagsPageState extends State<CompTagsPage> {
  Object? s_cart = 0;
  Object? s_apple = '苹果';
  Object? s_u = '';
  Object? s_p = '';
  Object? s_logged = 0;
  Object? s_tagList = <Object?>['水果', '蔬菜', '零食'];
  Object? s_cur = '蔬菜';
  final _lcChanged = ValueNotifier<int>(0);

  /// 改状态都走这里：`update(() => s_xxx = 新值)`。
  void update(void Function() change) {
    setState(change);
    _lcChanged.value++;
  }

  @override
  void dispose() {
    _lcChanged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(0),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lcText((_lcText('购物车 ') + _lcText(s_cart) + _lcText(' 件'))),
                    style: TextStyle(height: 1.5),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('改名'),
                  ),
                  Container(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 6,
                      children: [
                        if (_lcList(s_tagList).isEmpty) Text('还没有标签'),
                        for (final v_it in _lcList(s_tagList)) Flexible(
                          child: Text(
                            _lcText(v_it),
                            style: TextStyle(color: _lcColor(_lcBool(_lcEq(v_it, s_cur)) ? '#1565C0' : null), height: 1.5),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _lcText((_lcText('共 ') + _lcText(_lcLen(s_tagList)) + _lcText(' 个'))),
                            style: TextStyle(height: 1.5),
                          ),
                        ),
                        FilledButton(
                          onPressed: () { update(() => s_cur = _lcText('')); },
                          style: FilledButton.styleFrom(),
                          child: Text('清空'),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _lcText((_lcText('现在选的：') + _lcText(s_cur))),
                    style: TextStyle(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
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

/// 当成列表用：不是列表的（还没取到数据、填错了）当成空列表。
List<Object?> _lcList(Object? v) => v is List ? v : const [];

/// 列表有几项。
int _lcLen(Object? v) => v is List ? v.length : 0;

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
