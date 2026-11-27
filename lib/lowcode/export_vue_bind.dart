/// Vue 3 导出里的状态与绑定（第 5 期）。只有用了绑定的页面才走这里。
///
/// 写法（对着 Vue 官方文档核对过的记在 docs/api-notes.md）：
/// - 页面级状态是 `ref`，派生值是 `computed`；项目级状态放在共用文件 `lc-state.js` 的一个 `reactive` 对象里，各页 import 同一份。
/// - 模板里：文字 `{{ }}`、属性 `:名字`、显示条件 `v-show`、存在条件 `v-if`、重复 `v-for` + `:key`、
///   类名开关 `:class`、样式 `:style`、双向 `v-model`。
/// - 模板里**不直接写式子**：每个绑定的式子是脚本里的一个小函数（`lcB1()`…），模板里只调用它。
///   这样式子里的引号、尖括号、花括号都待在脚本里，不会把模板截断或被当成模板语法再解析。
library;

import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/model.dart';

/// 项目级状态的共用文件（Vue / React 都叫这个名字，内容不一样）。
const String kLcStateFile = 'lc-state.js';

/// 重复带出来的名字在代码里叫什么（撞了保留字的加一个下划线）。
String lcLocalAlias(String name) => isJsBindingName(name) ? name : '${name}_';

String _member(String object, String name) => isJsIdentifier(name) ? '$object.$name' : '$object[${jsString(name)}]';

/// Vue 的 `lc-state.js`。
String lcVueStateFile(LcBindPlan plan) => [
  '// $kExportHeader',
  '// 项目级状态：所有页面共用这一份（各页 import 的是同一个对象，换页不会丢；刷新网页会回到初值）。',
  'import { reactive } from "vue";',
  '',
  'export const lcShared = reactive({',
  for (final s in plan.plain)
    if (s.project) '  ${isJsIdentifier(s.name) ? s.name : '[${jsString(s.name)}]'}: ${lcInitialLiteral(s.variable)},',
  '});',
  '',
].join('\n');

class LcVueBind {
  LcVueBind(this.plan, this.varNames);
  final LcBindPlan plan;

  /// 状态名 → 脚本里的名字（页面级的 ref、所有派生的 computed）。项目级的普通状态不在里面（从 lcShared 读）。
  final Map<String, String> varNames;

  /// 脚本里要写的小函数（每个几行）。
  final List<String> functions = [];
  var _count = 0;

  /// 现在所在的“重复”带出来的名字（代码里的叫法），从外到里。
  final List<String> _scope = [];
  final Map<String, String> _localOf = {};
  final List<Map<String, String>> _frames = [];
  final Map<LcNode, String> _forAttr = Map.identity();

  JsExpr? _resolve(String name) {
    final local = _localOf[name];
    if (local != null) return JsExpr(local, LcType.any);
    final s = plan.state(name);
    if (s == null) return null;
    final v = s.variable;
    return s.project && !v.isDerived ? JsExpr(_member('lcShared', name), lcStateJsType(v)) : JsExpr('${varNames[name]}.value', lcStateJsType(v));
  }

  /// 积木里读写一个状态的写法（给 VueJsTarget 用）。项目级的普通状态返回 `lcShared.x`，别的返回 null（走原来的 ref 写法）。
  String? sharedRef(String name) {
    final s = plan.state(name);
    return s != null && s.project && !s.variable.isDerived ? _member('lcShared', name) : null;
  }

  /// 现在套着的“重复”带出来的名字（给要带着这一项去调用的函数当参数）。
  String get scopeParams => _scope.join(', ');

  /// 一个式子直接翻成代码（按现在的作用域）。
  String code(Object? e) => lcBindJs(e, _resolve).code;

  /// 组件实例的属性绑了式子：登记成小函数，返回模板里的调用。[type]＝属性的类型。
  String propCall(LcNode n, String label, Object? e, String type) => _call(n, label, e, text: type == 'text' || type == 'color', flag: type == 'bool', list: type == 'list');

  /// 这个名字是一个能直接写的状态（不是派生值、不是“重复”带出来的）：返回模板里的写法；不是返回 null。
  String? writableRef(String name) {
    final s = plan.state(name);
    if (s == null || s.variable.isDerived || _localOf.containsKey(name)) return null;
    return (s.project ? _member('lcShared', name) : varNames[name])?.replaceAll('"', "'");
  }

  /// 派生值的算法（写成 computed 的函数体）。
  String derivedCode(Object? expr) => lcBindJs(expr, _resolve).code;

  /// 把一个式子登记成脚本里的小函数，返回模板里的调用。
  String _call(LcNode n, String what, Object? e, {bool text = false, bool flag = false, bool list = false}) {
    var x = lcBindJs(e, _resolve);
    if (text) x = lcBindText(x);
    if (flag) x = lcBindBool(x);
    final code = list ? 'lcList(${x.code})' : x.code;
    final name = 'lcB${++_count}';
    final params = _scope.join(', ');
    functions
      ..add('// ${jsComment('${n.name.isNotEmpty ? n.name : n.spec.label}（${n.id}）的$what')}')
      ..add('function $name($params) {')
      ..add('  return $code;')
      ..add('}');
    return '$name($params)';
  }

