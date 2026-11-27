/// Vue 3 导出里“结构和样子”的那一半（线 B 管）：一个节点怎么写成模板、多页面怎么出文件、自定义组件的文件。
/// 页面脚本（`_page`、`_boundPage`，里面有线 A 的逻辑接入点）留在 export_vue.dart。
part of 'export_vue.dart';

LcFrameworkExport _exportSite(LcDocument doc) {
  final notes = <String>[kNoteBody, kNotePages];
  final site = LcSitePlan(doc);
  final files = <LcExportFile>[lcFormatted('$kLcShellName.vue', lcVueShell(site, themeCss: lcThemeCssIfUsed(doc)), 'vue')];
  final components = <LcExportFile>[];
  final done = <String>{};
  final nav = site.navPart;
  // 走新路的页面有两页以上：小库和页面宿主抽成一个共用文件（线 A 的接入点，logic_core_js.dart）。
  final coreShared = lcMarkCoreShared([for (final p in site.pages) p.view]);
  for (final p in site.pages) {
    if (nav != null) lcNavPartOf[p.view.root] = nav;
    final plans = LcComponentPlans.build(p.view, pageName: p.name, notes: notes, fixedNames: site.componentNames);
    files.add(lcFormatted('${p.name}.vue', _page(p.view, plans, notes), 'vue'));
    for (final plan in plans.all) {
      if (done.add(plan.def.id)) components.add(lcFormatted('components/${plan.name}.vue', _component(plan, plans, notes, doc: p.view, home: lcLiveFilesOk(p.view) ? p.view : null), 'vue'));
    }
  }
  final navFile = nav != null && files.any((f) => f.content.contains('import $nav from')) ? lcVueNavPart(doc, site, text: vueText, attr: vueAttr) : null;
  final shared = LcBindPlan.of(doc, doc.root);
  return LcFrameworkExport(
    files: [
      ...files,
      ...components,
      if (navFile != null) lcFormatted('components/$nav.vue', navFile, 'vue'),
      if (shared != null && shared.hasProject) LcExportFile(path: kLcStateFile, content: lcVueStateFile(shared)),
      if (coreShared && files.any((f) => f.content.contains("'./$kLcCoreSharedFile'") || f.content.contains('"./$kLcCoreSharedFile"')))
        LcExportFile(path: kLcCoreSharedFile, content: lcCoreSharedSource()),
    ],
    notes: lcLiveNotes(notes),
  );
}

