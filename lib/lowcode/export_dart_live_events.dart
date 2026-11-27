/// Flutter 导出“会动的那一路”：**组件事件接的动作**怎么写进生成的代码（第四轮 B6）。
///
/// 只管一种处理：组件里的控件往外发事件、页面上的实例给那个事件接了动作——摊开实例时合成出来的那几条
/// （export_live_doc.dart 的 [lcSynthHandlerIds]）。页面自己的积木逻辑 Flutter 这一份一直不导出，这里不碰。
///
/// 认得的积木（就是组件事件上能点出来的那几样快捷动作，加一个“如果”）：
/// - 设置状态、状态加上：`update(() => s_xxx = …)`；
/// - 去页面：`_lcGoTo(context, 那一页())`（多页面的项目才有）；
/// - 弹提示：`_lcAlert(context, …)`（一个只有“知道了”的对话框）；
/// - 打开弹窗（改控件 某个弹窗 的 显示 改成 是）：调那个弹窗的 `showDialog_xxx(context)`；
/// - 如果 / 否则。
/// 一条处理里只要有一块不认得的（打开网址要第三方包、关闭弹窗、等一会儿、要数据、新页面逻辑的转发记号…），
/// 整条不导出，文件开头记一句，按钮照旧是空的 `onPressed: () {}`。
///
/// 代码是写在那个控件自己身上的（不是另起一个函数），所以控件在“重复”里时，动作里读“重复带出的那一项 / 第几个”读得到。
library;

import 'package:lopicode/lowcode/export_dart_v3.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

String _ind(int n) => '  ' * n;

/// 弹提示用的小函数（用到才带进导出文件；见 export_dart_live_runtime.dart 的表）。
const String kDartLiveAlert = r'''
/// 弹一个提示（和网页上的 alert 一个意思：一段字、一个“知道了”）。
void _lcAlert(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('知道了'))],
    ),
  );
}
''';

class DartLiveEvents {
  DartLiveEvents({required this.handlers, required this.expr, required this.state, required this.isPageState, required this.read, required this.dialogs, required this.notes});

  /// 这一页里合成出来的处理：控件 id → 它的几条处理（按先后）。
  final Map<String, List<LcHandler>> handlers;

  /// 一个值式子翻成一句 Dart（会认“重复”里的名字）。
  final String Function(Object? e) expr;

  /// 状态的声明；没有这个状态返回 null。
  final LcVariable? Function(String name) state;
  final bool Function(String name) isPageState;

  /// 读一个状态的那句 Dart。
  final String? Function(String name) read;

  /// 这一页的弹窗：id → 节点。
  final Map<String, LcNode> dialogs;
  final Set<String> notes;

  /// 这一份导出里有没有真的写出过动作（文件开头的说明用）。
  bool wrote = false;

  String? _assign(String name, String value) {
    final v = state(name);
    if (v == null || v.isDerived) return null;
    final put = switch (v.type) {
      'number' => '_lcNum($value)',
      'text' => '_lcText($value)',
      'bool' => '_lcBool($value)',
      _ => value,
    };
    return isPageState(name) ? 'update(() => ${read(name)} = $put)' : 'LcAppState.update(() => ${read(name)} = $put)';
  }

  /// 一块积木翻成一句（不带分号的块自己带花括号）；不认得返回 null。
  String? _stmt(LcBlock b, int depth) {
    if (depth > 16) return null;
    switch (b.op) {
      case 'setVar':
        final name = b.args['name'];
        final code = name is String ? _assign(name, expr(b.args['value'])) : null;
        return code == null ? null : '$code;';
      case 'changeVar':
        final name = b.args['name'];
        final now = name is String ? read(name) : null;
        final code = now == null ? null : _assign(name as String, '(_lcNum($now) + _lcNum(${expr(b.args['by'])}))');
        return code == null ? null : '$code;';
      case kLcGoPageOp:
        final id = b.args['page'];
        final to = id is String ? dartPageJumps?.classOf(id) : null;
        return to == null ? null : '_lcGoTo(context, const $to());';
      case 'alert':
        return '_lcAlert(context, _lcText(${expr(b.args['message'])}));';
      case 'setProp':
        final d = dialogs[b.args['node']];
        final v = b.args['value'];
        if (d == null || b.args['prop'] != 'visible' || v is! Map || v['e'] != 'bool' || v['v'] != true) return null;
        return '${dartDialogMethod(d)}(context);';
      case 'if':
        final yes = _block(b.body, depth + 1), no = _block(b.orElse, depth + 1);
        if (yes == null || no == null) return null;
        return 'if (_lcBool(${expr(b.args['cond'])})) { $yes }${b.orElse.isEmpty ? '' : ' else { $no }'}';
    }
    return null;
  }

  String? _block(List<LcBlock> body, int depth) {
    final out = <String>[];
    for (final b in body) {
      final s = _stmt(b, depth);
      if (s == null) return null;
      out.add(s);
    }
    return out.join(' ');
  }

