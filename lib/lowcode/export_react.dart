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
/// 没有用真正的 React 编译器（Babel 等）编译过：本机没有，也不联网装。
library;

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

export 'package:lopicode/lowcode/export_framework_common.dart' show LcExportFile, LcFrameworkExport;

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

String _member(String object, String key) => isJsIdentifier(key) ? '$object.$key' : '$object[${jsString(key)}]';

/// React 的写法：变量在 `lcVars`、控件属性在 `lcUi`（见文件开头的说明），写完调用 `lcRefresh()`。
class ReactJsTarget extends JsTarget {
  ReactJsTarget(this.states, this.notes);
  final LcPropStates states;
  final List<String> notes;

  @override
  String readVar(LcVariable v) => _member('lcVars', v.name);

  @override
  List<String> writeVar(LcVariable v, String valueJs) => ['${readVar(v)} = $valueJs;', 'lcRefresh();'];

  @override
  JsExpr readProp(LcNode node, String prop) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: false);
      notes.add('逻辑里有一处读不到：$why。');
      return JsExpr('"" /* ${jsComment(why)} */', LcType.text);
    }
    return JsExpr('lcUi.${states.require(node, prop).name}', prop == 'visible' ? LcType.boolean : LcType.text);
  }

  @override
  List<String> writeProp(LcNode node, String prop, String valueJs) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: true);
      notes.add('逻辑里有一块“改控件”被跳过了：$why。');
      return ['// 跳过：${jsComment(why)}'];
    }
    return ['lcUi.${states.require(node, prop).name} = $valueJs;', 'lcRefresh();'];
  }
}

/// 把页面导出成 React 的文件。任何输入都不抛异常。
LcFrameworkExport exportReact(LcDocument doc) {
  final notes = <String>[kNoteBody];
  final pageName = lcPageName(doc);
  final plans = LcComponentPlans.build(doc, pageName: pageName, notes: notes);
  final (jsx, css) = _page(doc, pageName, plans, notes);
  final files = <LcExportFile>[lcFormatted('$pageName.jsx', jsx, 'jsx'), lcFormatted('$pageName.css', css, 'css'), lcFormatted(kReactBaseCss, '/* $kExportHeader */\n$kFrameworkBaseCss', 'css')];
  for (final plan in plans.all) {
    final (cJsx, cCss) = _component(plan, plans, notes);
    files
      ..add(lcFormatted('components/${plan.name}.jsx', cJsx, 'jsx'))
      ..add(lcFormatted('components/${plan.name}.css', cCss, 'css'));
  }
  return LcFrameworkExport(files: files, notes: {...notes}.toList());
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

  String _attrs(LcNode n) {
    final isRoot = identical(n, rootNode);
    final cls = lcNodeClass(n, prefix);
    final b = StringBuffer();
    if (isRoot) b.write(' {...lcRest}');
    b.write(isRoot ? ' className={"$cls" + (className ? " " + className : "")}' : ' className="$cls"');
    final bg = dyn(n, 'bg');
    final color = dyn(n, 'color');
    final visible = dyn(n, 'visible');
    final style = [
      // 空着＝还没被逻辑改过：交回给样式表（undefined 的条目 React 不会写到元素上）。
      if (bg != null) 'background: $bg || undefined',
      if (color != null) 'color: $color || undefined',
      if (visible != null) 'display: $visible ? undefined : "none"',
      if (isRoot) '...style',
    ];
    if (style.length == 1 && isRoot) {
      b.write(' style={style}');
    } else if (style.isNotEmpty) {
      b.write(' style={{ ${style.join(', ')} }}');
    }
    events(n).forEach((attr, fn) => b.write(' $attr={$fn}'));
    return b.toString();
  }

  String _content(LcNode n) {
    final e = dyn(n, 'text');
    if (e == null) return jsxText(n.strProp('text') ?? '');
    return (textNeedsString?.call(n) ?? false) ? '{String($e)}' : '{$e}';
  }

  String _bindable(LcNode n, String prop) {
    final e = dyn(n, prop);
    return e != null ? ' $prop={$e}' : jsxAttr(prop, n.strProp(prop) ?? '');
  }

  _Jsx node(LcNode n, int depth) {
    if (depth > kExportMaxDepth) {
      notes.add('有控件嵌套太深，里面的内容没有导出。');
      return const _Jsx(['嵌套太深，这里面的内容没有导出'], _Kind.comment);
    }
    final a = _attrs(n);
    switch (n.type) {
      case 'text':
        return _Jsx(['<p$a>${_content(n)}</p>']);
      case 'button':
        return _Jsx(['<button type="button"$a>${_content(n)}</button>']);
      case 'image':
        const placeholder = ' role="img" aria-label="图片占位"';
        final e = dyn(n, 'src');
        if (e != null) {
          // 地址会变：有地址显示图片，空着显示占位块。
          return _Jsx(['$e ? (', '  <img$a src={$e} alt="" />', ') : (', '  <div$a$placeholder></div>', ')'], _Kind.expression);
        }
        final src = n.strProp('src');
        return _Jsx([src == null ? '<div$a$placeholder></div>' : '<img$a${jsxAttr('src', src)} alt="" />']);
      case 'input':
        final value = dyn(n, 'value');
        return _Jsx(['<input$a${_bindable(n, 'placeholder')}${value == null ? '' : ' value={$value}'} />']);
      case 'list':
        final items = n.props['items'];
        return _Jsx(['<ul$a>', for (final item in items is List ? items : const <Object?>[]) '  <li>${jsxText('$item')}</li>', '</ul>']);
      case 'divider':
        return _Jsx(['<hr$a />']);
      case 'spacer':
        return _Jsx(['<div$a></div>']);
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
        return _Jsx(['<${plan.name}$a$values />']);
      default:
        final tag = n.type == 'page' ? 'main' : 'div';
        return _Jsx(['<$tag$a>', for (final c in n.children) ..._indent(node(c, depth + 1).asChild), '</$tag>']);
    }
  }

  List<String> imports() => [for (final p in used) 'import ${p.name} from ${jsString('$importDir${p.name}.jsx')};'];
}

