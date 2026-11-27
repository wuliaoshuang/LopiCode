/// 断点（第 4 期）：节点上的 `responsive` 字段，只存“屏幕更宽时和手机不一样的那几条样式”
/// （格式见 docs/lowcode-page-format-v3.md）：`{"tablet": {"style": {…}}, "desktop": {"style": {…}}}`。
///
/// 固定三档，手机优先：不带条件的样式＝手机（默认）；平板 ≥768、桌面 ≥1024 各有一份差别。
/// 宽的档叠在窄的上面：桌面上看到的是 手机 + 平板的差别 + 桌面的差别（和导出的 `@media (min-width: …)` 一个规矩）。
/// 这一版只解释每档的 `style`；每档里别的键（格式里留的 `props`）、别的档名都不解释，原样留着。
///
/// 另外这里有“画布按什么看”（[LcViewEnv]）：主题变量的值 + 现在看的是哪一档；
/// [lcViewNode] 把一个节点换成“在这个条件下的样子”（变量换成值、断点的差别并进来）。画布和面板共用。
library;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_preview.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

/// 档名，从窄到宽。
const List<String> kLcBreakpoints = ['tablet', 'desktop'];
const Map<String, String> kLcBpLabels = {'tablet': '平板', 'desktop': '桌面'};

/// 从多宽起算这一档（CSS 像素）；画布切到这一档时页面也画这么宽。
const Map<String, int> kLcBpMinWidth = {'tablet': 768, 'desktop': 1024};

/// 档的叫法；null＝手机（默认）。
String lcBpLabel(String? bp) => bp == null ? '手机' : kLcBpLabels[bp] ?? bp;

/// 这一档自己记的差别（不含更窄那档的）；没有是空表。
Map<String, String> lcBpStyle(LcNode n, String bp) {
  final all = n.more['responsive'];
  final b = all is Map ? all[bp] : null;
  final s = b is Map ? b['style'] : null;
  if (s is! Map) return const {};
  return {
    for (final e in s.entries)
      if (e.value is String) '${e.key}': e.value as String,
  };
}

/// 有没有在任何一档写过差别。
bool lcHasBp(LcNode n) => kLcBreakpoints.any((b) => lcBpStyle(n, b).isNotEmpty);

/// 看 [bp] 这一档时叠在手机样式上面的全部差别（平板；桌面＝平板的再叠桌面的）。
Map<String, String> lcBpMerged(LcNode n, String bp) {
  if (n.more['responsive'] == null) return const {};
  final out = <String, String>{};
  for (final b in kLcBreakpoints) {
    out.addAll(lcBpStyle(n, b));
    if (b == bp) break;
  }
  return out;
}

/// 把一档的差别整个换成 [decl]；空表＝这一档清掉。别的档、这一档里别的键原样留着；都空了 `responsive` 字段也去掉。
void lcReplaceBp(LcNode n, String bp, Map<String, String> decl) {
  final old = n.more['responsive'];
  final all = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
  };
  final cur = all[bp];
  final curStyle = cur is Map ? cur['style'] : null;
  // 这一档样式里读不懂的条目（值不是字符串的）原样留着。
  final style = <String, dynamic>{
    if (curStyle is Map)
      for (final e in curStyle.entries)
        if (e.value is! String) '${e.key}': e.value,
    ...decl,
  };
  final entry = <String, dynamic>{
    if (style.isNotEmpty) 'style': style,
    if (cur is Map)
      for (final e in cur.entries)
        if (e.key != 'style') '${e.key}': e.value,
  };
  if (entry.isEmpty) {
    all.remove(bp);
  } else {
    all[bp] = entry;
  }
  if (all.isEmpty) {
    n.more.remove('responsive');
  } else {
    n.more['responsive'] = all;
  }
}

/// 在 [bp] 这一档上改样式：[change] 拿到的是“这一档看到的整份样式”（手机的 + 更窄各档的 + 这一档的差别），
/// 改完以后只把**和下面那几层不一样的**记成这一档的差别；被删掉的条目＝这一档不再管它（回到跟下面一样）。
void lcEditAtBp(LcNode n, String bp, void Function(Map<String, String> style) change) {
  // 先都换成规范写法（简写拆开），不然“改了一条”会被看成“整份都不一样”。
  var below = canonicalDeclarations(n.style);
  for (final b in kLcBreakpoints) {
    if (b == bp) break;
    below = mergeDeclarations(below, lcBpStyle(n, b));
  }
  final seen = mergeDeclarations(below, lcBpStyle(n, bp));
  change(seen);
  lcReplaceBp(n, bp, {
    for (final e in seen.entries)
      if (below[e.key] != e.value) e.key: e.value,
  });
}

/// 画布（和面板）按什么条件看一个节点。
class LcViewEnv {
  const LcViewEnv({this.vars = const {}, this.bp, this.bind});
  static const LcViewEnv plain = LcViewEnv();

  factory LcViewEnv.of(LcDocument doc, [String? bp]) {
    final vars = lcThemeOf(doc).values;
    // 这一页一个绑定都没有：不带绑定环境，画布走的还是原来那条路。
    // 页面里有“用了第 6 期新东西”的组件实例：绑定在定义里，状态要算上每个实例自己的那一份。
    final live = lcTreeHasLiveInstance(doc, doc.root);
    final bind = live ? LcBindEnv.of(lcExportDoc(doc)) : (lcTreeHasBindings(doc.root) ? LcBindEnv.of(doc) : null);
    return vars.isEmpty && bp == null && bind == null ? plain : LcViewEnv(vars: vars, bp: bp, bind: bind);
  }

  /// 主题变量：名字 → 值。
  final Map<String, String> vars;

  /// 现在看的是哪一档；null＝手机。
  final String? bp;

  /// 绑定按什么算（状态的初值 + “重复”带出来的这一项）；null＝不算绑定。
  final LcBindEnv? bind;

  /// 换一个绑定环境（进到“重复”的某一份里）。
  LcViewEnv withBind(LcBindEnv bind) => LcViewEnv(vars: vars, bp: bp, bind: bind);

  bool get isPlain => vars.isEmpty && bp == null && bind == null;
}

/// 一份声明表里的变量换成值；没有变量就是原来那份（同一个对象）。
Map<String, String> lcSubstMap(Map<String, String> decl, Map<String, String> vars) {
  if (!decl.values.any((v) => v.contains('var('))) return decl;
  return {for (final e in decl.entries) e.key: lcSubstVars(e.value, vars)};
}

/// [n] 在 [env] 下的样子：断点的差别并进 `style`、变量换成值。没什么可换的就是 [n] 本身（同一个对象——
/// 画布靠这个判断能不能用记着的样式）。换样式；有绑定时再把绑了的属性换成初值；子节点、别的字段都是原来那份。
LcNode lcViewNode(LcNode n, LcViewEnv env) {
  if (env.isPlain || n.isUnknown) return n;
  final over = env.bp == null ? const <String, String>{} : lcBpMerged(n, env.bp!);
  final merged = over.isEmpty ? n.style : {...n.style, ...over};
  final style = lcSubstMap(merged, env.vars);
  final styled = identical(style, n.style)
      ? n
      : (LcNode(id: n.id, type: n.type, props: n.props, children: n.children, style: style, bind: n.bind, name: n.name, locked: n.locked, hidden: n.hidden, keptProps: n.keptProps, more: n.more)
          ..instSlots = n.instSlots);
  // 绑定换成初值（第 5 期，bind_preview.dart）。
  final bind = env.bind;
  return bind == null ? styled : lcBoundNode(styled, bind);
}
