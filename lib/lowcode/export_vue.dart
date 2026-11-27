/// 把低代码页面导出成 Vue 3 单文件组件（`<script setup>`，不用 TypeScript）。
///
/// - 页面一个 `.vue` 文件；用到的每个自定义组件各一个 `components/<名字>.vue`。
/// - 标签、class 和导出网页（export_html.dart）一致；样式放在 `<style scoped>` 里。
/// - 逻辑：页面变量是 `ref`；被逻辑读 / 改的控件属性也各是一个 `ref`，模板里绑定着它，
///   所以“改控件”积木不直接碰 DOM，只改 `ref`。
///
/// 防注入的规矩（test/lowcode_export_vue_test.dart 有专门的用例）：
/// - 进模板的文字做 HTML 转义；带花括号、换行、控制字符的文字不直接写进模板，
///   改成 `{{ '…' }}`：里面是一个把危险字符全写成 `\uXXXX` 的字符串，Vue 不会把它当插值语法再解析一遍。
/// - 进脚本的字符串只通过 `jsString`；进注释的只通过 `jsComment`；样式值在收集时查过。
///
/// 2026-11-26 起在开发机上用官方的 @vue/compiler-sfc 真编译、再服务端渲染（test/dev_webdev_compile_test.dart，环境不在时跳过）。
/// 真浏览器里、点击之后的变化没有验证过。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_theme_bp.dart';
import 'package:lopicode/lowcode/export_v3_fields.dart';
import 'package:lopicode/lowcode/export_vue_bind.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_core_js.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

export 'package:lopicode/lowcode/export_framework_common.dart' show LcExportFile, LcFrameworkExport;

const _esc = HtmlEscape(HtmlEscapeMode.element);
const _escAttr = HtmlEscape(HtmlEscapeMode.attribute);

final RegExp _control = RegExp('[\\x00-\\x1f\\x7f\u0085\u2028\u2029]');

/// 一个可以放在模板表达式里的字符串字面量（单引号）。除了字母、数字、中文和少数标点，一律写成 `\uXXXX`：
/// 这样它里面不会有引号、尖括号、`&`、花括号、反引号、`$`、换行——放在属性值里、插值里都不会被截断或被再解析。
String vueStringLiteral(String s) {
  final out = StringBuffer("'");
  for (final unit in s.codeUnits) {
    final risky = unit < 0x20 || unit == 0x7f || unit == 0x85 || unit == 0x2028 || unit == 0x2029 || r'''\'"<>&{}`$'''.codeUnits.contains(unit);
    out.write(risky ? '\\u${unit.toRadixString(16).padLeft(4, '0')}' : String.fromCharCode(unit));
  }
  out.write("'");
  return out.toString();
}

/// 固定的文字放进模板的元素内容里。
String vueText(String s) => s.contains('{') || s.contains('}') || _control.hasMatch(s) ? '{{ ${vueStringLiteral(s)} }}' : _esc.convert(s);

/// 固定的属性：` name="…"`；值里有花括号、换行、控制字符时改用绑定写法 ` :name="'…'"`
/// （一行写完；不依赖“属性里的 {{ }} 不算插值”“属性里的换行怎么处理”这些没法在本机验证的细节）。
String vueAttr(String name, String value) => value.contains('{') || value.contains('}') || _control.hasMatch(value) ? ' :$name="${vueStringLiteral(value)}"' : ' $name="${_escAttr.convert(value)}"';

/// Vue 的写法：变量和控件属性都是 ref，读写 `.value`。
class VueJsTarget extends JsTarget {
  VueJsTarget(this.varNames, this.states, this.notes, {this.bind});

  /// 用了状态与绑定的页面才有：项目级状态从共用的 lcShared 读写，派生值不能写。
  final LcVueBind? bind;

  /// 页面变量名 → 脚本里的变量名（绝大多数一样；撞了保留字 / 别的名字的会加后缀）。
  final Map<String, String> varNames;
  final LcPropStates states;
  final List<String> notes;

  @override
  String readVar(LcVariable v) => bind?.sharedRef(v.name) ?? '${varNames[v.name]}.value';

  @override
  List<String> writeVar(LcVariable v, String valueJs) => v.isDerived ? ['// 跳过：${jsComment('${v.name} 是派生值，算出来的，不能改')}'] : ['${readVar(v)} = $valueJs;'];

