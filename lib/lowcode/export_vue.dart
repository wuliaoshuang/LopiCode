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
/// 没有用真正的 Vue 编译器编译过（本机没有，也不联网装），只做了结构检查和脚本部分的实际运行。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

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
  VueJsTarget(this.varNames, this.states, this.notes);

  /// 页面变量名 → 脚本里的变量名（绝大多数一样；撞了保留字 / 别的名字的会加后缀）。
  final Map<String, String> varNames;
  final LcPropStates states;
  final List<String> notes;

  @override
  String readVar(LcVariable v) => '${varNames[v.name]}.value';

  @override
  List<String> writeVar(LcVariable v, String valueJs) => ['${varNames[v.name]}.value = $valueJs;'];

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
}

/// 把页面导出成 Vue 3 的文件。任何输入都不抛异常。
LcFrameworkExport exportVue(LcDocument doc) {
  final notes = <String>[kNoteBody];
  final pageName = lcPageName(doc);
  final plans = LcComponentPlans.build(doc, pageName: pageName, notes: notes);
  final files = <LcExportFile>[lcFormatted('$pageName.vue', _page(doc, plans, notes), 'vue')];
  for (final plan in plans.all) {
    files.add(lcFormatted('components/${plan.name}.vue', _component(plan, plans, notes), 'vue'));
  }
  return LcFrameworkExport(files: files, notes: {...notes}.toList());
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

  /// 模板里用到的组件（要在脚本里 import）。
  final Set<LcComponentPlan> used = {};

  String _attrs(LcNode n) {
    final b = StringBuffer(' class="${lcNodeClass(n, prefix)}"');
    final visible = dyn(n, 'visible');
    if (visible != null) b.write(' v-show="$visible"');
    final bg = dyn(n, 'bg');
    final color = dyn(n, 'color');
    if (bg != null || color != null) {
      b.write(' :style="{ ${[if (bg != null) 'background: $bg', if (color != null) 'color: $color'].join(', ')} }"');
    }
    events(n).forEach((event, fn) => b.write(' @$event="$fn"'));
    return b.toString();
  }

  String _content(LcNode n) {
    final name = dyn(n, 'text');
    return name != null ? '{{ $name }}' : vueText(n.strProp('text') ?? '');
  }

  String _bindable(LcNode n, String prop) {
    final name = dyn(n, prop);
    return name != null ? ' :$prop="$name"' : vueAttr(prop, n.strProp(prop) ?? '');
  }

  void node(LcNode n, int depth) {
    final pad = '  ' * depth;
    if (depth > kExportMaxDepth) {
      out.writeln('$pad<!-- 嵌套太深，这里面的内容没有导出 -->');
      notes.add('有控件嵌套太深，里面的内容没有导出。');
      return;
    }
    final a = _attrs(n);
    switch (n.type) {
      case 'text':
        out.writeln('$pad<p$a>${_content(n)}</p>');
      case 'button':
        out.writeln('$pad<button type="button"$a>${_content(n)}</button>');
      case 'image':
        final name = dyn(n, 'src');
        if (name != null) {
          // 地址会变：有地址显示图片，空着显示占位块。
          out.writeln('$pad<img v-if="$name"$a :src="$name" alt="">');
          out.writeln('$pad<div v-else$a role="img" aria-label="图片占位"></div>');
        } else {
          final src = n.strProp('src');
          out.writeln(src == null ? '$pad<div$a role="img" aria-label="图片占位"></div>' : '$pad<img$a${vueAttr('src', src)} alt="">');
        }
      case 'input':
        final value = dyn(n, 'value');
        out.writeln('$pad<input$a${_bindable(n, 'placeholder')}${value == null ? '' : ' :value="$value"'}>');
      case 'list':
        out.writeln('$pad<ul$a>');
        final items = n.props['items'];
        for (final item in items is List ? items : const <Object?>[]) {
          out.writeln('$pad  <li>${vueText('$item')}</li>');
        }
        out.writeln('$pad</ul>');
      case 'divider':
        out.writeln('$pad<hr$a>');
      case 'spacer':
        out.writeln('$pad<div$a></div>');
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
        out.writeln('$pad<${plan.name}$a$values />');
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

String _sfc({required List<String> script, required String template, required String css}) {
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
  final varNames = {for (final v in logic.variables) v.name: names.take(v.name, tag: 'var')};
  final states = LcPropStates(names);
  final writer = JsLogicWriter(doc, VueJsTarget(varNames, states, notes));

  // 先翻处理函数：翻的过程中才知道哪些控件属性被用到了。
  final functions = <String>[];
  for (var i = 0; i < logic.handlers.length; i++) {
    final h = logic.handlers[i];
    functions
      ..add('// ${jsComment(describeHandler(h, doc))}')
      ..add('function ${handlers.names[i]}(${h.event == 'load' ? '' : 'event'}) {')
      ..addAll([for (final l in writer.blocks(h.body, event: h.event)) '  $l'])
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

  final template = _Template(prefix: '', plans: plans, notes: notes, dyn: (n, prop) => states.of(n, prop)?.name, events: eventsOf, importDir: './components/')..node(doc.root, 1);

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
  return _sfc(script: script, template: template.out.toString(), css: lcCollectCss(doc.root, '', notes));
}

String _propType(LcComponentProp p) => switch (p.type) {
  'number' => 'Number',
  'bool' => 'Boolean',
  _ => 'String',
};

String _component(LcComponentPlan plan, LcComponentPlans plans, List<String> notes) {
  final def = plan.def;
  final prefix = lcComponentPrefix(def);
  final template = _Template(prefix: prefix, plans: plans, notes: notes, dyn: (n, prop) => lcBoundAttr(plan, n, prop, notes), events: (_) => const {}, ownerId: def.id, importDir: './')
    ..node(def.root, 1);
  final script = <String>[
    '// 自定义组件：${jsComment(def.name, 60)}',
    ...template.imports(),
    if (def.props.isNotEmpty) ...['', 'defineProps({', for (final p in def.props) '  ${plan.attrs[p.name]}: { type: ${_propType(p)}, default: ${lcPropDefaultLiteral(p)} },', '});'],
  ];
  return _sfc(script: script, template: template.out.toString(), css: lcCollectCss(def.root, prefix, notes));
}
