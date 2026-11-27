/// Vue 3 导出：用了第 6 期新东西（事件、变体、自己的状态、定义里的绑定）的自定义组件出成单独的 `.vue` 文件，
/// 以及页面上怎么用它（第四轮 B4；两种框架共用的那一半在 export_comp_files.dart）。
///
/// 组件文件里（写法对着 Vue 官方文档核对过的记在 docs/api-notes.md“组件文件”一节）：
/// - 属性 `defineProps`；每个属性再包成一个 `computed`，定义里的绑定读的是它。
///   被里面的输入框双向写的属性：组件自己留一份（外面给的值变了就跟上），改了以后发 `update:名字`——
///   页面写 `v-model:名字="状态"` 就是双向；页面没接，它在组件里照样能用。
/// - 事件 `defineEmits`；定义里“往外发”的控件挂一个小函数，带出去的数据包成 [kLcEvtJs] 约定的样子。
/// - 组件自己的状态是组件里的 `ref`（每用一次各有一份），派生值是 `computed`。
/// - 变体：每组一个文字属性 `lcv_<组名>`，样式差别是“这个属性等于某个变体名时成立的类名”。
part of 'export_vue.dart';

/// 页面（或外层组件）上一个实例多出来的属性。
class _LiveAttrs {
  _LiveAttrs(this.attrs, this.bound);
  final String attrs;

  /// 已经按绑定传了的属性（写死的值不再传）。
  final Set<String> bound;
}

_LiveAttrs _liveInstanceAttrs(_Template t, LcComponentPlan plan, LcNode n) {
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
      final state = lcPlainStateOf(e);
      final ref = state != null && models.contains(p.name) ? bind.writableRef(state) : null;
      b.write(ref != null ? ' v-model:$attr="$ref"' : ' :$attr="${bind.propCall(n, '属性 ${p.name}', e, p.type)}"');
    }
  }
  lcInstanceVariants(def, n).forEach((group, name) => b.write(' ${lcVariantProp(group)}="$name"'));
  final marks = lcTakeEventMarks(n);
  final inDef = t.ownerId != null;
  for (final e in lcCompEvents(def)) {
    final mark = marks[e.name];
    final fns = mark == null ? const <String>[] : t.events(mark).values.toList();
    if (fns.isNotEmpty) {
      b.write(' @${e.name}="${fns.first}"');
    } else if (inDef) {
      // 套在另一个组件里的实例：它的事件接着往外发（带的数据原样带出去）。
      final out = lcEmitsOf(n)[e.name];
      if (out != null) b.write(' @${e.name}="emit(\'${out.event}\', \$event)"');
    }
  }
  return _LiveAttrs(b.toString(), bound);
}

String _livePropType(String type) => switch (type) {
  'number' => 'Number',
  'bool' => 'Boolean',
  'list' => 'Array',
  'record' => 'Object',
  _ => 'String',
};