  @override
  JsExpr readProp(LcNode node, String prop) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: false);
      notes.add('逻辑里有一处读不到：$why。');
      return JsExpr('"" /* ${jsComment(why)} */', LcType.text);
    }
    return JsExpr('${states.require(node, prop).name}.value', prop == 'visible' ? LcType.boolean : LcType.text);
  }

  @override
  List<String> writeProp(LcNode node, String prop, String valueJs) {
    if (!propFitsNode(prop, node.type)) {
      final why = lcPropUnfitReason(node, prop, write: true);
      notes.add('逻辑里有一块“改控件”被跳过了：$why。');
      return ['// 跳过：${jsComment(why)}'];
    }
    return ['${states.require(node, prop).name}.value = $valueJs;'];
  }

  @override
  List<String> goPage(LcDocument doc, LcPage page) => lcHashGoPage(page);
}

/// 把页面导出成 Vue 3 的文件。任何输入都不抛异常。
///
/// 多页面的项目：每页一个 `<页名>.vue`，外加一个外壳 `LcApp.vue`（看地址栏决定显示哪一页，见 export_pages.dart）；
/// 自定义组件所有页面共用一份。只有一页时和以前逐字节一样。
LcFrameworkExport exportVue(LcDocument doc) {
  if (doc.isMultiPage) return _exportSite(doc);
  final notes = <String>[kNoteBody];
  final pageName = lcPageName(doc);
  final plans = LcComponentPlans.build(doc, pageName: pageName, notes: notes);
  final files = <LcExportFile>[lcFormatted('$pageName.vue', _page(doc, plans, notes), 'vue')];
  for (final plan in plans.all) {
    files.add(lcFormatted('components/${plan.name}.vue', _component(plan, plans, notes), 'vue'));
  }
  final shared = LcBindPlan.of(doc, doc.root);
  if (shared != null && shared.hasProject) files.add(LcExportFile(path: kLcStateFile, content: lcVueStateFile(shared)));
  return LcFrameworkExport(files: files, notes: {...notes}.toList());
}

LcFrameworkExport _exportSite(LcDocument doc) {
  final notes = <String>[kNoteBody, kNotePages];
  final site = LcSitePlan(doc);
  final files = <LcExportFile>[lcFormatted('$kLcShellName.vue', lcVueShell(site, themeCss: lcThemeCssIfUsed(doc)), 'vue')];
  final components = <LcExportFile>[];
  final done = <String>{};
  for (final p in site.pages) {
    final plans = LcComponentPlans.build(p.view, pageName: p.name, notes: notes, fixedNames: site.componentNames);
    files.add(lcFormatted('${p.name}.vue', _page(p.view, plans, notes), 'vue'));
    for (final plan in plans.all) {
      if (done.add(plan.def.id)) components.add(lcFormatted('components/${plan.name}.vue', _component(plan, plans, notes, doc: p.view), 'vue'));
    }
  }
  final shared = LcBindPlan.of(doc, doc.root);
  return LcFrameworkExport(
    files: [
      ...files,
      ...components,
      if (shared != null && shared.hasProject) LcExportFile(path: kLcStateFile, content: lcVueStateFile(shared)),
    ],
    notes: {...notes}.toList(),
  );
}

/// 模板生成器：页面和组件定义共用，区别只在“某个属性绑到哪个名字上”和“事件挂什么”。
class _Template {
  _Template({required this.prefix, required this.plans, required this.notes, required this.dyn, required this.events, this.ownerId, required this.importDir});

  final String prefix;
  final LcComponentPlans plans;
  final List<String> notes;

  /// 这个节点的这个属性绑到哪个名字上；固定内容返回 null。
  final String? Function(LcNode n, String prop) dyn;

  /// 这个节点要挂的事件：事件名 → 处理函数名。
  final Map<String, String> Function(LcNode n) events;
  final String? ownerId;
  final String importDir;

  final StringBuffer out = StringBuffer();

  /// 页面的根节点（组件定义里是 null）：判断“页面级的栏”用。
  LcNode? pageRoot;

  /// 底部导航项怎么跳页（只有一页的项目是 null）。
  String? Function(String pageId)? pageJump;
  late final LcWebCtx web = LcWebCtx(
    uniqueIds: prefix.isEmpty,
    fieldClass: (n) => lcFieldClassOf(n, prefix),
    // 弹窗的显示被逻辑管着（v-show 绑着一个 ref）：关闭时改那个 ref。
    closeExpr: (n) => dyn(n, 'visible') == null ? null : '${dyn(n, 'visible')} = false',
    pageRoot: pageRoot,
    pageJump: pageJump,
  );

