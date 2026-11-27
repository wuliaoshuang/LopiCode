/// 普通网页导出：用了状态与绑定的页面的 logic.js（第 5 期）。没用绑定的页面不走这里（logic_js.dart 原样）。
///
/// 写出来的脚本：`lcData`（普通状态的现值）、`lcDerived`（派生值的算法）、小工具、`state`（带读写器，积木翻出来的
/// `state.x = …` 原样能用）、事件处理、`lcBinds`（每个控件上的绑定各是一句箭头函数）、`lcStart`。
/// 运行代码在 export_html_bind_runtime.dart。
library;

import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_html_bind_runtime.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

const String _header = '''// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
//
// 怎么读这份脚本：
// - 这一页用了“状态与数据绑定”。状态都从 state 读写（state.名字）；每个“处理”是下面的一个函数；最后的 lcStart 把它们挂到控件上。
// - 状态改了以后，绑了它的地方（lcBinds 里列着）会自己跟着变，不用再拿“改控件”积木去改。
// - 项目级状态（lcSharedNames 里列着）跨页共用：放在浏览器的 sessionStorage 里，换页还在，关掉标签页就没了。
// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）；除以 0 的结果也当 0。要拼文字用“拼成文字”。
// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。
"use strict";
''';

String _key(String name) => isJsIdentifier(name) ? name : '[${jsString(name)}]';
String _stateRead(String name) => isJsIdentifier(name) ? 'state.$name' : 'state[${jsString(name)}]';

/// 网页里“一个名字怎么读”：重复带出来的从 `s` 里读，状态从 `state` 里读。
LcBindResolve lcHtmlResolve(LcBindPlan plan, Set<String> locals) => (name) {
  if (locals.contains(name)) return JsExpr(isJsIdentifier(name) ? 's.$name' : 's[${jsString(name)}]', LcType.any);
  final s = plan.state(name);
  return s == null ? null : JsExpr(_stateRead(name), lcStateJsType(s.variable));
};

/// 这一页所有绑定的清单（`lcBinds` 的每一项是几行代码）。[notes]：导出说明。
List<List<String>> lcHtmlBindEntries(LcBindPlan plan, LcNode tree, List<String> notes) {
  final out = <List<String>>[];
  var repeatedHandlers = false;
  final handled = {
    for (final h in plan.doc.logic.handlers)
      if (h.target != null) h.target!,
  };
  void walk(LcNode n, String? owner, Set<String> locals, int depth) {
    if (depth > 64) return;
    var inner = owner;
    var scope = locals;
    if (lcHasBindings(n) && isSafeNodeId(n.id)) {
      String fn(Object? e, Set<String> names, {bool text = false, bool flag = false}) {
        var x = lcBindJs(e, lcHtmlResolve(plan, names));
        if (text) x = lcBindText(x);
        if (flag) x = lcBindBool(x);
        return '(s) => ${x.code}';
      }

      final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
      final render = lcCanWrapBind(n) ? lcRenderIfExpr(n) : null;
      if (rep != null) {
        scope = {...locals, rep.item, rep.index};
        inner = n.id;
        out.add([
          'id: ${jsString(n.id)},',
          if (owner != null) 'in: ${jsString(owner)},',
          'each: ${fn(rep.list, locals)},',
          'item: ${jsString(rep.item)},',
          'index: ${jsString(rep.index)},',
          if (rep.key != null) 'key: ${fn(rep.key, scope)},',
          if (render != null) 'only: ${fn(render, scope, flag: true)},',
          if (rep.empty != null) 'empty: ${jsString(rep.empty!)},',
        ]);
      }
      final lines = <String>[];
      final show = lcCanWrapBind(n) ? lcShowIfExpr(n) : null;
      if (render != null && rep == null) lines.add('when: ${fn(render, scope, flag: true)},');
      if (show != null) lines.add('show: ${fn(show, scope, flag: true)},');
      final parts = <String>[], attrs = <String>[];
      for (final prop in lcBoundProps(n)) {
        final spec = lcBindable(n.type, prop);
        final e = lcDataExpr(n, prop);
        if (spec == null || e == null) continue;
        if (spec.type == 'list') {
          lines.add('items: ${fn(e, scope)},');
        } else if (spec.type == 'bool') {
          attrs.add('$prop: ${fn(e, scope, flag: true)},');
        } else if (prop == 'text' && (n.type == 'text' || n.type == 'button')) {
          lines.add('text: ${fn(e, scope)},');
        } else if (lcWebV3Types.contains(n.type) && prop != 'placeholder') {
          parts.add('$prop: ${fn(e, scope)},');
        } else {
          attrs.add('$prop: ${fn(e, scope)},');
        }
      }
      if (parts.isNotEmpty) lines.addAll(['parts: {', for (final p in parts) '  $p', '},']);
      if (attrs.isNotEmpty) lines.addAll(['attr: {', for (final a in attrs) '  $a', '},']);
      if (lcCanWrapBind(n)) {
        final cls = lcClassIfOf(n);
        if (cls.isNotEmpty) lines.addAll(['cls: {', for (final c in cls) '  ${jsString(c.name)}: ${fn(c.when, scope, flag: true)},', '},']);
        final styles = lcStyleBinds(n);
        if (styles.isNotEmpty) lines.addAll(['style: {', for (final e in styles.entries) '  ${jsString(e.key)}: ${fn(e.value, scope)},', '},']);
      }
      final model = lcModelOf(n);
      final modelProp = lcModelProp(n.type);
      final target = model == null ? null : plan.state(model);
      if (model != null && modelProp != null && target != null && !target.variable.isDerived && !scope.contains(model)) {
        lines.add('model: { name: ${jsString(model)}, prop: ${jsString(modelProp)}${target.variable.type == 'number' ? ', num: true' : ''} },');
      }
      if (lines.isNotEmpty) out.add(['id: ${jsString(n.id)},', if (inner != null) 'in: ${jsString(inner)},', ...lines]);
    }
    if (inner != null && handled.contains(n.id)) repeatedHandlers = true;
    for (final c in n.children) {
      walk(c, inner, scope, depth + 1);
    }
  }

  walk(tree, null, const {}, 0);
  if (repeatedHandlers) notes.add(kNoteBindRepeatEvents);
  return out;
}

