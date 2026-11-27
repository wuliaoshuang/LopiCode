/// Flutter 导出“会动的那一路”：项目里用了主题变量、状态与绑定、断点、状态样式、网格中的任何一样时走这里
/// （一样都没用的项目走 export_dart.dart 原来的路，结果和以前逐字节一样）。
///
/// 导出的代码是这样的：
/// - **主题变量**集中在文件末尾的 `LcVars` 类里（颜色是 `Color`、长度是 `double`）；用到变量的地方写 `LcVars.名字`。
/// - **状态**：有绑定的页面是 StatefulWidget，这一页的状态是 State 类里 `s_` 开头的字段（派生的是 getter）；
///   跨页共用的在 `LcAppState` 里。绑了状态的地方直接读它们，状态变了界面重画。
///   输入框、多行输入框、开关、勾选框、单选组、下拉选择的双向绑定会把值写回状态。
///   积木逻辑这一份一直不导出（按钮的 `onPressed` 是空的），在自己的代码里用 `update(() => s_xxx = 新值)` 改状态。
/// - **绑定**：文字 / 属性读状态；重复是列表里的 `for`；显示条件、存在条件是列表里的 `if`；
///   样式绑定认底色、文字颜色、字号、内外边距、圆角、间距、宽、高；类名开关导不出（见 export_dart_live_bind.dart 里的说明）。
/// - **断点**：每一档屏宽（手机 / 平板 ≥768 / 桌面 ≥1024）各有一个 build 方法，按 `MediaQuery` 的宽度挑。
/// - **状态样式**（按钮按下 / 禁用的底色和文字颜色、输入框聚焦的边框颜色）、**网格**（等宽 N 列、跨列）。
/// 导不出来的东西一条一句写在导出文件的开头。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_dart_hook.dart';
import 'package:lopicode/lowcode/export_dart_live_bind.dart';
import 'package:lopicode/lowcode/export_dart_live_runtime.dart';
import 'package:lopicode/lowcode/export_dart_live_tree.dart';
import 'package:lopicode/lowcode/export_dart_v3.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/state_model.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

/// 这个项目要不要走“会动的那一路”。
bool dartLiveWanted(LcDocument doc) {
  var yes = false;
  lcEachStyleMap(doc, (decl) {
    if (!yes && decl.values.any((v) => v is String && v.contains('var(--'))) yes = true;
  });
  void node(LcNode n, int depth) {
    if (yes || depth > LcNode.maxDepth * 4) return;
    if (lcHasBindings(n) || lcHasBp(n) || lcHasStates(n) || (n.style.isNotEmpty && lcIsGrid(n.style))) yes = true;
    for (final c in n.children) {
      node(c, depth + 1);
    }
  }

  for (final p in doc.pages) {
    node(p.root, 0);
  }
  for (final c in doc.components) {
    node(c.root, 0);
  }
  return yes;
}

const Map<String, String> _tierMethod = {'tablet': '_buildTablet', 'desktop': '_buildDesktop'};

/// 一次“会动的”导出（一个文件）。用法：每一页调 [pageClass]，最后取 [tail] 和 [header]。
class DartLiveExport {
  DartLiveExport(this.doc) : vars = DartLiveVars(lcThemeOf(doc).values), subs = DartLiveSubs(jsonEncode(doc.toJson()));

  final LcDocument doc;
  final DartLiveVars vars;
  final DartLiveSubs subs;
  final Set<String> _notes = {};
  final StringBuffer _code = StringBuffer();
  var _anyState = false, _anyBp = false, _anyProject = false;

  bool _usesBp(LcNode n, String bp, [int depth = 0]) => depth <= LcNode.maxDepth * 4 && (lcBpStyle(n, bp).isNotEmpty || n.children.any((c) => _usesBp(c, bp, depth + 1)));

