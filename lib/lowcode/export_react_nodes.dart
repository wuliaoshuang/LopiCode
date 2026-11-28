/// React 导出里“结构和样子”的那一半（线 B 管）：一个节点怎么写成 JSX、多页面怎么出文件、自定义组件的文件。
/// 页面脚本（`_page`，里面有线 A 的逻辑接入点）留在 export_react.dart。
part of 'export_react.dart';

LcFrameworkExport _exportSite(LcDocument doc) {
  final notes = <String>[kNoteBody, kNotePages];
  final site = LcSitePlan(doc);
  final files = <LcExportFile>[lcFormatted('$kLcShellName.jsx', lcReactShell(site), 'jsx')];
  final components = <LcExportFile>[];
  final done = <String>{};
  // 走新路的页面有两页以上：小库和页面宿主抽成一个共用文件（线 A 的接入点，logic_core_js.dart）。
  final coreShared = lcMarkCoreShared([for (final p in site.pages) p.view]);
  for (final p in site.pages) {
    final plans = LcComponentPlans.build(p.view, pageName: p.name, notes: notes, fixedNames: site.componentNames);
    if (site.navPart != null) lcNavPartOf[p.view.root] = site.navPart!;
    if (site.topPart != null) lcTopPartOf[p.view.root] = site.topPart!;
    final (jsx, css) = _page(p.view, p.name, plans, notes);
    files
      ..add(lcFormatted('${p.name}.jsx', jsx, 'jsx'))
      ..add(lcFormatted('${p.name}.css', css, 'css'));
    for (final plan in plans.all) {
      if (!done.add(plan.def.id)) continue;
      final (cJsx, cCss) = _component(plan, plans, notes, doc: p.view, home: lcLiveFilesOk(p.view) ? p.view : null);
      components
        ..add(lcFormatted('components/${plan.name}.jsx', cJsx, 'jsx'))
        ..add(lcFormatted('components/${plan.name}.css', cCss, 'css'));
    }
  }
  files.add(lcFormatted(kReactBaseCss, '/* $kExportHeader */\n$kFrameworkBaseCss${lcThemeCssIfUsed(doc)}', 'css'));
  final nav = site.navPart;
  if (nav != null && files.any((f) => f.content.contains('import $nav from'))) {
    components.add(lcFormatted('components/$nav.jsx', lcReactNavPart(doc, site, nav, text: jsxText, attr: jsxAttr)!, 'jsx'));
  }
  final top = site.topPart;
  if (top != null && files.any((f) => f.content.contains('import $top from'))) {
    components.add(lcFormatted('components/$top.jsx', lcReactTopPart(doc, site, top, text: jsxText, attr: jsxAttr)!, 'jsx'));
  }
  final shared = LcBindPlan.of(doc, doc.root);
  if (shared != null && shared.hasProject) files.add(LcExportFile(path: kLcReactStateFile, content: lcReactStateFile(shared)));
  if (coreShared && files.any((f) => f.content.contains("'./$kLcCoreSharedFile'") || f.content.contains('"./$kLcCoreSharedFile"'))) {
    files.add(LcExportFile(path: kLcCoreSharedFile, content: lcCoreSharedSource()));
  }
  return LcFrameworkExport(files: [...files, ...components], notes: lcLiveNotes(notes));
}