/// 用了绑定的页面的整份脚本。
String exportBoundLogicJs(LcBindPlan plan, LcNode tree, {List<String>? notes}) {
  final doc = plan.doc;
  final logic = doc.logic;
  const target = DomJsTarget();
  final writer = JsLogicWriter(doc, target, lookup: plan.lookup);
  final names = logicHandlerNames(doc);
  final out = StringBuffer(_header)..writeln();

  out.writeln('// 状态现在的值（开始时是初值）');
  out.writeln('const lcData = {');
  for (final s in plan.plain) {
    out.writeln('  ${_key(s.name)}: ${lcInitialLiteral(s.variable)},${s.project ? ' // 项目级' : ''}');
  }
  out.writeln('};');
  out.writeln();
  out.writeln('// 项目级状态的名字（跨页共用）');
  out.writeln(
    'const lcSharedNames = [${[for (final s in plan.plain)
      if (s.project) jsString(s.name)].join(', ')}];',
  );
  out.writeln();
  out.writeln('// 派生值：不存，读的时候按别的状态现算');
  out.writeln('const lcDerived = {');
  for (final s in plan.derived) {
    out.writeln('  ${_key(s.name)}: () => ${lcBindJs(s.variable.derived, lcHtmlResolve(plan, const {})).code},');
  }
  out.writeln('};');
  out.writeln();

  out.writeln('// —— 小工具（每份导出都一样）——');
  for (final block in [lcJsRuntime, lcBindJsRuntime, lcJsDomRuntime.substring(0, lcJsDomRuntime.indexOf('// 给控件挂事件。')), lcJsDelegatedOn, lcJsBindRuntime]) {
    out.writeln(block.trim());
    out.writeln();
  }
  out.writeln('lcLoadShared();');
  out.writeln('const state = lcMakeState();');
  out.writeln();

  final start = <String>[], load = <String>[];
  for (var i = 0; i < logic.handlers.length; i++) {
    final h = logic.handlers[i];
    final name = names[i];
    out.writeln('// ${jsComment(describeHandler(h, doc))}');
    out.writeln('function $name(${h.event == 'load' ? '' : 'event'}) {');
    for (final line in writer.blocks(h.body, event: h.event)) {
      out.writeln('  $line');
    }
    out.writeln('}');
    out.writeln();
    final targetId = h.target;
    final node = targetId == null ? null : doc.find(targetId);
    if (h.event == 'load') {
      load.add('$name();');
    } else if (h.event != 'click' && h.event != 'input') {
      start.add('// $name：${jsComment('不认识的事件 ${h.event}')}，没有挂上');
    } else if (node == null || !isSafeNodeId(node.id)) {
      start.add('// $name：触发它的控件不在页面里，没有挂上');
    } else {
      start.add('lcOn(${jsString(node.id)}, "${h.event}", $name);');
    }
  }

  out.writeln('// 每个控件上的绑定。in＝它在哪个“重复”里面；s＝重复带出来的这一项 / 序号。');
  out.writeln('const lcBinds = [');
  for (final entry in lcHtmlBindEntries(plan, tree, notes ?? [])) {
    out.writeln('  {');
    for (final line in entry) {
      out.writeln('    $line');
    }
    out.writeln('  },');
  }
  out.writeln('];');
  out.writeln();

  out.writeln('// 页面准备好以后：把处理挂到控件上，按现在的状态把界面画一遍，再执行“页面打开时”的处理。');
  out.writeln('function lcStart() {');
  for (final line in [...start, 'lcRender();', ...load]) {
    out.writeln('  $line');
  }
  out.writeln('}');
  out.writeln();
  out.writeln('if (document.readyState === "loading") {');
  out.writeln('  document.addEventListener("DOMContentLoaded", lcStart);');
  out.writeln('} else {');
  out.writeln('  lcStart();');
  out.writeln('}');
  return out.toString();
}

/// 网页里第 3 版组件的元素树上打记号：绑了的文字那一格带 `data-lc-t="控件id:属性"`、文字先写初值；
/// 有禁用 / 提示文字 / 双向绑定时，里面真正的控件带 `data-lc-c`。
void lcHtmlMarkEl(LcEl el, LcNode n, LcNode shown) {
  final needControl = lcModelOf(n) != null || lcBoundProps(n).any((p) => p == 'disabled' || p == 'placeholder');
  lcVisitEl(el, (e) {
    final prop = lcSentinelProp(e.text);
    if (prop != null) {
      e.attrs['data-lc-t'] = '${n.id}:$prop';
      e.text = shown.strProp(prop) ?? '';
    }
    if (needControl && lcIsControlEl(e) && !e.host) e.attrs['data-lc-c'] = '';
  });
}
