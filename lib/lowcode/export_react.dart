/// 把低代码页面导出成 React 函数组件（`.jsx` + `.css`，不用 TypeScript）。
///
/// - 页面：`<名字>.jsx` + `<名字>.css`；共用的基础样式 `lc-base.css`；用到的每个自定义组件 `components/<名字>.jsx` + `.css`。
/// - 标签、class 和导出网页（export_html.dart）一致。
///
/// 变量和控件属性怎么存（这是这份导出最要紧的设计）：
/// React 的 `useState` 是“下次重画才生效”的，积木却是一步一步马上生效的（先改变量、下一块就读它；
/// 请求回来、等一会儿之后还要读到最新的值）。所以不把它们直接放进 `useState`，而是：
/// - 页面变量放在 `lcVars`、被逻辑读 / 改的控件属性放在 `lcUi`，两个都是 `useRef({...}).current`——
///   整个组件一辈子只有这一个对象，读它永远是最新的值，写它马上生效，异步回调里拿到的也是同一个对象；
/// - 每次写完调用 `lcRefresh()`（一个只管计数的 `useState`），让 React 重新画一遍，界面从 `lcUi` 里读到新值。
/// 这样积木的先后语义和导出的网页完全一样。代价：这不是最“地道”的 React 写法（有的代码检查规则会提醒“渲染时读了 ref”）。
///
/// 防注入的规矩（test/lowcode_export_react_test.dart 有专门的用例）：
/// 模型里来的字符串进 JSX 一律写成 `{"…"}`（`jsString` 出来的字符串字面量），只有不含 `{ } < > & / *`、引号、
/// 反斜杠、换行的普通文字才直接写；属性值一律 `name={"…"}`；注释只通过 `jsComment`。
///
/// 2026-11-26 起在开发机上用 esbuild 真编译（JSX）、再用 react-dom/server 渲染（test/dev_webdev_compile_test.dart，环境不在时跳过）。
/// 真浏览器里、点击之后的变化没有验证过。
library;

import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react_bind.dart';
import 'package:lopicode/lowcode/export_react_target.dart';
import 'package:lopicode/lowcode/export_shared_parts.dart';
import 'package:lopicode/lowcode/export_theme_bp.dart';
import 'package:lopicode/lowcode/export_v3_fields.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/top_shared.dart';

export 'package:lopicode/lowcode/export_framework_common.dart' show LcExportFile, LcFrameworkExport;
export 'package:lopicode/lowcode/export_react_target.dart' show ReactJsTarget;

/// 页面组件里“界面”开始的地方。测试靠这一行把前面的逻辑部分单独取出来跑。
const String kReactViewMarker = '// —— 界面 ——';

/// 共用基础样式的文件名。
const String kReactBaseCss = 'lc-base.css';

final RegExp _plainText = RegExp(r'''^[^{}<>&"'\\`/*\x00-\x1f\x7f\u0085\u2028\u2029]+$''');

/// 固定的文字放进 JSX 的元素内容里。普通文字直接写；其余写成字符串表达式 `{"…"}`。
String jsxText(String s) {
  if (s.isEmpty) return '';
  if (_plainText.hasMatch(s) && s.trim() == s) return s;
  return '{${jsString(s)}}';
}

/// 固定的字符串属性：` name={"…"}`。
String jsxAttr(String name, String value) => ' $name={${jsString(value)}}';

/// 把页面导出成 React 的文件。任何输入都不抛异常。
///
/// 多页面的项目：每页一个 `<页名>.jsx` / `.css`，外加一个外壳 `LcApp.jsx`（看地址栏决定显示哪一页，见 export_pages.dart）；
/// 自定义组件所有页面共用一份。只有一页时和以前逐字节一样。
LcFrameworkExport exportReact(LcDocument source) {
  lcSettleSharedNav(source);
  lcSettleSharedTop(source);
  // 用了第 6 期新东西（事件、变体、自己的状态、属性绑定）的组件实例：先摊开成普通页面的样子再导出。
  final doc = lcExportDoc(source, allPages: true);
  if (doc.isMultiPage) return _exportSite(doc);
  final notes = <String>[kNoteBody];
  final pageName = lcPageName(doc);
  final plans = LcComponentPlans.build(doc, pageName: pageName, notes: notes);
  final (jsx, css) = _page(doc, pageName, plans, notes);
  final files = <LcExportFile>[
    lcFormatted('$pageName.jsx', jsx, 'jsx'),
    lcFormatted('$pageName.css', css, 'css'),
    lcFormatted(kReactBaseCss, '/* $kExportHeader */\n$kFrameworkBaseCss${lcThemeCssIfUsed(doc)}', 'css'),
  ];
  for (final plan in plans.all) {
    final (cJsx, cCss) = _component(plan, plans, notes);
    files
      ..add(lcFormatted('components/${plan.name}.jsx', cJsx, 'jsx'))
      ..add(lcFormatted('components/${plan.name}.css', cCss, 'css'));
  }
  final shared = LcBindPlan.of(doc, doc.root);
  if (shared != null && shared.hasProject) files.add(LcExportFile(path: kLcReactStateFile, content: lcReactStateFile(shared)));
  return LcFrameworkExport(files: files, notes: {...notes}.toList());
}

