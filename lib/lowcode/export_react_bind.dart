/// React 导出里的状态与绑定（第 5 期）。只有用了绑定的页面才走这里。
///
/// 写法（对着 React 官方文档核对过的记在 docs/api-notes.md）：
/// - 页面级状态沿用原来的办法：`lcVars`（useRef 里的普通对象）+ 写完调用 `lcRefresh()` 重画；界面里直接读 `lcVars.x`。
/// - 派生值是 `lcDerived` 里的小函数，读的时候现算（这一版不记缓存：每次重画各算一遍）。
/// - 项目级状态在共用文件 `lc-state.js` 里：一个普通对象 `lcShared` + 订阅；页面用 `useSyncExternalStore` 订它，
///   谁改了（改完调用 `lcSharedChanged()`），所有订着的页面都重画。
/// - JSX 里：文字和属性直接写式子、显示条件写行内 `display`、存在条件 `条件 && (…)`、重复 `.map()` + `key`、
///   类名开关拼 className、样式进行内 style、双向 `value` / `checked` + `onChange`。
library;

import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_vue_bind.dart' show kLcStateFile, lcLocalAlias;
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/model.dart';

String _member(String object, String name) => isJsIdentifier(name) ? '$object.$name' : '$object[${jsString(name)}]';

/// React 的 `lc-state.js`。
String lcReactStateFile(LcBindPlan plan) => [
  '// $kExportHeader',
  '// 项目级状态：所有页面共用这一份（换页不会丢；刷新网页会回到初值）。',
  '// 它是组件外面的一个普通对象；页面用 useSyncExternalStore(lcSubscribe, lcSnapshot, lcSnapshot) 订着它。',
  '// 改了 lcShared 里的东西以后调用 lcSharedChanged()，订着的页面才会重画。',
  'export const lcShared = {',
  for (final s in plan.plain)
    if (s.project) '  ${isJsIdentifier(s.name) ? s.name : '[${jsString(s.name)}]'}: ${lcInitialLiteral(s.variable)},',
  '};',
  '',
  'const lcListeners = new Set();',
  'let lcVersion = 0;',
  '',
  'export function lcSharedChanged() {',
  '  lcVersion++;',
  '  lcListeners.forEach((f) => f());',
  '}',
  '',
  'export function lcSubscribe(f) {',
  '  lcListeners.add(f);',
  '  return () => lcListeners.delete(f);',
  '}',
  '',
  'export function lcSnapshot() {',
  '  return lcVersion;',
  '}',
  '',
].join('\n');

/// 一个“重复”在 JSX 里要用的几样。
class LcReactRepeat {
  const LcReactRepeat(this.list, this.item, this.index, this.empty);
  final String list;
  final String item;
  final String index;
  final String? empty;
}

class LcReactBind {
  LcReactBind(this.plan);
  final LcBindPlan plan;
  final Map<String, String> _localOf = {};
  final List<Map<String, String>> _frames = [];
  final Map<LcNode, String> _key = Map.identity();

  JsExpr? _resolve(String name) {
    final local = _localOf[name];
    if (local != null) return JsExpr(local, LcType.any);
    final s = plan.state(name);
    return s == null ? null : JsExpr(read(name)!, lcStateJsType(s.variable));
  }

  /// 读一个状态的写法；没有这个状态返回 null。
  String? read(String name) {
    final s = plan.state(name);
    if (s == null) return null;
    if (s.variable.isDerived) return '${_member('lcDerived', name)}()';
    return _member(s.project ? 'lcShared' : 'lcVars', name);
  }

  /// 写一个状态的几句代码（派生值不能写）。
  List<String> write(String name, String valueJs) {
    final s = plan.state(name);
    if (s == null || s.variable.isDerived) return ['// 跳过：${jsComment('$name 是派生值，算出来的，不能改')}'];
    return s.project ? ['${_member('lcShared', name)} = $valueJs;', 'lcSharedChanged();'] : ['${_member('lcVars', name)} = $valueJs;', 'lcRefresh();'];
  }

  String code(Object? e, {bool text = false, bool flag = false}) {
    var x = lcBindJs(e, _resolve);
    if (text) x = lcBindText(x);
    if (flag) x = lcBindBool(x);
    return x.code;
  }

  void _rescope() {
    _localOf.clear();
    for (final f in _frames) {
      _localOf.addAll(f);
    }
  }