String _liveComponent(LcLiveComp live, LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc}) {
  final def = live.def;
  final prefix = lcComponentPrefix(def);
  final names = LcNames(kJsNamesInUse)
    ..reserve('props')
    ..reserve('emit');
  for (final p in plans.all) {
    names.reserve(p.name);
  }
  final varNames = {for (final s in live.plan.states) s.name: names.take(s.name, tag: 'var')};
  final bind = LcVueBind(live.plan, varNames);
  final emitted = <String>{};
  final emitFns = <String>[];
  final emitNames = <String>{};

  Map<String, String> eventsOf(LcNode n) {
    if (n.type == 'component') return const {};
    final out = <String, String>{};
    lcEmitsOf(n).forEach((on, emit) {
      if ((on != 'click' && on != 'input') || !isSafeNodeId(n.id)) return;
      emitted.add(emit.event);
      final scope = bind.scopeParams;
      final name = 'lcEmit_${n.id}_$on';
      out[on] = '$name(${['\$event', if (scope.isNotEmpty) scope].join(', ')})';
      if (!emitNames.add(name)) return;
      final args = [for (final a in live.argsOf(emit)) '${jsString(a.key)}: ${bind.code(lcSrcExprOf(a.value))}'];
      emitFns
        ..add('function $name(${['event', if (scope.isNotEmpty) scope].join(', ')}) {')
        ..add('  emit(${jsString(emit.event)}, lcEvt(${jsString(emit.event)}, { ${args.join(', ')} }));')
        ..add('}');
    });
    return out;
  }

  final template =
      _Template(
          prefix: prefix,
          plans: plans,
          notes: notes,
          // 老写法接到属性上的：读 props 里那一个。
          dyn: (n, prop) {
            final attr = lcBoundAttr(plan, n, prop, notes);
            return attr == null ? null : 'props.$attr';
          },
          events: eventsOf,
          ownerId: def.id,
          importDir: './',
        )
        ..pageJump = doc == null ? null : lcPageJumper(doc, hash: true, allowSelf: true)
        ..bind = bind
        ..node(live.root, 1);

  // 套着的实例往外转发的事件也要声明。
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
  final emits = [
    ...declared,
    for (final e in emitted)
      if (!declared.contains(e)) e,
    for (final p in live.modelProps) 'update:${plan.attrs[p]}',
  ];
  final own = [
    for (final v in live.own)
      if (!v.isDerived) v,
  ];
  final derived = [
    for (final v in live.own)
      if (v.isDerived) v,
  ];
  final attrOf = {for (final p in def.props) p.name: plan.attrs[p.name]!, for (final g in live.variantGroups) lcVariantProp(g): lcVariantProp(g)};
  final plainProps = [
    for (final v in live.propVars)
      if (!live.modelProps.contains(v.name)) v,
  ];
  final modelProps = [
    for (final v in live.propVars)
      if (live.modelProps.contains(v.name)) v,
  ];
  final vueImports = ['computed', if (own.isNotEmpty || modelProps.isNotEmpty) 'ref', if (modelProps.isNotEmpty) 'watch'];
  final script = <String>[
    '// 自定义组件：${jsComment(def.name, 60)}',
    '//',
    '// 怎么读这份脚本：',
    '// - 外面传进来的属性在 props 里；下面每个属性各包成一个 computed，模板里的绑定读的是它。',
    '// - 组件自己的状态是下面的 ref：这个组件每用一次各有一份。',
    '// - 往外发事件用 emit；带出去的数据在事件对象的 detail 里。',
    'import { ${vueImports.join(', ')} } from "vue";',
    ...template.imports(),
    '',
    'const props = defineProps({',
    for (final v in live.propVars)
      '  ${attrOf[v.name]}: { type: ${_livePropType(v.type)}, default: ${v.type == 'list' || v.type == 'record' ? '() => (${lcInitialLiteral(v)})' : lcInitialLiteral(v)} },',
    '});',
    'const emit = defineEmits([${emits.map(jsString).join(', ')}]);',
    if (plainProps.isNotEmpty) ...['', '// 属性（只读）', for (final v in plainProps) 'const ${varNames[v.name]} = computed(() => props.${attrOf[v.name]});'],
    if (modelProps.isNotEmpty) ...[
      '',
      '// 会被里面的输入框改的属性：组件自己留一份；外面给的值变了就跟上，自己改了就告诉外面（update:名字）',
      for (final v in modelProps) ...[
        'const lcOwn_${v.name} = ref(props.${attrOf[v.name]});',
        'watch(',
        '  () => props.${attrOf[v.name]},',
        '  (v) => {',
        '    lcOwn_${v.name}.value = v;',
        '  },',
        ');',
        'const ${varNames[v.name]} = computed({',
        '  get: () => lcOwn_${v.name}.value,',
        '  set: (v) => {',
        '    lcOwn_${v.name}.value = v;',
        '    emit(${jsString('update:${attrOf[v.name]}')}, v);',
        '  },',
        '});',
      ],
    ],
    if (own.isNotEmpty) ...['', '// 组件自己的状态（每用一次各有一份）', for (final v in own) 'const ${varNames[v.name]} = ref(${lcInitialLiteral(v)});'],
    if (derived.isNotEmpty) ...['', '// 派生值', for (final v in derived) 'const ${varNames[v.name]} = computed(() => ${bind.derivedCode(v.derived)});'],
    '',
    '// —— 小工具 ——',
    ...lcJsRuntime.trim().split('\n'),
    '',
    ...lcBindJsRuntime.trim().split('\n'),
    '',
    ...kLcEvtJs.trim().split('\n'),
    '',
    if (bind.functions.isNotEmpty) ...['// —— 绑定：模板里每一处绑定各调用一个 ——', ...bind.functions, ''],
    if (emitFns.isNotEmpty) ...['// —— 往外发事件 ——', ...emitFns],
  ];
  return _sfc(
    script: script,
    template: template.out.toString(),
    css: lcCollectCss(live.root, prefix, notes, plans: plans),
  );
}
