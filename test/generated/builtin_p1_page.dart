// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 页面自己的积木逻辑这一份不导出（那些按钮的 onPressed 是空的）；组件事件接的动作导出了，写在那个控件的 onPressed / onTap 里。在自己的代码里用 update(() => s_xxx = 新值) 改状态。
import 'package:flutter/material.dart';

class BuiltinP1Page extends StatefulWidget {
  const BuiltinP1Page({super.key});

  @override
  State<BuiltinP1Page> createState() => BuiltinP1PageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class BuiltinP1PageState extends State<BuiltinP1Page> {
  Object? s_n = 3;
  Object? s_hits = 0;
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
                    _lcText((_lcText('数量 ') + _lcText(s_n))),
                    style: TextStyle(height: 1.5),
                  ),
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 8,
                      children: [
                        (_lcBool((_lcNum(s_n) <= _lcNum(1))) ? FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(backgroundColor: Color(0xFFEEF3F5), foregroundColor: Color(0xFF222435), padding: EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), textStyle: TextStyle(fontSize: 16)),
                          child: Text('−'),
                        ) : FilledButton(
                          onPressed: () { update(() => s_n = _lcNum((_lcNum(s_n) - _lcNum(2)))); },
                          style: FilledButton.styleFrom(backgroundColor: Color(0xFFEEF3F5), foregroundColor: Color(0xFF222435), padding: EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), textStyle: TextStyle(fontSize: 16)),
                          child: Text('−'),
                        )),
                        Flexible(
                          child: Text(
                            _lcText(s_n),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Color(0xFF222435), height: 1.5),
                          ),
                        ),
                        (_lcBool((_lcNum(s_n) >= _lcNum(5))) ? FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(backgroundColor: Color(0xFFEEF3F5), foregroundColor: Color(0xFF222435), padding: EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), textStyle: TextStyle(fontSize: 16)),
                          child: Text('+'),
                        ) : FilledButton(
                          onPressed: () { update(() => s_n = _lcNum((_lcNum(s_n) + _lcNum(2)))); },
                          style: FilledButton.styleFrom(backgroundColor: Color(0xFFEEF3F5), foregroundColor: Color(0xFF222435), padding: EdgeInsets.all(6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), textStyle: TextStyle(fontSize: 16)),
                          child: Text('+'),
                        )),
                      ],
                    ),
                  ),
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _lcGoTo(context, MorePage()), child: Text(
                    _lcText('去更多'),
                    style: TextStyle(decoration: TextDecoration.underline, fontSize: 16, color: Color(0xFF1565C0), height: 1.5),
                  )),
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { update(() => s_hits = _lcNum((_lcNum(s_hits) + _lcNum(1)))); }, child: Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Color(0x00000000), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star, size: 24),
                      ],
                    ),
                  )),
                  Text(
                    _lcText((_lcText('点了 ') + _lcText(s_hits) + _lcText(' 次'))),
                    style: TextStyle(height: 1.5),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(0),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // 网格：3 列等宽。lcGridW 是一格的宽度。
                        final lcGridW = ((box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width) - 8 * 2) / 3;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(width: _lcCell(lcGridW, 1, 8), child: Text(
                              '格 1',
                              style: TextStyle(height: 1.5),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, 8), child: Text(
                              '格 2',
                              style: TextStyle(height: 1.5),
                            )),
                            SizedBox(width: _lcCell(lcGridW, 1, 8), child: Text(
                              '格 3',
                              style: TextStyle(height: 1.5),
                            )),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    height: 200,
                    padding: EdgeInsets.all(0),
                    child: SingleChildScrollView(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '滚动区里的字',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    )),
                  ),
                  Container(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Container(
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Container(
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 2,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _lcText('姓名'),
                                        style: TextStyle(fontSize: 14, color: Color(0xFF4A5560), height: 1.5),
                                      ),
                                    ),
                                    if (_lcBool(true)) Flexible(
                                      child: Text(
                                        '*',
                                        style: TextStyle(fontSize: 14, color: Color(0xFFD32F2F), height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextField(
                                decoration: InputDecoration(
                                  hintText: '你的名字',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_lcBool(!_lcEq('', ''))) Text(
                          _lcText(''),
                          style: TextStyle(fontSize: 12, color: Color(0xFF7A8791), height: 1.5),
                        ),
                        if (_lcBool(!_lcEq('必填', ''))) Text(
                          _lcText('必填'),
                          style: TextStyle(fontSize: 12, color: Color(0xFFD32F2F), height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

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
                    '这是更多页',
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

/// 去另一页（叠在当前页上面，系统的返回能回来）。
void _lcGoTo(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// 换成另一页（底部导航用：不往上叠）。page 是 null＝这一项没设去哪页，什么都不做。
void _lcSwitchTo(BuildContext context, Widget? page) {
  if (page == null) return;
  Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
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

/// 网格里跨 span 列的格子有多宽。
double _lcCell(double column, int span, double gap) {
  final w = column * span + gap * (span - 1);
  return w.isFinite && w > 0 ? w : 0;
}
