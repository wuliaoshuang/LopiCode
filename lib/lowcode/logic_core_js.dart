/// 新路的页面逻辑在三种导出里共用的那几段 JS（积木第 5 版·前端 1）。
///
/// 一页的逻辑用了新功能（[lcDocUsesCore]）才走这里：页面逻辑 → 语言核心的程序（logic_to_core.dart）→ 浏览器目标生成一个
/// `lcProgram(lc, lcHost)`。导出文件里放三段：
///
/// - [LcCoreJs.top]：浏览器小库 `lcRuntime`、页面宿主 `lcPageHost`、这一页的程序 `lcProgram`（和导出方式无关，放在最外层）。
/// - [LcCoreJs.boot]：一个 `lcBoot()` 函数：照这种导出放状态、放控件属性的办法做一张读写表，开工，交回页面宿主。
///   读写表里每一格怎么读怎么写，直接用这种导出原来的写法（[JsTarget]），所以“改了以后怎么让界面跟着变”和老路是同一套。
/// - [LcCoreJs.body]：每个处理函数里那一句——把事件转给页面宿主（同一个控件同一个事件有好几个处理时，第一个函数转一次，全都会做）。
///
/// 没用新功能的页面不走这里，导出和以前逐字节一样。
library;

import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/gen2_browser.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/rt2_browser.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_framework_common.dart' show lcInitialLiteral;
import 'package:lopicode/lowcode/export_html_repeat.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/front_emit_bridge.dart';
import 'package:lopicode/lowcode/logic_expr.dart' show kWritableProps;
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_libs.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_to_core.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/page_host_js.dart';

/// 新路的脚本开头那几句“怎么读”。
const List<String> kLcCoreReadme = [
  '// - 这一页的逻辑用了新积木（函数、类、库……），走的是“语言核心”这条路：整页逻辑是下面的 lcProgram；',
  '//   它通过页面宿主 lcPageHost 读写状态和控件、接事件。状态和控件属性放在哪，看 lcBoot 里的那张读写表。',
  '// - 旧积木的规矩没变：加减乘除按数字算，转不了的当 0；“等一会儿”“请求网址”只管它们里面的积木。',
];

class LcCoreJs {
  LcCoreJs._(this.top, this.boot, this._bodies, this.problems);
  final List<String> top;
  final List<String> boot;
  final List<List<String>> _bodies;

  /// 这一页的逻辑导不出来的原因（库不在、类型检查没过……）。不空时 [top] 是空的，处理函数都是空的。
  final List<String> problems;

  /// 第 [i] 个处理函数里的语句。
  List<String> body(int i) => i < _bodies.length ? _bodies[i] : const [];
}

/// 多页面的 Vue / React 导出里，小库和页面宿主抽出来的那个共用文件（和页面文件放在一起）。
const String kLcCoreSharedFile = 'lcCore.js';

/// 哪几页的小库和页面宿主改成从 [kLcCoreSharedFile] 引进来（多页面导出时由 `_exportSite` 标上；没标的和以前逐字节一样）。
final Expando<bool> lcCoreSharedOf = Expando<bool>('lcCoreShared');

/// 走新路的页面有两页以上才抽：给这几页标上，交回要不要出共用文件。
bool lcMarkCoreShared(Iterable<LcDocument> views) {
  final core = [
    for (final v in views)
      if (lcDocUsesCore(v)) v,
  ];
  if (core.length < 2) return false;
  for (final v in core) {
    lcCoreSharedOf[v] = true;
  }
  return true;
}

/// 共用文件的内容：小库 `lcRuntime` 和页面宿主 `lcPageHost`，一字不改，最后导出这两个名字。
String lcCoreSharedSource() => [
  '// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。',
  '// 语言核心的浏览器小库（lcRuntime）和页面宿主（lcPageHost）：这个项目里所有页面共用这一份。',
  kRt2BrowserSource.trim(),
  '',
  kLcPageHostJs.trim(),
  '',
  'export { lcRuntime, lcPageHost };',
  '',
].join('\n');

