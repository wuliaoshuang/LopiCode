// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。
// 没有导出的：
// · “按下”时的样子里的 opacity（Flutter 这边按下时只换底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条）。
import 'package:flutter/material.dart';

class B8Page extends StatefulWidget {
  const B8Page({super.key});

  @override
  State<B8Page> createState() => B8PageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class B8PageState extends State<B8Page> {
  Object? s_xs = <Object?>[];
  Object? s_two = <Object?>['苹果', '香蕉'];
  Object? s_none = <Object?>[];
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
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  _LcPress(builder: (context, lcDown) => Container(
                    padding: EdgeInsets.all((lcDown ? 20 : 12)),
                    decoration: BoxDecoration(color: (lcDown ? Color(0xFFFFCC00) : Color(0xFFEEEEEE)), borderRadius: BorderRadius.circular((lcDown ? 16 : 4))),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '按住我',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  )),
                  _LcPress(builder: (context, lcDown) => Text(
                    '按住这行字',
                    style: TextStyle(fontSize: (lcDown ? 20 : 16), color: (lcDown ? Color(0xFFFF0000) : Color(0xFF222222)), height: 1.5),
                  )),
                  _LcPress(builder: (context, lcDown) => Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: (lcDown ? Color(0xFFDDEEFF) : null), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '按住卡片',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  )),
                  for (final v_it in _lcList(s_xs)) Text(
                    _lcText(v_it),
                    style: TextStyle(height: 1.5),
                  ),
                  if (_lcBool(_lcEq(_lcLen(s_xs), 0))) Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          '还没有东西',
                          style: TextStyle(fontSize: 16, color: Color(0xFF222435), height: 1.5),
                        ),
                        FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(),
                          child: Text('放两个进来'),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('放两个'),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('清空'),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }

  /// 轻提示「已保存」：要它出现的时候调用（屏幕下方一句话，3 秒后自己消失）。
  Future<void> showDialog_toast(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已保存'), duration: Duration(seconds: 3), behavior: SnackBarBehavior.floating));
    return Future<void>.value();
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