String _objectLiteral(Iterable<(String, String)> entries) =>
    ['useRef({', for (final (key, value) in entries) '    ${isJsIdentifier(key) ? key : '[${jsString(key)}]'}: $value,', '  }).current;'].join('\n');

(String, String) _page(LcDocument doc, String pageName, LcComponentPlans plans, List<String> notes) {
  final logic = doc.logic;
  final handlers = lcPlanHandlers(doc, notes);
  // 控件属性是 lcUi 对象里的键，不和别的名字抢，所以单独一本名册。
  final states = LcPropStates(LcNames());
  final writer = JsLogicWriter(doc, ReactJsTarget(states, notes));

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

  final view = _View(prefix: '', plans: plans, notes: notes, dyn: (n, prop) => states.of(n, prop) == null ? null : 'lcUi.${states.of(n, prop)!.name}', events: eventsOf, importDir: './components/');
  final root = view.node(doc.root, 0);

  final hasLogic = !logic.isEmpty;
  final hooks = [if (handlers.load.isNotEmpty) 'useEffect', if (hasLogic) 'useRef', if (hasLogic) 'useState'];
  final out = StringBuffer()..writeln('// $kExportHeader');
  if (hasLogic) {
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
  view.imports().forEach(out.writeln);
  out.writeln();
  if (hasLogic) {
    out
      ..writeln('// —— 小工具 ——')
      ..writeln(lcJsRuntime.trim())
      ..writeln();
  }
  out.writeln('export default function $pageName() {');
  if (hasLogic) {
    out
      ..writeln('  // 页面变量')
      ..writeln('  const lcVars = ${_objectLiteral([for (final v in logic.variables) (v.name, lcInitialLiteral(v))])}')
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
    notes.add(kNoteNoBinding);
  }
  out
    ..writeln('  $kReactViewMarker')
    ..writeln('  return (');
  _indent(_indent(root.asRoot)).forEach(out.writeln);
  out
    ..writeln('  );')
    ..writeln('}');
  return (out.toString(), '/* $kExportHeader */\n${lcCollectCss(doc.root, '', notes)}');
}

(String, String) _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes) {
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
  );
  final root = view.node(def.root, 0);
  final params = [for (final LcComponentProp p in def.props) '${plan.attrs[p.name]} = ${lcPropDefaultLiteral(p)}', 'className', 'style', '...lcRest'];
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
  return (out.toString(), '/* $kExportHeader */\n${lcCollectCss(def.root, prefix, notes)}');
}
