/// React 导出：用了第 6 期新东西（事件、变体、自己的状态、定义里的绑定）的自定义组件出成单独的 `.jsx` 文件，
/// 以及页面上怎么用它（第四轮 B4；两种框架共用的那一半在 export_comp_files.dart）。
///
/// 组件文件里：
/// - 属性是函数的参数；每次重画时抄进 `lcVars`（定义里的绑定读的是 `lcVars`）。
///   被里面的输入框双向写的属性：`lcVars` 里那一份由组件自己留着（外面给的值变了才跟上），改了以后调用外面传进来的
///   `onLcUpdate_名字`——页面接了就是双向；页面没接，它在组件里照样能用。
/// - 事件是回调属性 `on事件名`（首字母大写）；带出去的数据包成 [kLcEvtJs] 约定的样子。
/// - 组件自己的状态在 `lcVars` 里（`useRef`，每用一次各有一份），改完调用 `lcRefresh()` 重画。
/// - 变体：每组一个文字属性 `lcv_<组名>`，样式差别是“这个属性等于某个变体名时成立的类名”。
part of 'export_react.dart';

class _LiveAttrs {
  _LiveAttrs(this.attrs, this.bound);
  final String attrs;
  final Set<String> bound;
}

_LiveAttrs _liveInstanceAttrs(_View t, LcComponentPlan plan, LcNode n) {
  final def = plan.def;
  final b = StringBuffer();
  final bound = <String>{};
  final bind = t.bind;
  final models = lcModelProps(def);
  if (bind != null) {
    for (final p in def.props) {
      final e = lcDataExpr(n, p.name);
      final attr = plan.attrs[p.name];
      if (e == null || attr == null) continue;
      bound.add(p.name);
      final c = bind.code(e, text: p.type == 'text' || p.type == 'color', flag: p.type == 'bool');
      b.write(' $attr={${p.type == 'list' ? 'lcList($c)' : c}}');
      final state = lcPlainStateOf(e);
      if (state != null && models.contains(p.name) && bind.writable(state)) b.write(' onLcUpdate_$attr={(v) => { ${bind.write(state, 'v').join(' ')} }}');
    }
  }
  lcInstanceVariants(def, n).forEach((group, name) => b.write(' ${lcVariantProp(group)}="$name"'));
  final marks = lcTakeEventMarks(n);
  final inDef = t.ownerId != null;
  for (final e in lcCompEvents(def)) {
    final mark = marks[e.name];
    final fns = mark == null ? const <String>[] : t.events(mark).values.toList();
    if (fns.isNotEmpty) {
      b.write(' ${lcReactEventAttr(e.name)}={${fns.first}}');
    } else if (inDef) {
      // 套在另一个组件里的实例：它的事件接着往外发（带的数据原样带出去）。
      final out = lcEmitsOf(n)[e.name];
      if (out != null) b.write(' ${lcReactEventAttr(e.name)}={${lcReactEventAttr(out.event)}}');
    }
  }
  return _LiveAttrs(b.toString(), bound);
}

/// 组件文件用的绑定：写“被双向写的属性”时走 `lcOut_名字`（改自己那一份、重画、告诉外面）。
class _CompReactBind extends LcReactBind {
  _CompReactBind(super.plan, this.modelProps);
  final Set<String> modelProps;

  @override
  List<String> write(String name, String valueJs) => modelProps.contains(name) ? ['lcOut_$name($valueJs);'] : super.write(name, valueJs);
}