LcFrameworkExport _exportSite(LcDocument doc) {
  final notes = <String>[kNoteBody, kNotePages];
  final site = LcSitePlan(doc);
  final files = <LcExportFile>[lcFormatted('$kLcShellName.jsx', lcReactShell(site), 'jsx')];
  final components = <LcExportFile>[];
  final done = <String>{};
  for (final p in site.pages) {
    final plans = LcComponentPlans.build(p.view, pageName: p.name, notes: notes, fixedNames: site.componentNames);
    if (site.navPart != null) lcNavPartOf[p.view.root] = site.navPart!;
    final (jsx, css) = _page(p.view, p.name, plans, notes);
    files
      ..add(lcFormatted('${p.name}.jsx', jsx, 'jsx'))
      ..add(lcFormatted('${p.name}.css', css, 'css'));
    for (final plan in plans.all) {
      if (!done.add(plan.def.id)) continue;
      final (cJsx, cCss) = _component(plan, plans, notes, doc: p.view);
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
  final shared = LcBindPlan.of(doc, doc.root);
  if (shared != null && shared.hasProject) files.add(LcExportFile(path: kLcReactStateFile, content: lcReactStateFile(shared)));
  return LcFrameworkExport(files: [...files, ...components], notes: {...notes}.toList());
}

enum _Kind {
  /// 一个 JSX 元素。
  element,

  /// 一个 JS 表达式（比如“有地址显示图片、没有显示占位”的三元式）：当子节点时要包一层花括号。
  expression,

  /// 只有一句注释（没导出的组件）。
  comment,
}

class _Jsx {
  const _Jsx(this.lines, [this.kind = _Kind.element]);
  final List<String> lines;
  final _Kind kind;

  /// 当别的元素的子节点时怎么写。
  List<String> get asChild => switch (kind) {
    _Kind.element => lines,
    _Kind.comment => ['{/* ${lines.single} */}'],
    _Kind.expression => [for (var i = 0; i < lines.length; i++) '${i == 0 ? '{' : ''}${lines[i]}${i == lines.length - 1 ? '}' : ''}'],
  };

  /// 当组件 `return (…)` 的内容时怎么写。
  List<String> get asRoot => kind == _Kind.comment ? ['null /* ${lines.single} */'] : lines;
}

List<String> _indent(List<String> lines) => [for (final l in lines) '  $l'];

/// JSX 生成器：页面和组件定义共用，区别只在“某个属性绑到哪个表达式上”和“事件挂什么”。
class _View {
  _View({required this.prefix, required this.plans, required this.notes, required this.dyn, required this.events, this.ownerId, required this.importDir, this.rootNode, this.textNeedsString});

  final String prefix;
  final LcComponentPlans plans;
  final List<String> notes;

  /// 这个节点的这个属性绑到哪个表达式上；固定内容返回 null。
  final String? Function(LcNode n, String prop) dyn;

  /// 这个节点要挂的事件：React 的属性名（onClick / onChange / onInput）→ 处理函数名。
  final Map<String, String> Function(LcNode n) events;
  final String? ownerId;
  final String importDir;

  /// 组件定义的根节点：它要接住外面传进来的 className / style / 事件（页面没有）。
  final LcNode? rootNode;

  /// 绑定的文字要不要先 `String(...)`（接的是数字 / 是否类型的 prop 时，React 不会自己把布尔显示出来）。
  final bool Function(LcNode n)? textNeedsString;

  final Set<LcComponentPlan> used = {};
  final Set<String> parts = {};
  final Set<String> _slotsSeen = {};

  /// 状态与绑定（第 5 期）：只有用了绑定的页面给；别的是 null，下面每一处都走原来那条路。
  LcReactBind? bind;

  /// 页面的根节点（组件定义里是 null）：判断“页面级的栏”用。
  LcNode? pageRoot;

  /// 底部导航项怎么跳页（只有一页的项目是 null）。
  String? Function(String pageId)? pageJump;
  late final LcWebCtx web = LcWebCtx(
    uniqueIds: prefix.isEmpty,
    fieldClass: (n) => lcFieldClassOf(n, prefix),
    // 弹窗的显示被逻辑管着（lcUi 里有它）：关闭时改 lcUi 再让 React 重画。
    closeExpr: (n) => dyn(n, 'visible') == null ? null : '{ ${dyn(n, 'visible')} = false; lcRefresh(); }',
    pageRoot: pageRoot,
    pageJump: pageJump,
  );

  String _attrs(LcNode n) {
    final isRoot = identical(n, rootNode);
    final cls = lcNodeClass(n, prefix);
    final b = StringBuffer();
    if (isRoot) b.write(' {...lcRest}');
    final bound = bind;
    final key = bound?.keyOf(n);
    if (key != null) b.write(' key={$key}');
    final tail = bound?.classTail(n) ?? '';
    b.write(isRoot ? ' className={"$cls" + (className ? " " + className : "")}' : (tail.isEmpty ? ' className="$cls"' : ' className={"$cls"$tail}'));
    final bg = dyn(n, 'bg');
    final color = dyn(n, 'color');
    // 显示条件和“改控件 显示”只能留一样（检查会报）：都有时听显示条件的。
    final show = bound?.showCond(n);
    final visible = show ?? dyn(n, 'visible');
    final style = [
      // 空着＝还没被逻辑改过：交回给样式表（undefined 的条目 React 不会写到元素上）。
      if (bg != null) 'background: $bg || undefined',
      if (color != null) 'color: $color || undefined',
      if (visible != null) 'display: $visible ? undefined : "none"',
      ...?bound?.styleEntries(n),
      if (isRoot) '...style',
    ];
    if (style.length == 1 && isRoot) {
      b.write(' style={style}');
    } else if (style.isNotEmpty) {
      b.write(' style={{ ${style.join(', ')} }}');
    }
    // 输入框双向：内容变化时先写回状态，再接着做原来挂在它上面的处理。
    final model = n.type == 'input' ? bound?.modelName(n) : null;
    final set = model == null ? null : bound!.modelSet(model, 'event.target.value');
    var wired = false;
    events(n).forEach((attr, fn) {
      if (set != null && attr == 'onChange') {
        wired = true;
        b.write(' onChange={(event) => { $set $fn(event); }}');
      } else {
        b.write(' $attr={$fn}');
      }
    });
    if (set != null && !wired) b.write(' onChange={(event) => { $set }}');
    return b.toString();
  }

  String _content(LcNode n) {
    final bound = bind?.value(n, 'text');
    if (bound != null) return '{$bound}';
    final e = dyn(n, 'text');
    if (e == null) return jsxText(n.strProp('text') ?? '');
    return (textNeedsString?.call(n) ?? false) ? '{String($e)}' : '{$e}';
  }

  String _disabled(LcNode n) {
    final v = bind?.value(n, 'disabled');
    return v != null ? ' disabled={$v}' : (lcIsDisabled(n) ? ' disabled' : '');
  }

  String _bindable(LcNode n, String prop) {
    final e = bind?.value(n, prop) ?? dyn(n, prop);
    return e != null ? ' $prop={$e}' : jsxAttr(prop, n.strProp(prop) ?? '');
  }

  _Jsx node(LcNode n, int depth) {
    final bound = bind;
    if (bound == null) return _node(n, depth);
    final rep = bound.open(n);
    final inner = _node(n, depth);
    final cond = bound.renderCond(n);
    final key = bound.keyOf(n);
    bound.close(n);
    if (rep == null && cond == null) return inner;
    // 一个元素：直接用（key 已经写在它上面了）；不是元素（三元式、注释）：包一层带 key 的 Fragment。
    final one = inner.kind == _Kind.element ? inner.lines : [rep == null ? '<>' : '<React.Fragment key={$key}>', ..._indent(inner.asChild), rep == null ? '</>' : '</React.Fragment>'];
    if (rep == null) return _Jsx(['$cond && (', ..._indent(one), ')'], _Kind.expression);
    final each = ['${rep.list}.map((${rep.item}, ${rep.index}) =>${cond == null ? '' : ' $cond ?'} (', ..._indent(one), cond == null ? '))' : ') : null)'];
    if (rep.empty == null) return _Jsx(each, _Kind.expression);
    return _Jsx(['${rep.list}.length === 0 ? (', '  <p className="lc-text lc-empty">${jsxText(rep.empty!)}</p>', ') : (', ..._indent(each), ')'], _Kind.expression);
  }

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
        for (final (attr, p, v) in lcInstanceValues(plan, n)) {
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
        return _Jsx(['<$tag$a>', for (final c in n.children) ..._indent(node(c, depth + 1).asChild), '</$tag>']);
    }
  }

  List<String> imports() => [for (final p in used) 'import ${p.name} from ${jsString('$importDir${p.name}.jsx')};', for (final p in parts) 'import $p from ${jsString('$importDir$p.jsx')};'];
}

String _objectLiteral(Iterable<(String, String)> entries) =>
    ['useRef({', for (final (key, value) in entries) '    ${isJsIdentifier(key) ? key : '[${jsString(key)}]'}: $value,', '  }).current;'].join('\n');

(String, String) _page(LcDocument doc, String pageName, LcComponentPlans plans, List<String> notes) {
  final logic = doc.logic;
  final handlers = lcPlanHandlers(doc, notes);
  // 控件属性是 lcUi 对象里的键，不和别的名字抢，所以单独一本名册。
  final states = LcPropStates(LcNames());
  // 第 5 期：这一页用了状态与绑定才有 plan / bind；没用的页面下面每一处都走原来那条路。
  final plan = LcBindPlan.of(doc, doc.root);
  final bind = plan == null ? null : LcReactBind(plan);
  final writer = JsLogicWriter(doc, ReactJsTarget(states, notes, bind: bind), lookup: plan?.lookup);

  final functions = <String>[];
  for (var i = 0; i < logic.handlers.length; i++) {
    final h = logic.handlers[i];
    functions
      ..add('// ${jsComment(describeHandler(h, doc))}')
      ..add('function ${handlers.names[i]}(${h.event == 'load' ? '' : 'event'}) {')
      ..addAll(_indent(writer.blocks(h.body, event: h.event)))
      ..add('}')
      ..add('');
  }

  final dispatchers = <String>[];
  Map<String, String> eventsOf(LcNode n) {
    final out = <String, String>{};
    for (final event in const ['click', 'input']) {
      final fns = handlers.of(n, event);
      final value = event == 'input' && n.type == 'input' ? states.of(n, 'value') : null;
      if (fns.isEmpty && value == null) continue;
      // 输入框在 React 里“内容变化”是 onChange；别的控件用 onInput。
      final attr = event == 'click' ? 'onClick' : (n.type == 'input' ? 'onChange' : 'onInput');
      if (fns.length == 1 && value == null) {
        out[attr] = fns.single;
        continue;
      }
      final name = 'lcOn_${n.id}_$event';
      dispatchers
        ..add('function $name(event) {')
        ..addAll([
          if (value != null) ...['  lcUi.${value.name} = lcEventValue(event);', '  lcRefresh();'],
          for (final f in fns) '  $f(event);',
        ])
        ..add('}')
        ..add('');
      out[attr] = name;
    }
    return out;
  }

  final view = _View(prefix: '', plans: plans, notes: notes, dyn: (n, prop) => states.of(n, prop) == null ? null : 'lcUi.${states.of(n, prop)!.name}', events: eventsOf, importDir: './components/')
    ..pageRoot = doc.root
    ..pageJump = doc.isMultiPage ? lcPageJumper(doc, hash: true) : null
    ..bind = bind;
  final root = view.node(doc.root, 0);

  final hasLogic = !logic.isEmpty || plan != null;
  final hooks = [if (handlers.load.isNotEmpty) 'useEffect', if (hasLogic) 'useRef', if (hasLogic) 'useState', if (plan != null && plan.hasProject) 'useSyncExternalStore'];
  final out = StringBuffer()..writeln('// $kExportHeader');
  if (plan != null) {
    out
      ..writeln('//')
      ..writeln('// 怎么读这份代码：')
      ..writeln('// - 这一页用了“状态与数据绑定”。页面级状态在 lcVars 里（useRef 里的普通对象：读到的永远是最新的值，写完马上生效）；')
      ..writeln('//   每次写完调用 lcRefresh()，React 重新画界面，界面里读着状态的地方就跟着变了。')
      ..writeln('// - 派生值在 lcDerived 里，是一个个小函数，读的时候现算。')
      ..writeln('// - 项目级状态在 $kLcReactStateFile 的 lcShared 里（所有页面共用）；改完调用 lcSharedChanged()，订着它的页面都会重画。')
      ..writeln('// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。')
      ..writeln('// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。');
  } else if (hasLogic) {
    out
      ..writeln('//')
      ..writeln('// 怎么读这份代码：')
      ..writeln('// - 页面变量在 lcVars 里，逻辑里读或改到的控件属性在 lcUi 里。它们是 useRef 里的普通对象：读到的永远是最新的值，')
      ..writeln('//   写完马上生效（请求回来、等一会儿之后也一样）。每次写完调用 lcRefresh()，React 才会重新画界面。')
      ..writeln('// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木（改的是 lcUi）。')
      ..writeln('// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。')
      ..writeln('// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。');
  }
  // 带上 React 本身：老的 JSX 转换方式需要它在场，新的方式多这一个名字也没有坏处。
  out
    ..writeln('import React${hooks.isEmpty ? '' : ', { ${hooks.join(', ')} }'} from "react";')
    ..writeln('import ${jsString('./$kReactBaseCss')};')
    ..writeln('import ${jsString('./$pageName.css')};');
  if (plan != null && plan.hasProject) out.writeln('import { lcShared, lcSharedChanged, lcSnapshot, lcSubscribe } from ${jsString('./$kLcReactStateFile')};');
  view.imports().forEach(out.writeln);
  out.writeln();
  if (hasLogic) {
    out
      ..writeln('// —— 小工具 ——')
      ..writeln(lcJsRuntime.trim())
      ..writeln();
    if (plan != null) {
      out
        ..writeln(lcBindJsRuntime.trim())
        ..writeln();
    }
  }
  out.writeln('export default function $pageName() {');
  if (hasLogic) {
    out
      ..writeln(plan == null ? '  // 页面变量' : '  // 页面级状态')
      ..writeln(
        '  const lcVars = ${_objectLiteral([for (final v in logic.variables)
          if (!v.isDerived || plan == null) (v.name, lcInitialLiteral(v))])}',
      );
    if (plan != null && bind != null) {
      if (plan.hasProject) {
        out
          ..writeln('  // 订着项目级状态：别的页面（或者这一页）改了它，这里重画')
          ..writeln('  useSyncExternalStore(lcSubscribe, lcSnapshot, lcSnapshot);');
      }
      if (plan.derived.isNotEmpty) {
        out
          ..writeln('  // 派生值：读的时候现算')
          ..writeln('  const lcDerived = {');
        for (final s in plan.derived) {
          out.writeln('    ${isJsIdentifier(s.name) ? s.name : '[${jsString(s.name)}]'}: () => ${bind.code(s.variable.derived)},');
        }
        out.writeln('  };');
      }
    }
    out
      ..writeln('  // 控件属性：逻辑里读或改到的那些（下面的界面绑定着它们）')
      ..writeln('  const lcUi = ${_objectLiteral([for (final s in states.all) (s.name, s.initialJs)])}')
      ..writeln('  // 改了上面两样以后调用它，让 React 重新画一遍界面')
      ..writeln('  const [, lcSetTick] = useState(0);')
      ..writeln('  function lcRefresh() {')
      ..writeln('    lcSetTick((n) => n + 1);')
      ..writeln('  }')
      ..writeln();
    _indent([...functions, ...dispatchers]).map((l) => l.trimRight()).forEach(out.writeln);
    if (handlers.load.isNotEmpty) {
      out
        ..writeln('  // 页面打开时（只做一次）。开发模式下开着 StrictMode 时 React 会故意做两次，上线后只做一次。')
        ..writeln('  useEffect(() => {');
      for (final f in handlers.load) {
        out.writeln('    $f();');
      }
      out
        ..writeln('  }, []);')
        ..writeln();
      notes.add('React 开发模式下如果开着 StrictMode，“页面打开时”的处理会被执行两次（React 故意的），上线后只执行一次。');
    }
    notes.add(plan == null ? kNoteNoBinding : kNoteBindings);
    if (plan != null && doc.components.any((c) => lcTreeHasBindings(c.root))) notes.add(kNoteBindComponent);
  }
  out
    ..writeln('  $kReactViewMarker')
    ..writeln('  return (');
  _indent(_indent(root.asRoot)).forEach(out.writeln);
  out
    ..writeln('  );')
    ..writeln('}');
  return (out.toString(), '/* $kExportHeader */\n${lcCollectCss(doc.root, '', notes, plans: plans)}');
}

/// [doc]：多页面导出时给（组件里的底部导航项要知道项目里有哪些页）。
(String, String) _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc}) {
  final def = plan.def;
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