extension _TemplateNodes on _Template {
  void _node(LcNode n, int depth) {
    final pad = '  ' * depth;
    if (depth > kExportMaxDepth) {
      out.writeln('$pad<!-- 嵌套太深，这里面的内容没有导出 -->');
      notes.add('有控件嵌套太深，里面的内容没有导出。');
      return;
    }
    final a = _attrs(n);
    // 各页共用的底部导航：引用公共部件（export_shared_parts.dart）。
    final part = lcNavPartFor(pageRoot, n, attrs: a, plain: ' class="${lcNodeClass(n, prefix)}"');
    if (part != null) {
      parts.add(part);
      return out.writeln('$pad<$part$a${lcIsPageBar(pageRoot, n) ? ' data-page=""' : ''} :current="${lcNavPartCurrent(n)}" />');
    }
    // 第 3 版的新组件：元素树三种导出共用（export_web_v3.dart）。
    final el = bind == null ? lcWebElement(n, web) : lcBoundWebElement(n, web);
    if (el != null) {
      bind?.markEl(el, n);
      for (final p in lcRenderEl(el, LcWebDialect.vue, hostAttrs: a, text: vueText, attr: vueAttr)) {
        p.child == null ? out.writeln('$pad${'  ' * p.indent}${p.line}') : node(p.child!, depth + p.indent);
      }
      return;
    }
    switch (n.type) {
      case 'text':
        out.writeln('$pad<p$a>${_content(n)}</p>');
      case 'button':
        final icon = lcButtonIcon(n);
        final solo = dyn(n, 'text') == null && (n.strProp('text') ?? '').isEmpty;
        out.writeln('$pad<button type="button"$a${_disabled(n)}>${icon == null ? '' : lcIconSvg(icon, solo: solo)}${_content(n)}</button>');
      case 'image':
        final name = bind?.value(n, 'src') ?? dyn(n, 'src');
        if (name != null) {
          // 地址会变：有地址显示图片，空着显示占位块。
          out.writeln('$pad<img v-if="$name"$a :src="$name"${_alt(n)}>');
          out.writeln('$pad<div v-else$a role="img"${_ariaLabel(n)}></div>');
        } else {
          final src = n.strProp('src');
          out.writeln(src == null ? '$pad<div$a role="img"${_ariaLabel(n)}></div>' : '$pad<img$a${vueAttr('src', src)}${_alt(n)}>');
        }
      case 'input':
        final value = dyn(n, 'value');
        final type = lcInputType(n), fixed = n.strProp('value'), label = lcInputLabel(n);
        final model = bind?.model(n) ?? '';
        final input =
            '<input$a${type == null ? '' : ' type="$type"'}${_bindable(n, 'placeholder')}${model.isNotEmpty ? model : (value != null ? ' :value="$value"' : (fixed == null ? '' : vueAttr('value', fixed)))}'
            '${lcInputRequired(n) ? ' required' : ''}${_disabled(n)}>';
        if (label == null) {
          out.writeln('$pad$input');
        } else {
          out.writeln('$pad<label class="${lcFieldClassOf(n, prefix)}">');
          out.writeln('$pad  <span class="lc-label">${vueText(label)}${lcInputRequired(n) ? '<span class="lc-required" aria-hidden="true"> *</span>' : ''}</span>');
          out.writeln('$pad  $input');
          out.writeln('$pad</label>');
        }
      case 'list':
        out.writeln('$pad<ul$a>');
        final items = n.props['items'];
        final list = bind?.value(n, 'items');
        if (list != null) {
          out.writeln('$pad  <li v-for="(lcItem, lcAt) in $list" :key="lcAt">{{ lcText(lcItem) }}</li>');
        } else {
          for (final item in items is List ? items : const <Object?>[]) {
            out.writeln('$pad  <li>${vueText('$item')}</li>');
          }
        }
        out.writeln('$pad</ul>');
      case 'divider':
        out.writeln('$pad<hr$a>');
      case 'spacer':
        out.writeln('$pad<div$a></div>');
      case LcNode.unknownType:
        out.writeln('$pad<!-- 这里有一个新版应用加的组件，这一版导不出来 -->');
        notes.add(kNoteUnknownNode);
      case 'component':
        final plan = plans.planFor(n, ownerId: ownerId);
        if (plan == null) {
          out.writeln('$pad<!-- 这里原来是一个自定义组件（${lcSafeRef(n)}），没有导出：找不到它的定义，或者它绕回来用到了自己 -->');
          return;
        }
        used.add(plan);
        final values = StringBuffer();
        // 用了第 6 期新东西的实例：绑了状态的属性、选的变体、接了动作的事件（export_vue_live.dart）。
        final live = lcUsesLiveFile(plan.def, n) ? _liveInstanceAttrs(this, plan, n) : null;
        if (live != null) {
          // 事件不挂在最外层元素上了（记号节点已经摘掉），a 里没有它们。
          values.write(live.attrs);
        }
        for (final (attr, p, v) in lcInstanceValues(plan, n)) {
          if (live != null && live.bound.contains(p.name)) continue;
          // 文字、颜色当普通属性传；数字、是否要用绑定写法才是真的数字 / 布尔。
          values.write(v is String ? vueAttr(attr, v) : ' :$attr="${lcValueLiteral(p.type, v)}"');
        }
        final filled = plan.filled(n);
        if (n.children.isNotEmpty && plan.def.slots.isEmpty) notes.add(kNoteHomeless);
        if (filled.isEmpty) {
          out.writeln('$pad<${plan.name}$a$values />');
          return;
        }
        // 填进插槽的内容：每个插槽一个 <template #名字>（Vue 的具名插槽写法；默认插槽是 #default）。
        out.writeln('$pad<${plan.name}$a$values>');
        filled.forEach((slot, kids) {
          out.writeln('$pad  <template #$slot>');
          for (final c in kids) {
            node(c, depth + 2);
          }
          out.writeln('$pad  </template>');
        });
        out.writeln('$pad</${plan.name}>');
      case 'slot':
        // 组件定义里：<slot>，里面是没填时显示的默认内容。同名的第二个、页面里误放的：只留里面的内容。
        final name = lcSlotNameOf(n);
        final real = ownerId != null && _slotsSeen.add(name);
        if (ownerId == null) notes.add(kNoteStraySlot);
        if (real) out.writeln('$pad<slot${name == kLcDefaultSlot ? '' : ' name="$name"'}>');
        for (final c in n.children) {
          node(c, depth + (real ? 1 : 0));
        }
        if (real) out.writeln('$pad</slot>');
      default:
        final tag = n.type == 'page' ? 'main' : 'div';
        out.writeln('$pad<$tag$a>');
        for (final c in n.children) {
          node(c, depth + 1);
        }
        out.writeln('$pad</$tag>');
    }
  }

  List<String> imports() => [for (final p in used) 'import ${p.name} from ${jsString('$importDir${p.name}.vue')};', for (final p in parts) 'import $p from ${jsString('$importDir$p.vue')};'];
}

String _propType(LcComponentProp p) => switch (p.type) {
  'number' => 'Number',
  'bool' => 'Boolean',
  _ => 'String',
};

/// [doc]：多页面导出时给（组件里的底部导航项要知道项目里有哪些页；组件哪页都可能用，所以“去当前这页”也照写，反正不会动）。
String _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc, LcDocument? home}) {
  final def = plan.def;
  // 用了事件 / 变体 / 自己的状态 / 定义里的绑定：组件文件自己带这些（export_vue_live.dart）。没用的照旧，一个字不变。
  if (home != null && lcDefIsLive(def)) return _liveComponent(LcLiveComp(home, def), plan, plans, notes, doc: doc);
  final prefix = lcComponentPrefix(def);
  final template = _Template(prefix: prefix, plans: plans, notes: notes, dyn: (n, prop) => lcBoundAttr(plan, n, prop, notes), events: (_) => const {}, ownerId: def.id, importDir: './')
    ..pageJump = doc == null ? null : lcPageJumper(doc, hash: true, allowSelf: true)
    ..node(def.root, 1);
  final script = <String>[
    '// 自定义组件：${jsComment(def.name, 60)}',
    ...template.imports(),
    if (def.props.isNotEmpty) ...['', 'defineProps({', for (final p in def.props) '  ${plan.attrs[p.name]}: { type: ${_propType(p)}, default: ${lcPropDefaultLiteral(p)} },', '});'],
  ];
  return _sfc(
    script: script,
    template: template.out.toString(),
    css: lcCollectCss(def.root, prefix, notes, plans: plans),
  );
}