  /// [n] 这个控件的 [event]（click / input）要做的事，写成几句 Dart（用空格隔开）；没有、或者导不出返回 null。
  String? _body(LcNode n, String event) {
    final out = <String>[];
    for (final h in handlers[n.id] ?? const <LcHandler>[]) {
      if (h.event != event || h.body.isEmpty) continue;
      // “点击时去页面”正好一块的那种，生成器原来就接好了（export_dart.dart 的 _nodeJump），这里不再写第二遍。
      if (event == 'click' && h.body.length == 1 && h.body.single.op == kLcGoPageOp && dartPageJumps?.clickPage(n) != null) continue;
      final code = _block(h.body, 0);
      if (code == null) {
        notes.add('有的组件事件接的动作（Flutter 这边导出的是：设置状态、状态加上、去页面、弹提示、打开弹窗、如果。打开网址要另装第三方包、关闭弹窗、等一会儿、向网址要数据、改控件别的属性，以及新的页面逻辑里接的事件都没有导出，那个控件点了没反应）。');
        continue;
      }
      out.add(code);
    }
    return out.isEmpty ? null : out.join(' ');
  }

  static final RegExp _wrapped = RegExp(r'^(Expanded|Flexible)\(\n(\s*)child: ');
  static final RegExp _changedArrow = RegExp(r'onChanged: \(value\) => ([^\n]*),\n');
  static final RegExp _fieldHead = RegExp(r'\b(TextField|TextFormField)\(\n( *)');

  /// 把这个控件的动作接到已经生成好的 [code] 上。
  String attach(LcNode n, String code, int indent) {
    if (handlers[n.id] == null) return code;
    var out = code;
    final click = _body(n, 'click');
    if (click != null) {
      final fn = '() { $click }';
      if (n.type == 'button') {
        if (out.contains('onPressed: () {}')) {
          out = out.replaceFirst('onPressed: () {}', 'onPressed: $fn');
          wrote = true;
        }
        // 禁用着的按钮（onPressed: null）本来就点不动，不接。
      } else {
        final m = _wrapped.firstMatch(out);
        final tail = ',\n${_ind(indent)})';
        if (m != null && out.endsWith(tail)) {
          final inner = out.substring(m.end, out.length - tail.length);
          out = '${m[1]}(\n${m[2]}child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: $fn, child: $inner)$tail';
        } else {
          out = 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: $fn, child: $out)';
        }
        wrote = true;
      }
    }
    final input = _body(n, 'input');
    if (input != null) {
      final arrow = _changedArrow.firstMatch(out);
      final head = n.type == 'input' || n.type == 'textarea' ? _fieldHead.firstMatch(out) : null;
      if (out.contains('onChanged: (value) {}')) {
        out = out.replaceFirst('onChanged: (value) {}', 'onChanged: (value) { $input }');
        wrote = true;
      } else if (arrow != null) {
        // 先把值写回状态，再做接的动作（动作里读到的是新值）。
        out = out.replaceRange(arrow.start, arrow.end, 'onChanged: (value) { ${arrow[1]}; $input },\n');
        wrote = true;
      } else if (head != null && !out.contains('onChanged:')) {
        out = out.replaceRange(head.end, head.end, 'onChanged: (value) { $input },\n${head[2]}');
        wrote = true;
      } else {
        notes.add('有的组件事件是“内容改了”时发的，而那个控件在 Flutter 这边没有现成的“改了”的口子（只接了输入框、多行输入框、开关、勾选框），那一条没有导出。');
      }
    }
    return out;
  }
}

/// 样式里只有 Flutter 的生成器不认、但能在外面补一下的两样（第四轮 B6）：竖着能滚、字带下划线。
String dartLiveExtras(LcNode n, String code, int indent, Set<String> notes) {
  if (n.style.isEmpty) return code;
  var out = code;
  final line = n.style['text-decoration-line'] ?? n.style['text-decoration'] ?? '';
  if (n.type == 'text' && line.contains('underline')) {
    out = out.replaceFirstMapped(RegExp(r'style: (const )?TextStyle\('), (m) => '${m[0]}decoration: TextDecoration.underline, ');
  }
  final oy = n.style['overflow-y']?.trim(), ox = n.style['overflow-x']?.trim();
  bool scrolls(String? v) => v == 'auto' || v == 'scroll';
  if (n.isContainer && n.type != 'page' && (scrolls(oy) || scrolls(ox))) {
    final tail = ',\n${_ind(indent)})';
    final at = out.lastIndexOf('\n${_ind(indent + 1)}child: ');
    final column = n.type != 'row';
    if (scrolls(oy) && column && at >= 0 && out.endsWith(tail) && out.startsWith('Container(')) {
      final start = at + '\n${_ind(indent + 1)}child: '.length;
      final inner = out.substring(start, out.length - tail.length);
      out = '${out.substring(0, start)}SingleChildScrollView(child: $inner)$tail';
    } else {
      notes.add('有的能滚的区域（Flutter 这边导出的是“竖着排、竖着滚”的那种；横着滚的、排成一行的没有导出成能滚的：一行里的东西会被压在一屏宽里）。');
    }
  }
  return out;
}