  /// 进一个节点；设了“重复”的返回它的几样东西（列表按外面的名字算）。
  LcReactRepeat? open(LcNode n) {
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    if (rep == null) return null;
    final list = 'lcList(${code(rep.list)})';
    final item = lcLocalAlias(rep.item), index = lcLocalAlias(rep.index);
    _frames.add({rep.item: item, rep.index: index});
    _rescope();
    _key[n] = rep.key == null ? index : code(rep.key);
    return LcReactRepeat(list, item, index, rep.empty);
  }

  void close(LcNode n) {
    if (lcCanWrapBind(n) && lcRepeatOf(n) != null) {
      _frames.removeLast();
      _rescope();
    }
  }

  /// 重复出来的每一份的 key（没设重复是 null）。
  String? keyOf(LcNode n) => _key[n];

  /// 存在条件（没设是 null）。
  String? renderCond(LcNode n) {
    final e = lcCanWrapBind(n) ? lcRenderIfExpr(n) : null;
    return e == null ? null : code(e, flag: true);
  }

  /// 显示条件（没设是 null）。
  String? showCond(LcNode n) {
    final e = lcCanWrapBind(n) ? lcShowIfExpr(n) : null;
    return e == null ? null : code(e, flag: true);
  }

  /// className 后面要拼的那一段（没有类名开关是空串）：` + (条件 ? " 名字" : "")`。
  String classTail(LcNode n) => [
    if (lcCanWrapBind(n))
      for (final c in lcClassIfOf(n)) ' + (${code(c.when, flag: true)} ? " ${c.name}" : "")',
  ].join();

  /// 行内样式的条目。
  List<String> styleEntries(LcNode n) => [
    if (lcCanWrapBind(n))
      for (final e in lcStyleBinds(n).entries) '${lcCssCamel(e.key)}: ${code(e.value, text: true)} || undefined',
  ];

  /// 这个属性绑了的话，JSX 里的式子；没绑返回 null。
  String? value(LcNode n, String prop) {
    final spec = lcBindable(n.type, prop);
    final e = lcDataExpr(n, prop);
    if (spec == null || e == null) return null;
    final c = code(e, text: spec.type == 'text', flag: spec.type == 'bool');
    return spec.type == 'list' ? 'lcList($c)' : c;
  }

  /// 双向绑到的状态（绑不上是 null）。
  String? modelName(LcNode n) {
    final name = lcModelOf(n);
    final s = name == null ? null : plan.state(name);
    if (name == null || s == null || lcModelProp(n.type) == null || s.variable.isDerived || _localOf.containsKey(name)) return null;
    return name;
  }

  /// 把控件里的新值写回状态的那几句（[valueJs] 是新值的式子），连成一行。
  String modelSet(String name, String valueJs) {
    final number = plan.state(name)?.variable.type == 'number';
    return write(name, number ? 'lcNum($valueJs)' : valueJs).join(' ');
  }

  /// 第 3 版组件的元素树：绑了的文字换成式子，禁用 / 提示文字 / 双向落到里面真正的控件上。
  void markEl(LcEl el, LcNode n) {
    final disabled = value(n, 'disabled'), placeholder = value(n, 'placeholder');
    final model = modelName(n);
    lcVisitEl(el, (e) {
      final prop = lcSentinelProp(e.text);
      if (prop != null) e.rawText = '{${value(n, prop)}}';
      if (!lcIsControlEl(e)) return;
      if (disabled != null) {
        e.attrs.remove('disabled');
        e.rawAttrs.add(' disabled={$disabled}');
      }
      if (placeholder != null && e.attrs.containsKey('placeholder')) {
        e.attrs.remove('placeholder');
        e.rawAttrs.add(' placeholder={$placeholder}');
      }
      if (model == null) return;
      e.attrs
        ..remove('@value')
        ..remove('@checked');
      final r = read(model)!;
      if (e.attrs['type'] == 'radio') {
        final v = jsString(e.attrs['value'] ?? '');
        e.rawAttrs.add(' checked={lcText($r) === $v} onChange={() => { ${modelSet(model, v)} }}');
        // 用了双向以后，“点一个取消同组别的”由状态管，原来那句直接改元素的不要了。
        e.on.remove('change');
      } else if (e.attrs['type'] == 'checkbox') {
        e.rawAttrs.add(' checked={!!$r} onChange={(event) => { ${modelSet(model, 'event.target.checked')} }}');
      } else {
        e.rawAttrs.add(' value={lcText($r)} onChange={(event) => { ${modelSet(model, 'event.target.value')} }}');
      }
    });
  }
}

/// React 共用文件的名字（和 Vue 的一样）。
const String kLcReactStateFile = kLcStateFile;
