// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。
import 'package:flutter/material.dart';

class CompCardPage extends StatefulWidget {
  const CompCardPage({super.key});

  @override
  State<CompCardPage> createState() => CompCardPageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class CompCardPageState extends State<CompCardPage> {
  Object? s_cart = 0;
  Object? s_apple = '苹果';
  Object? s_u = '';
  Object? s_p = '';
  Object? s_logged = 0;
  Object? s_tagList = <Object?>['水果', '蔬菜', '零食'];
  Object? s_cur = '蔬菜';
  Object? s_p1__liked = false;
  Object? s_p2__liked = false;
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
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Color(0xFFFFF3E0), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '苹果的图',
                          style: TextStyle(height: 1.5),
                        ),
                        Text(
                          _lcText(s_apple),
                          style: TextStyle(fontSize: 22, height: 1.5),
                        ),
                        Text(
                          _lcText((_lcText('¥') + _lcText(3))),
                          style: TextStyle(color: Color(0xFFD84315), height: 1.5),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(value: _lcBool(s_p1__liked), onChanged: (value) => update(() => s_p1__liked = value == true)),
                            Flexible(child: Text('收藏')),
                          ],
                        ),
                        if (_lcBool(s_p1__liked)) Text(
                          '已收藏',
                          style: TextStyle(height: 1.5),
                        ),
                        Container(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Flexible(
                                child: Text(
                                  '新',
                                  style: TextStyle(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(),
                          child: Text('加入购物车'),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          '（放图片）',
                          style: TextStyle(height: 1.5),
                        ),
                        Text(
                          _lcText('香蕉'),
                          style: TextStyle(fontSize: 16, height: 1.5),
                        ),
                        Text(
                          _lcText((_lcText('¥') + _lcText(2))),
                          style: TextStyle(height: 1.5),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(value: _lcBool(s_p2__liked), onChanged: (value) => update(() => s_p2__liked = value == true)),
                            Flexible(child: Text('收藏')),
                          ],
                        ),
                        if (_lcBool(s_p2__liked)) Text(
                          '已收藏',
                          style: TextStyle(height: 1.5),
                        ),
                        Container(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 4,
                            children: [
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(),
                          child: Text('加入购物车'),
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