extension _ViewNodes on _View {
  _Jsx _node(LcNode n, int depth) {
    if (depth > kExportMaxDepth) {
      notes.add('有控件嵌套太深，里面的内容没有导出。');
      return const _Jsx(['嵌套太深，这里面的内容没有导出'], _Kind.comment);
    }
    final a = _attrs(n);
    // 各页共用的底部导航：引用公共部件（export_shared_parts.dart）。
    final part = lcNavPartFor(pageRoot, n, attrs: a, plain: ' className="${lcNodeClass(n, prefix)}"');
    if (part != null) {
      parts.add(part);
      return _Jsx(['<$part$a${lcIsPageBar(pageRoot, n) ? ' data-page=""' : ''} current={${lcNavPartCurrent(n)}} />']);
    }
    // 各页共用的顶部导航栏：同理；这一页的标题、返回箭头当属性传，左右按钮也当属性传（left / right）。
    final topPart = lcTopPartFor(pageRoot, n, attrs: a, plain: ' className="${lcNodeClass(n, prefix)}"');
    if (topPart != null) {
      parts.add(topPart);
      final head = '<$topPart$a${lcIsPageBar(pageRoot, n) ? ' data-page=""' : ''}${jsxAttr('title', lcTopPartTitle(n))}${lcTopPartBack(n) ? ' back' : ''}';
      final sides = [
        for (final side in ['left', 'right'])
          if (lcTopPartSlot(n, side).isNotEmpty) (side, [for (final c in lcTopPartSlot(n, side)) ...node(c, depth + 2).asChild]),
      ];
      if (sides.isEmpty) return _Jsx(['$head />']);
      return _Jsx([
        head,
        for (final (side, kids) in sides) ...['  $side={', '    <>', ..._indent(_indent(_indent(kids))), '    </>', '  }'],
        '/>',
      ]);
    }
    // 第 3 版的新组件：元素树三种导出共用（export_web_v3.dart）。
    final el = bind == null ? lcWebElement(n, web) : lcBoundWebElement(n, web);
    if (el != null) {
      bind?.markEl(el, n);
      return _Jsx([
        for (final p in lcRenderEl(el, LcWebDialect.react, hostAttrs: a, text: jsxText, attr: jsxAttr))
          if (p.child == null) '${'  ' * p.indent}${p.line}' else ...[for (final l in node(p.child!, depth + p.indent).asChild) '${'  ' * p.indent}$l'],
      ]);
    }
    switch (n.type) {
      case 'text':
        return _Jsx(['<p$a>${_content(n)}</p>']);
      case 'button':
        final icon = lcButtonIcon(n);
        final solo = dyn(n, 'text') == null && (n.strProp('text') ?? '').isEmpty;
        return _Jsx(['<button type="button"$a${_disabled(n)}>${icon == null ? '' : lcIconSvg(icon, classAttr: 'className', solo: solo, jsx: true)}${_content(n)}</button>']);
      case 'image':
        final altText = n.strProp('alt');
        final placeholder = altText == null ? ' role="img" aria-label="图片占位"' : ' role="img"${jsxAttr('aria-label', altText)}';
        final boundAlt = bind?.value(n, 'alt');
        final alt = boundAlt != null ? ' alt={$boundAlt}' : (altText == null ? ' alt=""' : jsxAttr('alt', altText));
        final e = bind?.value(n, 'src') ?? dyn(n, 'src');
        if (e != null) {
          // 地址会变：有地址显示图片，空着显示占位块。
          return _Jsx(['$e ? (', '  <img$a src={$e}$alt />', ') : (', '  <div$a$placeholder></div>', ')'], _Kind.expression);
        }
        final src = n.strProp('src');
        return _Jsx([src == null ? '<div$a$placeholder></div>' : '<img$a${jsxAttr('src', src)}$alt />']);
      case 'input':
        final model = bind?.modelName(n);
        final value = model != null ? 'lcText(${bind!.read(model)})' : dyn(n, 'value');
        final type = lcInputType(n), fixed = n.strProp('value'), label = lcInputLabel(n);
        final input =
            '<input$a${type == null ? '' : ' type="$type"'}${_bindable(n, 'placeholder')}${value != null ? ' value={$value}' : (fixed == null ? '' : jsxAttr('defaultValue', fixed))}'
            '${lcInputRequired(n) ? ' required' : ''}${_disabled(n)} />';
        if (label == null) return _Jsx([input]);
        return _Jsx([
          '<label className="${lcFieldClassOf(n, prefix)}">',
          '  <span className="lc-label">',
          '    ${jsxText(label)}',
          if (lcInputRequired(n)) '    <span className="lc-required" aria-hidden="true">{" *"}</span>',
          '  </span>',
          '  $input',
          '</label>',
        ]);
      case 'list':
        final items = n.props['items'];
        final list = bind?.value(n, 'items');
        if (list != null) return _Jsx(['<ul$a>', '  {$list.map((lcItem, lcAt) => (', '    <li key={lcAt}>{lcText(lcItem)}</li>', '  ))}', '</ul>']);
        return _Jsx(['<ul$a>', for (final item in items is List ? items : const <Object?>[]) '  <li>${jsxText('$item')}</li>', '</ul>']);
      case 'divider':
        return _Jsx(['<hr$a />']);
      case 'spacer':
        return _Jsx(['<div$a></div>']);
      case LcNode.unknownType:
        notes.add(kNoteUnknownNode);
        return const _Jsx(['这里有一个新版应用加的组件，这一版导不出来'], _Kind.comment);
      case 'component':
        final plan = plans.planFor(n, ownerId: ownerId);
        if (plan == null) {
          return _Jsx(['这里原来是一个自定义组件（${lcSafeRef(n)}），没有导出：找不到它的定义，或者它绕回来用到了自己'], _Kind.comment);
        }
        used.add(plan);
        final values = StringBuffer();
        // 用了第 6 期新东西的实例：绑了状态的属性、选的变体、接了动作的事件（export_react_live.dart）。
        final live = lcUsesLiveFile(plan.def, n) ? _liveInstanceAttrs(this, plan, n) : null;
        if (live != null) values.write(live.attrs);
        for (final (attr, p, v) in lcInstanceValues(plan, n)) {
          if (live != null && live.bound.contains(p.name)) continue;
          values.write(v is String ? jsxAttr(attr, v) : ' $attr={${lcValueLiteral(p.type, v)}}');
        }
        final filled = plan.filled(n);
        if (n.children.isNotEmpty && plan.def.slots.isEmpty) notes.add(kNoteHomeless);
        if (filled.isEmpty) return _Jsx(['<${plan.name}$a$values />']);
        // 填进插槽的内容：默认插槽写成子节点（组件那边是 children），具名插槽当属性传一段 JSX。
        List<String> kidsOf(String slot) => [for (final c in filled[slot]!) ...node(c, depth + 1).asChild];
        final named = [
          for (final slot in filled.keys)
            if (slot != kLcDefaultSlot) ...['  ${plan.slotAttrs[slot]}={', '    <>', ..._indent(_indent(_indent(kidsOf(slot)))), '    </>', '  }'],
        ];
        final inner = filled.containsKey(kLcDefaultSlot) ? kidsOf(kLcDefaultSlot) : null;
        if (named.isEmpty) return _Jsx(['<${plan.name}$a$values>', ..._indent(inner!), '</${plan.name}>']);
        return _Jsx([
          '<${plan.name}$a$values',
          ...named,
          if (inner == null) '/>' else ...['>', ..._indent(inner), '</${plan.name}>'],
        ]);
      case 'slot':
        // 组件定义里：外面传了就用外面的，没传用默认内容。同名的第二个、页面里误放的：只留里面的内容。
        final name = lcSlotNameOf(n);
        final attr = ownerId == null ? null : plans.planOf(ownerId!)?.slotAttrs[name];
        if (ownerId == null) notes.add(kNoteStraySlot);
        final kids = [for (final c in n.children) ...node(c, depth + 1).asChild];
        if (attr == null || !_slotsSeen.add(name)) return _Jsx(['<>', ..._indent(kids), '</>']);
        if (kids.isEmpty) return _Jsx([attr], _Kind.expression);
        return _Jsx(['$attr ?? (', '  <>', ..._indent(_indent(kids)), '  </>', ')'], _Kind.expression);
      default:
        final tag = n.type == 'page' ? 'main' : 'div';
        return _Jsx([
          '<$tag$a${lcBoxReactAttrs(n, off: bind?.value(n, 'disabled'), label: bind?.value(n, 'alt'), attr: jsxAttr)}>',
          for (final c in n.children) ..._indent(node(c, depth + 1).asChild),
          '</$tag>',
        ]);
    }
  }

