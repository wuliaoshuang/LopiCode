/// 纯网页导出：“重复”出来的每一份里，控件的事件处理读得到“这一项 / 第几个”（第四轮 B7）。
///
/// 以前：重复出来的每一份共用一个处理函数，处理里读“这一项”读到的是空的。现在：
/// - 每一份元素上记着它那一份带的东西（`el.lcS`，就是绑定用的那个 `s`）；
/// - 处理函数开头 `const lcS = lcScopeAt(event);`——从点的地方顺着往上找到那一份；
/// - 处理里读“这一项 / 第几个”（连同往下取的 `item.name`）翻成 `lcS.item?.["name"]`。
/// 只有处理里真读到了重复带出的名字才多这几句；别的页面导出一个字不变。新的页面逻辑走它自己的办法（`el.lcAt`），不经过这里。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 运行时多出来的小函数。
const String kLcScopeAtJs = '''
// 事件发生在“重复”出来的哪一份里：顺着往上找到那一份，交回它带的“这一项 / 第几个”。
function lcScopeAt(event) {
  for (let el = event && event.target; el; el = el.parentNode) {
    if (el.lcS) return el.lcS;
  }
  return Object.create(null);
}''';

/// 这棵树里：在“重复”里面的控件 id → 它读得到的重复带出的名字。
Map<String, Set<String>> lcRepeatScopes(LcNode tree) {
  final out = <String, Set<String>>{};
  void walk(LcNode n, Set<String> locals, int depth) {
    if (depth > 64) return;
    var scope = locals;
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    if (rep != null) scope = {...locals, rep.item, rep.index};
    if (scope.isNotEmpty) out[n.id] = scope;
    for (final c in n.children) {
      walk(c, scope, depth + 1);
    }
  }

  walk(tree, const {}, 0);
  return out;
}

/// 读重复带出的名字时用的写法：别的照普通网页的来。
class LcScopedDomTarget extends DomJsTarget {
  LcScopedDomTarget(this.code);

  /// 假名字 → 那句 JS。
  final Map<String, String> code;

  @override
  String readVar(LcVariable v) => code[v.name] ?? super.readVar(v);
}

/// 一条处理改写好以后：[body] 里读重复带出的名字的地方换成了假名字，[vars] 是假名字对应的“状态”，[code] 是它们各自的 JS。
class LcScopedBody {
  LcScopedBody(this.body, this.vars, this.code);
  final List<LcBlock> body;
  final Map<String, LcVariable> vars;
  final Map<String, String> code;
  bool get used => code.isNotEmpty;
}

String _js(String name, List<String> path) => '${isJsIdentifier(name) ? 'lcS.$name' : 'lcS[${jsString(name)}]'}${[for (final p in path) '?.[${jsString(p)}]'].join()}';

/// 把 [body]（不改它，交回拷出来的一份）里读 [locals] 的地方换掉。
LcScopedBody lcScopedBody(List<LcBlock> body, Set<String> locals) {
  final vars = <String, LcVariable>{};
  final code = <String, String>{};
  Object? swap(Object? v, int depth) {
    if (depth > 64) return v;
    if (v is Map) {
      final name = v['name'];
      if (v['e'] == 'var' && name is String && locals.contains(name)) {
        final path = lcPathOf(v['path']);
        final fake = '\u0001${jsonEncode([name, path])}';
        // 类型写成“记录”：翻译时不当成文字 / 数字 / 是否（不知道这一项是什么）。
        vars.putIfAbsent(fake, () => LcVariable(name: fake, type: 'record'));
        code[fake] = _js(name, path);
        return <String, dynamic>{'e': 'var', 'name': fake};
      }
      return <String, dynamic>{for (final e in v.entries) '${e.key}': swap(e.value, depth + 1)};
    }
    return v is List ? [for (final x in v) swap(x, depth + 1)] : v;
  }

  List<LcBlock> all(List<LcBlock> list) => [
    for (final b in list)
      () {
        final c = b.clone();
        for (final k in c.args.keys.toList()) {
          c.args[k] = swap(c.args[k], 0);
        }
        final inner = all(c.body), other = all(c.orElse);
        c.body
          ..clear()
          ..addAll(inner);
        c.orElse
          ..clear()
          ..addAll(other);
        return c;
      }(),
  ];

  return LcScopedBody(all(body), vars, code);
}
