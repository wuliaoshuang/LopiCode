// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段，绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。
import 'package:flutter/material.dart';

class CompLoginPage extends StatefulWidget {
  const CompLoginPage({super.key});

  @override
  State<CompLoginPage> createState() => CompLoginPageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class CompLoginPageState extends State<CompLoginPage> {
  Object? s_cart = 0;
  Object? s_apple = '苹果';
  Object? s_u = '';
  Object? s_p = '';
  Object? s_logged = 0;
  Object? s_tagList = <Object?>['水果', '蔬菜', '零食'];
  Object? s_cur = '蔬菜';
  Object? s_login__showTip = false;
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
                    padding: EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          _lcText('请登录'),
                          style: TextStyle(height: 1.5),
                        ),
                        TextField(
                          controller: _lcField('login__userIn', s_u),
                          onChanged: (value) => update(() => s_u = value),
                          decoration: InputDecoration(
                            hintText: '用户名',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        TextField(
                          controller: _lcField('login__passIn', s_p),
                          onChanged: (value) => update(() => s_p = value),
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: '密码',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(value: _lcBool(s_login__showTip), onChanged: (value) => update(() => s_login__showTip = value == true)),
                            Flexible(child: Text('显示提示')),
                          ],
                        ),
                        if (_lcBool(s_login__showTip)) Text(
                          _lcText((_lcText('要登录的是：') + _lcText(s_u))),
                          style: TextStyle(height: 1.5),
                        ),
                        (_lcBool(_lcEq(s_u, '')) ? FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(),
                          child: Text('登录'),
                        ) : FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(),
                          child: Text('登录'),
                        )),
                        Text(
                          '忘记密码？',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _lcText((_lcText('用户=') + _lcText(s_u) + _lcText(' 密码=') + _lcText(s_p) + _lcText(' 登录了 ') + _lcText(s_logged) + _lcText(' 次'))),
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