(String, String) _liveComponent(LcLiveComp live, LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc}) {
  final def = live.def;
  final prefix = lcComponentPrefix(def);
  final bind = _CompReactBind(live.plan, live.modelProps);
  final emitted = <String>{};
  final emitFns = <String>[];
  final emitNames = <String>{};

  Map<String, String> eventsOf(LcNode n) {
    if (n.type == 'component') return const {};
    final out = <String, String>{};
    lcEmitsOf(n).forEach((on, emit) {
      if ((on != 'click' && on != 'input') || !isSafeNodeId(n.id)) return;
      emitted.add(emit.event);
      final scope = bind.scopeNames.join(', ');
      final name = 'lcEmit_${n.id}_$on';
      final attr = on == 'click' ? 'onClick' : (n.type == 'input' ? 'onChange' : 'onInput');
      out[attr] = '((event) => $name(${['event', if (scope.isNotEmpty) scope].join(', ')}))';
      if (!emitNames.add(name)) return;
      final cb = lcReactEventAttr(emit.event);
      final args = [for (final a in live.argsOf(emit)) '${jsString(a.key)}: ${bind.code(lcSrcExprOf(a.value))}'];
      emitFns
        ..add('function $name(${['event', if (scope.isNotEmpty) scope].join(', ')}) {')
        ..add('  if ($cb) $cb(lcEvt(${jsString(emit.event)}, { ${args.join(', ')} }));')
        ..add('}');
    });
    return out;
  }

  final view =
      _View(
          prefix: prefix,
          plans: plans,
          notes: notes,
          dyn: (n, prop) => lcBoundAttr(plan, n, prop, notes),
          events: eventsOf,
          ownerId: def.id,
          importDir: './',
          rootNode: live.root,
          textNeedsString: (n) => !lcBoundIsText(plan, n, 'text'),
        )
        ..pageJump = doc == null ? null : lcPageJumper(doc, hash: true, allowSelf: true)
        ..bind = bind;
  final root = view.node(live.root, 0);

  void forwards(LcNode n) {
    if (n.type == 'component') {
      for (final e in lcEmitsOf(n).values) {
        emitted.add(e.event);
      }
    }
    n.children.forEach(forwards);
  }

  forwards(live.root);
  final declared = [for (final e in lcCompEvents(def)) e.name];
  final events = [
    ...declared,
    for (final e in emitted)
      if (!declared.contains(e)) e,
  ];
  final attrOf = {for (final p in def.props) p.name: plan.attrs[p.name]!, for (final g in live.variantGroups) lcVariantProp(g): lcVariantProp(g)};
  final own = [
    for (final v in live.own)
      if (!v.isDerived) v,
  ];
  final derived = [
    for (final v in live.own)
      if (v.isDerived) v,
  ];
  final models = [
    for (final v in live.propVars)
      if (live.modelProps.contains(v.name)) v,
  ];
  final params = [
    for (final v in live.propVars) '${attrOf[v.name]} = ${lcInitialLiteral(v)}',
    for (final e in events) lcReactEventAttr(e),
    for (final v in models) 'onLcUpdate_${attrOf[v.name]}',
    ...plan.slotAttrs.values,
    'className',
    'style',
    '...lcRest',
  ];
  final out = StringBuffer()
    ..writeln('// $kExportHeader')
    ..writeln('// 自定义组件：${jsComment(def.name, 60)}')
    ..writeln('//')
    ..writeln('// 怎么读这份代码：')
    ..writeln('// - 外面传进来的属性是函数的参数；每次重画时抄进 lcVars，下面的界面读的是 lcVars。')
    ..writeln('// - 组件自己的状态也在 lcVars 里（useRef 里的普通对象，这个组件每用一次各有一份）；改完调用 lcRefresh() 重画。')
    ..writeln('// - 往外发事件就是调用外面传进来的回调（on 开头的那几个参数）；带出去的数据在事件对象的 detail 里。')
    ..writeln('import React, { useRef, useState } from "react";')
    ..writeln('import ${jsString('../$kReactBaseCss')};')
    ..writeln('import ${jsString('./${plan.name}.css')};');
  view.imports().forEach(out.writeln);
  out
    ..writeln()
    ..writeln('// —— 小工具 ——')
    ..writeln(lcJsRuntime.trim())
    ..writeln()
    ..writeln(lcBindJsRuntime.trim())
    ..writeln()
    ..writeln(kLcEvtJs.trim())
    ..writeln()
    ..writeln('export default function ${plan.name}({ ${params.join(', ')} }) {')
    ..writeln('  // 组件自己的状态')
    ..writeln('  const lcVars = ${_objectLiteral([for (final v in own) (v.name, lcInitialLiteral(v))])}')
    ..writeln('  const [, lcSetTick] = useState(0);')
    ..writeln('  function lcRefresh() {')
    ..writeln('    lcSetTick((n) => n + 1);')
    ..writeln('  }');
  final plain = [
    for (final v in live.propVars)
      if (!live.modelProps.contains(v.name)) v,
  ];
  if (plain.isNotEmpty) {
    out.writeln('  // 属性：照外面这一次给的');
    for (final v in plain) {
      out.writeln('  lcVars${isJsIdentifier(v.name) ? '.${v.name}' : '[${jsString(v.name)}]'} = ${attrOf[v.name]};');
    }
  }
  if (models.isNotEmpty) {
    out
      ..writeln('  // 会被里面的输入框改的属性：自己留一份；外面给的值变了才跟上，自己改了就告诉外面')
      ..writeln('  const lcSeen = useRef({}).current;');
    for (final v in models) {
      final a = attrOf[v.name];
      out
        ..writeln('  if (lcSeen.${v.name} !== $a) {')
        ..writeln('    lcSeen.${v.name} = $a;')
        ..writeln('    lcVars.${v.name} = $a;')
        ..writeln('  }')
        ..writeln('  function lcOut_${v.name}(v) {')
        ..writeln('    lcVars.${v.name} = v;')
        ..writeln('    lcRefresh();')
        ..writeln('    if (onLcUpdate_$a) onLcUpdate_$a(v);')
        ..writeln('  }');
    }
  }
  if (derived.isNotEmpty) {
    out
      ..writeln('  // 派生值：读的时候现算')
      ..writeln('  const lcDerived = {');
    for (final v in derived) {
      out.writeln('    ${isJsIdentifier(v.name) ? v.name : '[${jsString(v.name)}]'}: () => ${bind.code(v.derived)},');
    }
    out.writeln('  };');
  }
  if (emitFns.isNotEmpty) {
    out.writeln('  // 往外发事件');
    _indent(emitFns).forEach(out.writeln);
  }
  out
    ..writeln()
    ..writeln('  return (');
  _indent(_indent(root.asRoot)).forEach(out.writeln);
  out
    ..writeln('  );')
    ..writeln('}');
  return (out.toString(), '/* $kExportHeader */\n${lcCollectCss(live.root, prefix, notes, plans: plans)}');
}