/// 这一页走新路时交回那几段；不走交回 null。[hash]＝“去页面”改地址栏里 # 后面那段（Vue / React）；否则换到 `页名.html`。
/// [listen]＝读写表里带“往控件上挂事件”（纯网页用：这时不需要一个个处理函数）。
LcCoreJs? lcCoreJsFor(LcDocument doc, JsTarget target, List<String>? notes, {LcVariable? Function(String name)? lookup, required bool hash, bool listen = false}) {
  if (!lcDocUsesCore(doc)) return null;
  // 新的页面逻辑（`logic.front`，一份前端这一边的积木文档）直接出程序；旧积木走新路（用了库的旧页面）照 A2 的翻法。
  final front = lcFrontOf(doc.logic);
  final List<String> problems, skipped;
  final Set<String> states;
  final Set<(String, String)> props;
  String? program;
  if (front != null) {
    // 组件实例摊开过的文档（纯网页）：对着页面的检查要对着摊开以前的页面查（实例还是实例）。
    final source = lcExportSource(doc);
    final out = lcFrontProgram(front);
    final touch = lcFrontTouch(front);
    // 对着页面才查得出的错（帽子挂的控件没了、“这一项”用在重复外面、去页面少带参数……）也拦。
    problems = [...out.problems, for (final i in lcFrontPageIssues(source, source.pages.where((p) => p.id == doc.page.id).firstOrNull ?? doc.page, front)) '${i.where}：${i.problem}'];
    skipped = out.skipped;
    program = problems.isEmpty ? out.code : null;
    // 库里的函数可以按名字读写状态，所以页面声明过的状态全都进读写表。
    states = {for (final v in doc.logic.variables) v.name, ...touch.states};
    props = touch.props;
  } else {
    final built = lcLogicToCore(doc, lookup: lookup, pageUrl: (p) => hash ? '#/${p.id}' : '${lcPageFileBase(doc, p.id)}.html');
    problems = [...built.problems];
    skipped = built.skipped;
    states = built.states;
    props = built.props;
    if (problems.isEmpty) {
      try {
        program = gen2BrowserProgram(built.program!);
      } on LangUnsupported catch (e) {
        problems.add(e.message);
      }
    }
  }
  for (final s in skipped) {
    notes?.add('页面逻辑：$s');
  }
  if (program == null) {
    notes?.add('这一页的逻辑没有导出：${problems.join('；')}');
    return LcCoreJs._(
      const [],
      ['// 这一页的逻辑没有导出：${jsComment(problems.join('；'))}', 'function lcBoot() {', '  return { emit() {}, emitLife() {} };', '}', ''],
      [for (final _ in doc.logic.handlers) const []],
      problems,
    );
  }

  LcVariable? find(String name) => lookup == null ? doc.logic.variable(name) : lookup(name);
  final boot = <String>['// 开工：做一张读写表（状态、控件属性各放在哪），把这一页的程序跑起来，交回页面宿主。', 'function lcBoot() {', '  const lcT = {', '    state(name) {', '      switch (name) {'];
  for (final name in states) {
    final v = find(name);
    if (v == null) continue;
    boot.add('        case ${jsString(name)}:');
    if (v.isDerived) {
      boot.add('          return [() => ${target.readVar(v)}, null];');
    } else {
      boot
        ..add('          return [() => ${target.readVar(v)}, (lcV) => {')
        ..addAll([for (final l in target.writeVar(v, 'lcV')) '            $l'])
        ..add('          }];');
    }
  }
  boot.addAll(['      }', '      return null;', '    },', '    prop(id, prop) {', '      switch (id + " " + prop) {']);
  for (final (id, prop) in props) {
    final node = doc.find(id);
    if (node == null) continue;
    boot.add('        case ${jsString('$id $prop')}:');
    final read = '() => ${target.readProp(node, prop).code}';
    if (kWritableProps.contains(prop)) {
      boot
        ..add('          return [$read, (lcV) => {')
        ..addAll([for (final l in target.writeProp(node, prop, 'lcV')) '            $l'])
        ..add('          }];');
    } else {
      boot.add('          return [$read, null];');
    }
  }
  boot.addAll([
    '      }',
    '      return null;',
    '    },',
    if (listen) ...['    listen(id, type, f) {', '      lcOn(id, type, f);', '    },'],
    // 新的页面逻辑才有的：这一页是谁、去别的页怎么去（带的参数由页面宿主存取）、“重复”出来的控件是第几份。
    if (front != null) ...[
      '    page: ${jsString(doc.page.id)},',
      ...['    item(id, ev) {', '      for (let el = ev && ev.target; el; el = el.parentNode) {', '        if (el.lcAt) return el.lcAt;', '      }', '      return null;', '    },'],
      '    go(id) {',
      '      switch (id) {',
      for (final p in doc.pages)
        if (p.id != doc.page.id) ...[
          '        case ${jsString(p.id)}:',
          hash ? '          location.hash = ${jsString('#/${p.id}')};' : '          location.href = ${jsString('${lcPageFileBase(doc, p.id)}.html')};',
          '          return true;',
        ],
      '      }',
      '      return false;',
      '    },',
    ],
    '  };',
    '  const lcRt = lcRuntime(globalThis);',
    '  const lcHost = lcPageHost(lcRt, lcT);',
    '  lcProgram(lcRt, lcHost);',
    '  return lcHost;',
    '}',
    '',
  ]);

  // 每个处理函数：同一个控件同一个事件，第一个函数转一次（宿主那边登记过的全都会做）；“页面打开时”也一样。
  final seen = <String>{};
  final bodies = <List<String>>[];
  for (final h in doc.logic.handlers) {
    final node = h.target == null ? null : doc.find(h.target!);
    final String key, call;
    final bridge = lcEmitBridgeOf(h);
    if (bridge != null) {
      // 组件实例发出来的事件（front_emit_bridge.dart）：转给页面宿主，帽子“当〔实例〕发出〔事件〕”登记在 (实例, "emit:事件名") 上。
      // 组件文件发的：数据在事件对象的 detail 里；摊开的实例：数据是一个个式子，当场算。
      // 纯网页里摊开的实例放在“重复”里：式子里读“这一项 / 第几个”的地方，从点到的那一份元素上记着的（`el.lcAt`）读。
      final rep = hash || bridge.data == null ? null : _repeatAround(doc, h.target);
      final sb = rep == null ? null : lcScopedBody([LcBlock(op: kLcEmitBridgeOp, args: bridge.data!)], {rep.item, rep.index});
      final scoped = sb != null && sb.used;
      final data = scoped ? sb.body.single.args : bridge.data;
      final writer = scoped ? JsLogicWriter(doc, LcScopedDomTarget(sb.code), lookup: (name) => sb.vars[name] ?? find(name)) : JsLogicWriter(doc, target, lookup: lookup);
      final lcData = data == null ? '(event && event.detail) || {}' : '{ ${[for (final d in data.entries) '${jsString(d.key)}: ${writer.expr(d.value).code}'].join(', ')} }';
      bodies.add([
        if (scoped) ...[
          'const lcS = Object.create(null);',
          'for (let el = event && event.target; el; el = el.parentNode) {',
          '  if (el.lcAt) {',
          '    lcS[${jsString(rep!.item)}] = el.lcAt.item;',
          '    lcS[${jsString(rep.index)}] = el.lcAt.index;',
          '    break;',
          '  }',
          '}',
        ],
        'lcPage.emit(${jsString(bridge.instance)}, ${jsString('emit:${bridge.event}')}, { lcData: $lcData });',
      ]);
      continue;
    }
    if (h.event == 'load') {
      key = 'load';
      call = 'lcPage.emitLife("mounted");';
    } else if ((h.event == 'click' || h.event == 'input') && node != null && isSafeNodeId(node.id)) {
      key = '${node.id} ${h.event}';
      call = 'lcPage.emit(${jsString(node.id)}, "${h.event}", event);';
    } else {
      bodies.add(const ['// 没有挂上（触发它的控件不在页面里，或者不认识的事件）']);
      continue;
    }
    bodies.add(seen.add(key) ? [call] : const ['// 和前面同一个事件的处理一起做了（都登记在页面宿主里）']);
  }
  return LcCoreJs._(
    [
      if (lcCoreSharedOf[doc] == true) ...[
        '// —— 语言核心的浏览器小库和页面宿主：所有页面共用，在 $kLcCoreSharedFile 里 ——',
        "import { lcRuntime, lcPageHost } from './$kLcCoreSharedFile';",
      ] else ...[
        '// —— 语言核心的浏览器小库（每份导出都一样）——',
        ...kRt2BrowserSource.trim().split('\n'),
        '',
        ...kLcPageHostJs.trim().split('\n'),
      ],
      '',
      '// —— 这一页的逻辑 ——',
      ...program.trim().split('\n'),
      '',
    ],
    boot,
    bodies,
    const [],
  );
}