  List<String> imports() => [for (final p in used) 'import ${p.name} from ${jsString('$importDir${p.name}.jsx')};', for (final p in parts) 'import $p from ${jsString('$importDir$p.jsx')};'];
}

/// [doc]：多页面导出时给（组件里的底部导航项要知道项目里有哪些页）。
(String, String) _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc, LcDocument? home}) {
  final def = plan.def;
  // 用了事件 / 变体 / 自己的状态 / 定义里的绑定：组件文件自己带这些（export_react_live.dart）。没用的照旧，一个字不变。
  if (home != null && lcDefIsLive(def)) return _liveComponent(LcLiveComp(home, def), plan, plans, notes, doc: doc);
  final prefix = lcComponentPrefix(def);
  final view = _View(
    prefix: prefix,
    plans: plans,
    notes: notes,
    dyn: (n, prop) => lcBoundAttr(plan, n, prop, notes),
    events: (_) => const {},
    ownerId: def.id,
    importDir: './',
    rootNode: def.root,
    textNeedsString: (n) => !lcBoundIsText(plan, n, 'text'),
  )..pageJump = doc == null ? null : lcPageJumper(doc, hash: true, allowSelf: true);
  final root = view.node(def.root, 0);
  final params = [for (final LcComponentProp p in def.props) '${plan.attrs[p.name]} = ${lcPropDefaultLiteral(p)}', ...plan.slotAttrs.values, 'className', 'style', '...lcRest'];
  final out = StringBuffer()
    ..writeln('// $kExportHeader')
    ..writeln('// 自定义组件：${jsComment(def.name, 60)}')
    ..writeln('import React from "react";')
    ..writeln('import ${jsString('../$kReactBaseCss')};')
    ..writeln('import ${jsString('./${plan.name}.css')};');
  view.imports().forEach(out.writeln);
  out
    ..writeln()
    // className / style / 其余的（事件等）是外面用这个组件时传进来的，接在最外层的元素上。
    ..writeln('export default function ${plan.name}({ ${params.join(', ')} }) {')
    ..writeln('  return (');
  _indent(_indent(root.asRoot)).forEach(out.writeln);
  out
    ..writeln('  );')
    ..writeln('}');
  return (out.toString(), '/* $kExportHeader */\n${lcCollectCss(def.root, prefix, notes, plans: plans)}');
}