  /// 进一个节点：设了“重复”的先把列表（按外面的名字算）定下来，再把这一项 / 序号加进作用域。返回要先写出来的几行。
  List<String> open(LcNode n) {
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    if (rep == null) return const [];
    final list = _call(n, '重复的列表', rep.list, list: true);
    final before = [
      if (rep.empty != null)
        '<p v-if="${_call(n, '列表是不是空的', {
          'e': 'bin',
          'op': '==',
          'l': {'e': 'len', 'x': rep.list},
          'r': {'e': 'num', 'v': 0},
        })}" class="lc-text lc-empty">${_plainText(rep.empty!)}</p>',
    ];
    final item = lcLocalAlias(rep.item), index = lcLocalAlias(rep.index);
    _frames.add({rep.item: item, rep.index: index});
    _rescope();
    final key = rep.key == null ? index : _call(n, '重复的标识', rep.key);
    final render = lcRenderIfExpr(n);
    final loop = ' v-for="($item, $index) in $list" :key="$key"';
    if (render == null) {
      _forAttr[n] = loop;
      return before;
    }
    // 又重复又有存在条件：Vue 里 v-if 和 v-for 不能写在同一个元素上（v-if 先算，拿不到这一项），外面包一层 <template>。
    _forAttr[n] = ' v-if="${_call(n, '存在条件', render, flag: true)}"';
    return [...before, '<template$loop>'];
  }

  /// 出一个节点（和 [open] 成对）。返回要补在后面的几行。
  List<String> close(LcNode n) {
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    if (rep == null) return const [];
    _frames.removeLast();
    _rescope();
    return [if (lcRenderIfExpr(n) != null) '</template>'];
  }

  /// 按现在套着的几层“重复”重算作用域（里层盖住外层的同名）。
  void _rescope() {
    _localOf.clear();
    _scope.clear();
    for (final f in _frames) {
      _localOf.addAll(f);
    }
    _scope.addAll({..._localOf.values});
  }

  String _plainText(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('{', '&#123;').replaceAll('}', '&#125;');

  /// 最外层元素上多出来的属性：重复、存在条件、显示条件、类名开关。
  String wrapAttrs(LcNode n) {
    if (!lcCanWrapBind(n)) return '';
    final b = StringBuffer(_forAttr[n] ?? '');
    final render = lcRenderIfExpr(n);
    if (render != null && lcRepeatOf(n) == null) b.write(' v-if="${_call(n, '存在条件', render, flag: true)}"');
    final show = lcShowIfExpr(n);
    if (show != null) b.write(' v-show="${_call(n, '显示条件', show, flag: true)}"');
    final cls = lcClassIfOf(n);
    if (cls.isNotEmpty) b.write(' :class="{ ${[for (final c in cls) "'${c.name}': ${_call(n, '类名 ${c.name}', c.when, flag: true)}"].join(', ')} }"');
    return b.toString();
  }

  bool hasShow(LcNode n) => lcCanWrapBind(n) && lcShowIfExpr(n) != null;

  /// 样式绑定：`'width': lcB3()` 这样的几条（和别的 :style 条目并在一起写）。
  List<String> styleEntries(LcNode n) => [
    if (lcCanWrapBind(n))
      for (final e in lcStyleBinds(n).entries) "'${e.key}': ${_call(n, '样式 ${e.key}', e.value, text: true)}",
  ];

  /// 这个属性绑了的话，模板里的调用；没绑返回 null。
  String? value(LcNode n, String prop) {
    final spec = lcBindable(n.type, prop);
    final e = lcDataExpr(n, prop);
    if (spec == null || e == null) return null;
    return _call(n, spec.label, e, text: spec.type == 'text', flag: spec.type == 'bool', list: spec.type == 'list');
  }

  /// 双向：` v-model="count"`；没绑、绑不上返回空串。
  String model(LcNode n) {
    final name = lcModelOf(n);
    final s = name == null ? null : plan.state(name);
    if (name == null || s == null || lcModelProp(n.type) == null || s.variable.isDerived || _localOf.containsKey(name)) return '';
    final ref = s.project ? _member('lcShared', name) : varNames[name];
    return ' v-model${s.variable.type == 'number' ? '.number' : ''}="${ref!.replaceAll('"', "'")}"';
  }

  /// 第 3 版组件的元素树：绑了的文字换成插值，禁用 / 提示文字 / 双向落到里面真正的控件上。
  void markEl(LcEl el, LcNode n) {
    final disabled = value(n, 'disabled'), placeholder = value(n, 'placeholder'), vModel = model(n);
    lcVisitEl(el, (e) {
      final prop = lcSentinelProp(e.text);
      if (prop != null) e.rawText = '{{ ${value(n, prop)} }}';
      if (!lcIsControlEl(e)) return;
      if (disabled != null) {
        e.attrs.remove('disabled');
        e.rawAttrs.add(' :disabled="$disabled"');
      }
      if (placeholder != null && e.attrs.containsKey('placeholder')) {
        e.attrs.remove('placeholder');
        e.rawAttrs.add(' :placeholder="$placeholder"');
      }
      if (vModel.isNotEmpty) {
        e.attrs
          ..remove('@value')
          ..remove('@checked');
        e.rawAttrs.add(vModel);
      }
    });
  }
}
