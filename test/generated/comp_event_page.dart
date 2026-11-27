// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 页面自己的积木逻辑这一份不导出（那些按钮的 onPressed 是空的）；组件事件接的动作导出了，写在那个控件的 onPressed / onTap 里。在自己的代码里用 update(() => s_xxx = 新值) 改状态。
// 没有导出的：
// · 类名开关 on 的样子里的 font-weight（Flutter 这边只认底色、文字颜色、字号、内外边距、圆角、间距、宽、高这几条）。
import 'package:flutter/material.dart';

class CompEventPage extends StatefulWidget {
  const CompEventPage({super.key});

  @override
  State<CompEventPage> createState() => CompEventPageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class CompEventPageState extends State<CompEventPage> {
  Object? s_tagList = <Object?>['水果', '蔬菜', '零食'];
  Object? s_cur = '蔬菜';
  Object? s_got = 0;
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
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 6,
                      children: [
                        for (final v_it in _lcList(s_tagList)) FilledButton(
                          onPressed: () { update(() => s_cur = _lcText(v_it)); },
                          style: FilledButton.styleFrom(),
                          child: Text(_lcText(v_it)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _lcText((_lcText('现在选的：') + _lcText(s_cur))),
                    style: TextStyle(height: 1.5),
                  ),
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: () { update(() => s_got = _lcNum(5)); },
                          style: FilledButton.styleFrom(),
                          child: Text('加'),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: () { update(() => s_got = _lcNum(7)); },
                          style: FilledButton.styleFrom(),
                          child: Text('加'),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _lcText((_lcText('拿到 ') + _lcText(s_got))),
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

/// 当成列表用：不是列表的（还没取到数据、填错了）当成空列表。
List<Object?> _lcList(Object? v) => v is List ? v : const [];