/// 没用绑定的纯网页，新路的整份 logic.js。
String exportCoreLogicJs(LcDocument doc, {List<String>? notes}) {
  const target = DomJsTarget();
  final core = lcCoreJsFor(doc, target, notes, hash: false, listen: true)!;
  final out = StringBuffer()
    ..writeln('// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。')
    ..writeln('//')
    ..writeln('// 怎么读这份脚本：')
    ..writeln('// - 状态都在 state 里。状态改了以后，界面上不会自动跟着变（这一页没有用数据绑定）；要让界面变，用“改控件”积木。');
  kLcCoreReadme.forEach(out.writeln);
  out
    ..writeln('"use strict";')
    ..writeln()
    ..writeln('// 状态')
    ..writeln('const state = {');
  final seen = <String>{};
  for (final v in doc.logic.variables) {
    if (!seen.add(v.name)) continue;
    out.writeln('  ${isJsIdentifier(v.name) ? v.name : '[${jsString(v.name)}]'}: ${lcInitialLiteral(v)},');
  }
  out
    ..writeln('};')
    ..writeln()
    ..writeln(lcJsDomRuntime.trim())
    ..writeln();
  [...core.top, ...core.boot].forEach(out.writeln);
  out
    ..writeln('// 页面准备好以后：开工（处理都挂到控件上），再做“当页面放上以后”。')
    ..writeln('let lcPage = null;')
    ..writeln('function lcStart() {')
    ..writeln('  lcPage = lcBoot();');
  // 摊开的组件实例往外发事件：页面宿主自己不会去挂（它只挂帽子点名的控件），这里替它把“组件里的那个控件”接上。
  for (var i = 0; i < doc.logic.handlers.length; i++) {
    final h = doc.logic.handlers[i];
    final node = h.target == null ? null : doc.find(h.target!);
    if (lcEmitBridgeOf(h) == null || core.body(i).isEmpty || node == null || !isSafeNodeId(node.id) || (h.event != 'click' && h.event != 'input')) continue;
    out.writeln('  lcOn(${jsString(node.id)}, "${h.event}", (event) => {');
    for (final line in core.body(i)) {
      out.writeln('    $line');
    }
    out.writeln('  });');
  }
  out
    ..writeln('  lcPage.emitLife("mounted");')
    ..writeln('}')
    ..writeln()
    ..writeln('if (document.readyState === "loading") {')
    ..writeln('  document.addEventListener("DOMContentLoaded", lcStart);')
    ..writeln('} else {')
    ..writeln('  lcStart();')
    ..writeln('}');
  return out.toString();
}

/// 这个控件外面最近的那层“重复”带出的名字（没在“重复”里：null）。
({String item, String index})? _repeatAround(LcDocument doc, String? id) {
  if (id == null) return null;
  ({String item, String index})? hit;
  bool walk(LcNode n, ({String item, String index})? at, int depth) {
    if (depth > 64) return false;
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    final here = rep == null ? at : (item: rep.item, index: rep.index);
    if (n.id == id) {
      hit = here;
      return true;
    }
    return n.children.any((c) => walk(c, here, depth + 1));
  }

  walk(doc.root, null, 0);
  return hit;
}