  /// 状态与绑定（第 5 期）：只有用了绑定的页面给；组件定义里、没用绑定的页面是 null，下面每一处都走原来那条路。
  LcVueBind? bind;

  /// 模板里用到的组件（要在脚本里 import）。
  final Set<LcComponentPlan> used = {};
  final Set<String> _slotsSeen = {};

  String _attrs(LcNode n) {
    final b = StringBuffer(' class="${lcNodeClass(n, prefix)}"');
    final bound = bind;
    if (bound != null) b.write(bound.wrapAttrs(n));
    final visible = dyn(n, 'visible');
    // 显示条件和“改控件 显示”只能留一样（检查会报）：都有时听显示条件的。
    if (visible != null && !(bound?.hasShow(n) ?? false)) b.write(' v-show="$visible"');
    final bg = dyn(n, 'bg');
    final color = dyn(n, 'color');
    final styles = [if (bg != null) 'background: $bg', if (color != null) 'color: $color', ...?bound?.styleEntries(n)];
    if (styles.isNotEmpty) {
      b.write(' :style="{ ${styles.join(', ')} }"');
    }
    final at = bound?.eachAt; // 新的页面逻辑、在“重复”里：事件带上这一项
    events(n).forEach((event, fn) => b.write(at == null ? ' @$event="$fn"' : ' @$event="$fn(Object.assign(\$event, { lcAt: $at }))"'));
    return b.toString();
  }

  String _content(LcNode n) {
    final name = bind?.value(n, 'text') ?? dyn(n, 'text');
    return name != null ? '{{ $name }}' : vueText(n.strProp('text') ?? '');
  }

  /// 禁用：绑了的写 `:disabled`，没绑的照旧。
  String _disabled(LcNode n) {
    final v = bind?.value(n, 'disabled');
    return v != null ? ' :disabled="$v"' : (lcIsDisabled(n) ? ' disabled' : '');
  }

  String _alt(LcNode n) {
    final v = bind?.value(n, 'alt');
    if (v != null) return ' :alt="$v"';
    return n.strProp('alt') == null ? ' alt=""' : vueAttr('alt', n.strProp('alt')!);
  }

  String _ariaLabel(LcNode n) => vueAttr('aria-label', n.strProp('alt') ?? '图片占位');

  String _bindable(LcNode n, String prop) {
    final name = bind?.value(n, prop) ?? dyn(n, prop);
    return name != null ? ' :$prop="$name"' : vueAttr(prop, n.strProp(prop) ?? '');
  }

  void node(LcNode n, int depth) {
    final bound = bind;
    if (bound == null) return _node(n, depth);
    final pad = '  ' * depth;
    for (final l in bound.open(n)) {
      out.writeln('$pad$l');
    }
    _node(n, depth);
    for (final l in bound.close(n)) {
      out.writeln('$pad$l');
    }
  }

