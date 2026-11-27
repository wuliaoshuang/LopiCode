// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
// 状态与绑定：状态是页面 State 类里 s_ 开头的字段（跨页共用的在 LcAppState 里），绑了它的地方跟着变；输入框、开关这些会把值写回去。
// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。
// 没有导出的：
// · 类名开关 ready（它还没配“成立时的样子”，Flutter 里没有“类名”这个东西，所以这条在 Flutter 里什么也不做；在编辑器里给它配上样子就会导出）。
import 'package:flutter/material.dart';

class BindHomePage extends StatefulWidget {
  const BindHomePage({super.key});

  @override
  State<BindHomePage> createState() => BindHomePageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class BindHomePageState extends State<BindHomePage> {
  Object? s_count = 0;
  Object? s_keyword = '';
  Object? s_agree = false;
  Object? s_names = <Object?>['甲', '乙'];
  Object? get s_tip => (_lcText('已点 ') + _lcText(s_count) + _lcText(' 次'));
  final Map<String, TextEditingController> _lcFields = {};
  final _lcChanged = ValueNotifier<int>(0);

  /// 改状态都走这里：`update(() => s_xxx = 新值)`。
  void update(void Function() change) {
    setState(change);
    _lcChanged.value++;
  }

  void _lcOnApp() {
    if (mounted) update(() {});
  }

  @override
  void initState() {
    super.initState();
    LcAppState.changed.addListener(_lcOnApp);
  }

  @override
  void dispose() {
    LcAppState.changed.removeListener(_lcOnApp);
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
        backgroundColor: Color(0xFFFFFFFF),
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
                  Text(
                    _lcText((_lcText('你好，') + _lcText(LcAppState.user))),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                  Text(
                    _lcText(s_tip),
                    style: TextStyle(height: 1.5),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('加一'),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _lcField('kw', s_keyword),
                      onChanged: (value) => update(() => s_keyword = value),
                      decoration: InputDecoration(
                        hintText: '搜点什么',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                  if (_lcBool(!_lcEq(s_keyword, ''))) Text(
                    _lcText((_lcText('在搜：') + _lcText(s_keyword))),
                    style: TextStyle(height: 1.5),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(value: _lcBool(s_agree), onChanged: (value) => update(() => s_agree = value == true)),
                      Flexible(child: Text('我同意')),
                    ],
                  ),
                  (_lcBool(!_lcBool(s_agree)) ? SizedBox(
                    width: _lcPxOrNull((_lcText((_lcNum((_lcNum(s_count) * _lcNum(10))) + _lcNum(120))) + _lcText('px'))),
                    child: FilledButton(
                      onPressed: null,
                      style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('提交'),
                    ),
                  ) : SizedBox(
                    width: _lcPxOrNull((_lcText((_lcNum((_lcNum(s_count) * _lcNum(10))) + _lcNum(120))) + _lcText('px'))),
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: Text('提交'),
                    ),
                  )),
                  if (_lcBool((_lcNum(s_count) >= _lcNum(3)))) Text(
                    '点够三次了',
                    style: TextStyle(height: 1.5),
                  ),
                  if (_lcList(LcAppState.cart).isEmpty) Text('购物车是空的'),
                  for (final (v_i, v_it) in _lcList(LcAppState.cart).indexed) Container(
                    width: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      spacing: 8,
                      children: [
                        Flexible(
                          child: Text(
                            _lcText((_lcText((_lcNum(v_i) + _lcNum(1))) + _lcText('. ') + _lcText(_lcAt(v_it, const ['name'])) + _lcText(' ¥') + _lcText(_lcAt(v_it, const ['price'])))),
                            style: TextStyle(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in _lcList(s_names)) Text('• ' + _lcText(item), style: TextStyle(height: 1.75)),
                    ],
                  ),
                  Text(
                    _lcText((_lcText('共 ') + _lcText(LcAppState.cartCount) + _lcText(' 件'))),
                    style: TextStyle(height: 1.5),
                  ),
                  Text(
                    _lcText((_lcText('来过 ') + _lcText(LcAppState.visits) + _lcText(' 次'))),
                    style: TextStyle(height: 1.5),
                  ),
                  FilledButton(
                    onPressed: () => _lcGoTo(context, LowcodePage()),
                    style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('去购物车'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}

class LowcodePage extends StatefulWidget {
  const LowcodePage({super.key});

  @override
  State<LowcodePage> createState() => LowcodePageState();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class LowcodePageState extends State<LowcodePage> {
  Object? s_user = '本页的名字';
  final _lcChanged = ValueNotifier<int>(0);

  /// 改状态都走这里：`update(() => s_xxx = 新值)`。
  void update(void Function() change) {
    setState(change);
    _lcChanged.value++;
  }

  void _lcOnApp() {
    if (mounted) update(() {});
  }

  @override
  void initState() {
    super.initState();
    LcAppState.changed.addListener(_lcOnApp);
  }

  @override
  void dispose() {
    LcAppState.changed.removeListener(_lcOnApp);
    _lcChanged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Color(0xFFFFFFFF),
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
                  Text(
                    _lcText(s_user),
                    style: TextStyle(height: 1.5),
                  ),
                  Text(
                    _lcText((_lcText('共 ') + _lcText(LcAppState.cartCount) + _lcText(' 件'))),
                    style: TextStyle(height: 1.5),
                  ),
                  Text(
                    _lcText((_lcText('来过 ') + _lcText(LcAppState.visits) + _lcText(' 次'))),
                    style: TextStyle(height: 1.5),
                  ),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('记一次'),
                  ),
                  FilledButton(
                    onPressed: () => _lcGoTo(context, BindHomePage()),
                    style: FilledButton.styleFrom(padding: EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: Text('回首页'),
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

/// 跨页共用的状态。改它：`LcAppState.update(() => LcAppState.xxx = 新值)`，开着的页面都跟着变。
abstract final class LcAppState {
  static Object? user = '小塔塔';
  static Object? cart = <Object?>[<String, Object?>{'id': 'a', 'name': '苹果', 'price': 3}, <String, Object?>{'id': 'b', 'name': '香蕉', 'price': 2}];
  static Object? visits = 0;
  static Object? get cartCount => _lcLen(LcAppState.cart);

  static final changed = ValueNotifier<int>(0);

  static void update(void Function() change) {
    change();
    changed.value++;
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

/// 当成列表用：不是列表的（还没取到数据、填错了）当成空列表。
List<Object?> _lcList(Object? v) => v is List ? v : const [];

/// 列表有几项。
int _lcLen(Object? v) => v is List ? v.length : 0;

/// 记录里一格一格往下取；取不到是 null。
Object? _lcAt(Object? v, List<String> path) {
  for (final p in path) {
    final i = int.tryParse(p);
    v = v is Map ? v[p] : (v is List && i != null && i >= 0 && i < v.length ? v[i] : null);
  }
  return v;
}

/// `120px` / 120 → 120；认不出来是 null。
double? _lcPxOrNull(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final t = _lcText(v).trim();
  final d = double.tryParse(t.endsWith('px') ? t.substring(0, t.length - 2) : t);
  return d != null && d.isFinite ? d : null;
}
