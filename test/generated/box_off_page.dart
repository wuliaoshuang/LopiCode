// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 页面自己的积木逻辑这一份不导出（那些按钮的 onPressed 是空的）；组件事件接的动作导出了，写在那个控件的 onPressed / onTap 里。在自己的代码里用 update(() => s_xxx = 新值) 改状态。
import 'package:flutter/material.dart';

class BoxOffPage extends StatefulWidget {
  const BoxOffPage({super.key});

  @override
  State<BoxOffPage> createState() => BoxOffPageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class BoxOffPageState extends State<BoxOffPage> {
  Object? s_hits = 0;
  Object? s_off = false;
  Object? s_tip = '会锁上的块';
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
                    _lcText((_lcText('点了 ') + _lcText(s_hits) + _lcText(' 次'))),
                    style: TextStyle(height: 1.5),
                  ),
                  Tooltip(message: '加一', child: Container(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '能点的块',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  )),
                  Tooltip(message: '关着的块', child: Opacity(opacity: 0.5, child: Container(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '禁用的块',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ))),
                  (_lcBool(s_off) ? Tooltip(message: _lcText(s_tip), child: Opacity(opacity: 0.5, child: Container(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '会锁上的块',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ))) : Tooltip(message: _lcText(s_tip), child: Container(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '会锁上的块',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ))),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(),
                    child: Text('锁上'),
                  ),
                  Tooltip(message: '收藏', child: Opacity(opacity: 0.5, child: Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Color(0xFFEEF3F5), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 24, color: Color(0xFF222435)),
                      ],
                    ),
                  ))),
                  (_lcBool(s_off) ? Tooltip(message: '点赞', child: Opacity(opacity: 0.5, child: Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Color(0xFFEEF3F5), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 24, color: Color(0xFF222435)),
                      ],
                    ),
                  ))) : Tooltip(message: '点赞', child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { update(() => s_hits = _lcNum((_lcNum(s_hits) + _lcNum(1)))); }, child: Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Color(0xFFEEF3F5), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 24, color: Color(0xFF222435)),
                      ],
                    ),
                  )))),
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: () { update(() => s_hits = _lcNum((_lcNum(s_hits) + _lcNum(1)))); }, child: Container(
                    width: 40,
                    height: 40,
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Color(0xFFEEF3F5), borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 24, color: Color(0xFF222435)),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
        ),
      );
  }
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