  void _node(LcNode n, int depth) {
    final pad = '  ' * depth;
    if (depth > kExportMaxDepth) {
      out.writeln('$pad<!-- 嵌套太深，这里面的内容没有导出 -->');
      notes.add('有控件嵌套太深，里面的内容没有导出。');
      return;
    }
    final a = _attrs(n);
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
        for (final (attr, p, v) in lcInstanceValues(plan, n)) {
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

  List<String> imports() => [for (final p in used) 'import ${p.name} from ${jsString('$importDir${p.name}.vue')};'];
}

/// [globalCss]：不带 scoped 的一段（主题变量的 `:root` 写在 scoped 里不生效，所以单独一段）。
String _sfc({required List<String> script, required String template, required String css, String globalCss = ''}) {
  final out = StringBuffer()
    ..writeln('<script setup>')
    ..writeln('// $kExportHeader');
  script.forEach(out.writeln);
  out
    ..writeln('</script>')
    ..writeln()
    ..writeln('<template>')
    ..write(template)
    ..writeln('</template>')
    ..writeln()
    ..writeln('<style scoped>')
    ..write(kFrameworkBaseCss)
    ..write(css)
    ..writeln('</style>');
  if (globalCss.isNotEmpty) {
    out
      ..writeln()
      ..writeln('<style>')
      ..write(globalCss)
      ..writeln('</style>');
  }
  return out.toString();
}

String _page(LcDocument doc, LcComponentPlans plans, List<String> notes) {
  final logic = doc.logic;
  final handlers = lcPlanHandlers(doc, notes);

  // 名字的先后：处理函数名是定死的，组件名要和 import 对上，所以先占；再给变量、控件属性发名字。
  final names = LcNames(kJsNamesInUse);
  handlers.names.forEach(names.reserve);
  for (final p in plans.all) {
    names.reserve(p.name);
  }
  // 第 5 期：这一页用了状态与绑定才有 plan / bind；没用的页面下面每一处都走原来那条路。
  final plan = LcBindPlan.of(doc, doc.root);
  final varNames = {
    for (final v in logic.variables) v.name: names.take(v.name, tag: 'var'),
    if (plan != null)
      for (final s in plan.derived)
        if (s.project) s.name: names.take(s.name, tag: 'var'),
  };
  final states = LcPropStates(names);
  final bind = plan == null ? null : LcVueBind(plan, varNames);
  bind?.eventAt = doc.logic.front != null;
  final target = VueJsTarget(varNames, states, notes, bind: bind);
  final writer = JsLogicWriter(doc, target, lookup: plan?.lookup);
  // 用了新积木的页面：处理函数只把事件转给页面宿主（见 logic_core_js.dart）；没用的页面下面和以前一样。
  final core = lcCoreJsFor(doc, target, notes, lookup: plan?.lookup, hash: true);

  // 先翻处理函数：翻的过程中才知道哪些控件属性被用到了。
  final functions = <String>[
    ...?core?.top,
    ...?core?.boot,
    if (core != null) ...['const lcPage = lcBoot();', ''],
  ];
  for (var i = 0; i < logic.handlers.length; i++) {
    final h = logic.handlers[i];
    functions
      ..add('// ${jsComment(describeHandler(h, doc))}')
      ..add('function ${handlers.names[i]}(${h.event == 'load' ? '' : 'event'}) {')
      ..addAll([for (final l in core?.body(i) ?? writer.blocks(h.body, event: h.event)) '  $l'])
      ..add('}')
      ..add('');
  }

  // 一个控件的一个事件只能挂一个函数：有好几个处理、或者输入框要先把内容记下来时，包一层。
  final dispatchers = <String>[];
  Map<String, String> eventsOf(LcNode n) {
    final out = <String, String>{};
    for (final event in const ['click', 'input']) {
      final fns = handlers.of(n, event);
      final value = event == 'input' && n.type == 'input' ? states.of(n, 'value') : null;
      if (fns.isEmpty && value == null) continue;
      if (fns.length == 1 && value == null) {
        out[event] = fns.single;
        continue;
      }
      final name = 'lcOn_${n.id}_$event';
      dispatchers
        ..add('function $name(event) {')
        ..addAll([if (value != null) '  ${value.name}.value = lcEventValue(event);', for (final f in fns) '  $f(event);'])
        ..add('}')
        ..add('');
      out[event] = name;
    }
    return out;
  }

  final template = _Template(prefix: '', plans: plans, notes: notes, dyn: (n, prop) => states.of(n, prop)?.name, events: eventsOf, importDir: './components/')
    ..pageRoot = doc.root
    ..pageJump = doc.isMultiPage ? lcPageJumper(doc, hash: true) : null
    ..bind = bind
    ..node(doc.root, 1);

  if (plan != null && bind != null) {
    return _boundPage(doc, plans, notes, plan: plan, bind: bind, varNames: varNames, states: states, handlers: handlers, functions: functions, dispatchers: dispatchers, template: template);
  }
  final usesRef = logic.variables.isNotEmpty || !states.isEmpty;
  final vueImports = [if (handlers.load.isNotEmpty) 'onMounted', if (usesRef) 'ref'];
  final script = <String>[
    if (!logic.isEmpty) ...[
      '//',
      '// 怎么读这份脚本：',
      '// - 页面变量是下面的 ref；每个“处理”是一个函数，模板里用 @click / @input 挂在控件上。',
      '// - 变量改了以后，界面上不会自动跟着变。要让界面变，用“改控件”积木：它改的是下面“控件属性”里的 ref，模板绑定着它们。',
      '// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。',
      '// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。',
    ],
    if (vueImports.isNotEmpty) 'import { ${vueImports.join(', ')} } from "vue";',
    ...template.imports(),
    if (logic.variables.isNotEmpty) ...['', '// 页面变量', for (final v in logic.variables) 'const ${varNames[v.name]} = ref(${lcInitialLiteral(v)});'],
    if (!states.isEmpty) ...['', '// 控件属性：逻辑里读或改到的那些（模板里绑定着它们）', for (final s in states.all) 'const ${s.name} = ref(${s.initialJs});'],
    if (!logic.isEmpty) ...['', '// —— 小工具 ——', ...lcJsRuntime.trim().split('\n'), ''],
    ...functions,
    ...dispatchers,
    if (handlers.load.isNotEmpty) ...['// 页面准备好以后，执行“页面打开时”的处理', 'onMounted(() => {', for (final f in handlers.load) '  $f();', '});'],
  ];
  if (!logic.isEmpty) notes.add(kNoteNoBinding);
  return _sfc(
    script: script,
    template: template.out.toString(),
    css: lcCollectCss(doc.root, '', notes, plans: plans),
    // 只有一页的项目没有外壳：主题变量写在页面自己这个文件里。
    globalCss: doc.isMultiPage ? '' : lcThemeCssIfUsed(doc),
  );
}

/// 用了状态与绑定的页面的脚本（没用的页面不走这里）。
String _boundPage(
  LcDocument doc,
  LcComponentPlans plans,
  List<String> notes, {
  required LcBindPlan plan,
  required LcVueBind bind,
  required Map<String, String> varNames,
  required LcPropStates states,
  required LcHandlerPlan handlers,
  required List<String> functions,
  required List<String> dispatchers,
  required _Template template,
}) {
  final own = [
    for (final s in plan.states)
      if (!s.project) s.variable,
  ];
  final derived = [for (final s in plan.derived) s.variable];
  final usesRef = own.any((v) => !v.isDerived) || !states.isEmpty;
  final vueImports = [if (derived.isNotEmpty) 'computed', if (handlers.load.isNotEmpty) 'onMounted', if (usesRef) 'ref'];
  final script = <String>[
    '//',
    '// 怎么读这份脚本：',
    '// - 这一页用了“状态与数据绑定”。页面级状态是下面的 ref，派生值是 computed；项目级状态在 $kLcStateFile 的 lcShared 里（所有页面共用）。',
    '// - 状态改了以后，模板里绑了它的地方自己跟着变。每个绑定的式子是下面“绑定”里的一个小函数，模板里只调用它。',
    '// - 加减乘除一律按数字算：输入框里读到的是文字，会先用 lcNum 转成数字（转不了的当 0）。',
    '// - “等一会儿”“请求网址”只管它们里面的积木：排在它们后面的积木不会等，马上接着做。',
    if (vueImports.isNotEmpty) 'import { ${vueImports.join(', ')} } from "vue";',
    if (plan.hasProject) 'import { lcShared } from ${jsString('./$kLcStateFile')};',
    ...template.imports(),
    if (own.any((v) => !v.isDerived)) ...[
      '',
      '// 页面级状态',
      for (final v in own)
        if (!v.isDerived) 'const ${varNames[v.name]} = ref(${lcInitialLiteral(v)});',
    ],
    if (derived.isNotEmpty) ...['', '// 派生值：读的时候才算，算过记着，用到的状态变了才重算', for (final v in derived) 'const ${varNames[v.name]} = computed(() => ${bind.derivedCode(v.derived)});'],
    if (!states.isEmpty) ...['', '// 控件属性：逻辑里读或改到的那些（模板里绑定着它们）', for (final s in states.all) 'const ${s.name} = ref(${s.initialJs});'],
    '',
    '// —— 小工具 ——',
    ...lcJsRuntime.trim().split('\n'),
    '',
    ...lcBindJsRuntime.trim().split('\n'),
    '',
    if (bind.functions.isNotEmpty) ...['// —— 绑定：模板里每一处绑定各调用一个 ——', ...bind.functions, ''],
    ...functions,
    ...dispatchers,
    if (handlers.load.isNotEmpty) ...['// 页面准备好以后，执行“页面打开时”的处理', 'onMounted(() => {', for (final f in handlers.load) '  $f();', '});'],
  ];
  notes.add(kNoteBindings);
  if (doc.components.any((c) => lcTreeHasBindings(c.root))) notes.add(kNoteBindComponent);
  return _sfc(
    script: script,
    template: template.out.toString(),
    css: lcCollectCss(doc.root, '', notes, plans: plans),
    globalCss: doc.isMultiPage ? '' : lcThemeCssIfUsed(doc),
  );
}

String _propType(LcComponentProp p) => switch (p.type) {
  'number' => 'Number',
  'bool' => 'Boolean',
  _ => 'String',
};

/// [doc]：多页面导出时给（组件里的底部导航项要知道项目里有哪些页；组件哪页都可能用，所以“去当前这页”也照写，反正不会动）。
String _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes, {LcDocument? doc}) {
  final def = plan.def;
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