  /// 当前这一页（[doc] 要停在这一页上）的类。
  String pageClass(String name) {
    final tree = expandedTree(doc);
    final stateful = lcTreeHasBindings(tree);
    final scope = lcStatesInScope(doc);
    final pageStates = {
      for (final s in scope)
        if (!s.project) s.name: s.variable,
    };
    final projectStates = {
      for (final s in scope)
        if (s.project) s.name: s.variable,
    };
    final gen = DartLiveGen(subs: subs, vars: vars, notes: _notes, pageStates: stateful ? pageStates : const {}, projectStates: stateful ? projectStates : const {});
    final tiers = <(String?, String)>[];
    final dialogs = StringBuffer();
    dartLive = gen;
    try {
      LcNode? phone;
      for (final bp in <String?>[null, ...kLcBreakpoints]) {
        if (bp != null && !_usesBp(tree, bp)) continue;
        final t = DartLiveTier(bp, vars, subs, _notes).tree(tree);
        phone ??= t;
        final body = subs.apply(dartNode(t, null, 3));
        if (tiers.isEmpty || tiers.last.$2 != body) tiers.add((bp, body));
      }
      // 弹窗不在控件树里：每个弹窗一个方法（按手机那一档的样子出）。
      for (final d in dartDialogsOf(phone!)) {
        var code = subs.apply(dartDialogMethodCode(gen.dialog(d), dartNode));
        if (stateful) {
          // 弹窗是另一条路由，页面重画带不动它：让它自己听着状态变没变。
          code = code
              .replaceFirst('  static Future<void>', '  Future<void>')
              .replaceFirst('builder: (context) => AlertDialog(', 'builder: (context) => ListenableBuilder(listenable: _lcChanged, builder: (context, child) => AlertDialog(');
          final end = code.lastIndexOf(',\n    );\n  }');
          if (end > 0 && code.contains('ListenableBuilder(')) code = code.replaceRange(end, end, ')');
        }
        dialogs.write('\n$code');
      }
    } finally {
      dartLive = null;
    }
    if (tiers.length > 1) _anyBp = true;

    final build = StringBuffer('  @override\n  Widget build(BuildContext context) {\n');
    if (tiers.length == 1) {
      build.write('    return ${tiers.single.$2};\n  }\n');
    } else {
      build.write('    // 按屏幕宽度取样子：从宽到窄，先对上哪一档用哪一档。\n    final width = MediaQuery.sizeOf(context).width;\n');
      for (final t in tiers.reversed) {
        build.write(t.$1 == null ? '    return _buildPhone(context);\n  }\n' : '    if (width >= ${kLcBpMinWidth[t.$1]}) return ${_tierMethod[t.$1]}(context);\n');
      }
      for (final t in tiers) {
        build.write(
          '\n  /// ${lcBpLabel(t.$1)}${t.$1 == null ? '' : '（屏幕宽度 ≥ ${kLcBpMinWidth[t.$1]}）'}的样子。\n  Widget ${t.$1 == null ? '_buildPhone' : _tierMethod[t.$1]}(BuildContext context) {\n    return ${t.$2};\n  }\n',
        );
      }
    }
    final String out;
    if (!stateful) {
      out = 'class $name extends StatelessWidget {\n  const $name({super.key});\n\n$build$dialogs}\n';
    } else {
      _anyState = true;
      final usesProject = projectStates.isNotEmpty;
      if (usesProject) _anyProject = true;
      final fields = [
        for (final v in pageStates.values)
          v.isDerived ? '  Object? get ${dartStateIdent(v.name)} => ${gen.expr(v.derived)};\n' : '  Object? ${dartStateIdent(v.name)} = ${dartLiveLiteral(v.initial)};\n',
      ].join();
      final usesFields = '$build$dialogs'.contains('_lcField(');
      out =
          '''class $name extends StatefulWidget {
  const $name({super.key});

  @override
  State<$name> createState() => ${name}State();
}

/// 这一页的状态是下面 s_ 开头的那几个。在自己的代码里改状态：`update(() => s_xxx = 新值)`，界面自己重画。
class ${name}State extends State<$name> {
$fields${usesFields ? '  final Map<String, TextEditingController> _lcFields = {};\n' : ''}  final _lcChanged = ValueNotifier<int>(0);

  /// 改状态都走这里：`update(() => s_xxx = 新值)`。
  void update(void Function() change) {
    setState(change);
    _lcChanged.value++;
  }
${usesProject ? '''

  void _lcOnApp() {
    if (mounted) update(() {});
  }

  @override
  void initState() {
    super.initState();
    LcAppState.changed.addListener(_lcOnApp);
  }
''' : ''}
  @override
  void dispose() {
${usesProject ? '    LcAppState.changed.removeListener(_lcOnApp);\n' : ''}${usesFields ? '    for (final c in _lcFields.values) {\n      c.dispose();\n    }\n' : ''}    _lcChanged.dispose();
    super.dispose();
  }
${usesFields ? r'''

  /// 双向绑定的输入框用的控制器：状态被别处改了，下一帧把框里的字对齐（正在打的字不打断）。
  TextEditingController _lcField(String id, Object? value, {bool number = false}) {
    final text = _lcText(value);
    final c = _lcFields.putIfAbsent(id, () => TextEditingController(text: text));
    final same = number ? _lcNum(c.text) == _lcNum(value) : c.text == text;
    if (!same) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && c.text != text) c.text = text;
      });
    }
    return c;
  }
''' : ''}
$build$dialogs}
''';
    }
    _code.write(out);
    return out;
  }

  /// 文件末尾：跨页共用的状态、主题变量、用到的小函数。
  String tail() {
    final app = StringBuffer();
    if (_anyProject) {
      final states = lcProjectStates(doc);
      final names = {for (final v in states) v.name};
      String? resolve(String name) => names.contains(name) ? 'LcAppState.$name' : null;
      app.write('\n/// 跨页共用的状态。改它：`LcAppState.update(() => LcAppState.xxx = 新值)`，开着的页面都跟着变。\nabstract final class LcAppState {\n');
      for (final v in states) {
        app.write(v.isDerived ? '  static Object? get ${v.name} => ${dartLiveExpr(v.derived, resolve)};\n' : '  static Object? ${v.name} = ${dartLiveLiteral(v.initial)};\n');
      }
      app.write('\n  static final changed = ValueNotifier<int>(0);\n\n  static void update(void Function() change) {\n    change();\n    changed.value++;\n  }\n}\n');
    }
    final varsCode = vars.isEmpty ? '' : vars.classCode(lcThemeOf(doc).labels);
    return '$app$varsCode${dartLiveRuntimeFor('$_code$app')}';
  }

  /// 文件开头的说明。
  String header() => [
    if (!vars.isEmpty) '// 主题变量：集中在文件末尾的 LcVars 里，改那里一处，用到的地方全跟着变。\n',
    if (_anyState) ...[
      '// 状态与绑定：状态是页面 State 类里 s_ 开头的字段${_anyProject ? '（跨页共用的在 LcAppState 里）' : ''}，绑了它的地方跟着变；输入框、开关这些会把值写回去。\n',
      '// 积木逻辑这一份不导出（按钮的 onPressed 是空的）：在自己的代码里用 update(() => s_xxx = 新值) 改状态。\n',
    ],
    if (_anyBp) '// 断点：按屏幕宽度取样子（平板 ≥768、桌面 ≥1024），见各页的 build。\n',
    if (_notes.isNotEmpty) '// 没有导出的：\n',
    for (final n in _notes) '// · $n\n',
  ].join();
}
