/// 状态样式：节点上的 `states` 字段，只存“和平时不一样的那几条”（格式见 docs/lowcode-page-format-v3.md）。
///
/// 三种状态：按下（pressed）、禁用（disabled）、聚焦（focused），网页类导出分别写成 `:active` / `:disabled` / `:focus`。
/// 值是 CSS 声明表（和节点的 `style` 一个写法）。不认识的状态名、不是字符串的值都不解释、原样留在文件里。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 状态名，按面板上的顺序。
const List<String> kLcStateNames = ['pressed', 'disabled', 'focused'];

const Map<String, String> kLcStateLabels = {'pressed': '按下', 'disabled': '禁用', 'focused': '聚焦'};

/// 导出成哪个 CSS 伪类。
const Map<String, String> kLcStatePseudo = {'pressed': ':active', 'disabled': ':disabled', 'focused': ':focus'};

/// 能“禁用”的组件：导出的网页里它们是真的表单控件，`:disabled` 才对得上。
const Set<String> kLcCanDisable = {'button', 'input', 'textarea', 'switch', 'select'};

/// 在 [type] 这种组件上设 [state] 的样子不会生效时，给一句说明；会生效是 null。
String? lcStateCaveat(String type, String? state) => state == 'disabled' && !kLcCanDisable.contains(type) ? '这种组件不能禁用，这里设的样子不会生效。能禁用的有：按钮、输入框、多行输入框、开关、下拉选择。' : null;

/// 面板上“状态”一行里，类名开关也算一种“状态”（第四轮 B2）：写成 `class:<类名>`，改的是这条类名成立时的样子。
const String kLcClassStatePrefix = 'class:';

String lcClassState(String className) => '$kLcClassStatePrefix$className';

/// 是类名开关的那种“状态”时返回类名，不是返回 null。
String? lcClassOfState(String? state) => state != null && state.startsWith(kLcClassStatePrefix) ? state.substring(kLcClassStatePrefix.length) : null;

/// 状态在界面上的叫法。
String lcStateLabel(String state) => lcClassOfState(state) == null ? (kLcStateLabels[state] ?? state) : '类名 ${lcClassOfState(state)} 成立';

/// 这个状态下和平时不一样的声明；没有是空表。
Map<String, String> lcStateStyle(LcNode n, String state) {
  final cls = lcClassOfState(state);
  if (cls != null) {
    for (final c in lcClassIfOf(n)) {
      if (c.name == cls) return c.style;
    }
    return const {};
  }
  final all = n.more['states'];
  final s = all is Map ? all[state] : null;
  if (s is! Map) return const {};
  return {
    for (final e in s.entries)
      if (e.value is String) '${e.key}': e.value as String,
  };
}

/// 有没有写过任何状态样式。
bool lcHasStates(LcNode n) => kLcStateNames.any((s) => lcStateStyle(n, s).isNotEmpty);

/// 改一个状态下的一条声明；[value] 传 null 或空＝去掉这条。这个状态空了就整个去掉，三个都空了 `states` 字段也去掉。
/// 别的（这一版不认识的）状态名原样留着。
void lcSetStateDecl(LcNode n, String state, String prop, String? value) {
  final old = n.more['states'];
  final all = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
  };
  final cur = all[state];
  final decl = <String, dynamic>{
    if (cur is Map)
      for (final e in cur.entries) '${e.key}': e.value,
  };
  if (value == null || value.trim().isEmpty) {
    decl.remove(prop);
  } else {
    decl[prop] = value.trim();
  }
  if (decl.isEmpty) {
    all.remove(state);
  } else {
    all[state] = decl;
  }
  if (all.isEmpty) {
    n.more.remove('states');
  } else {
    n.more['states'] = all;
  }
}

/// 把一个状态的声明整个换成 [decl]（面板一次改好几条时用）；空表＝去掉这个状态。别的状态不动。
void lcReplaceState(LcNode n, String state, Map<String, String> decl) {
  final cls = lcClassOfState(state);
  if (cls != null) return lcSetClassIfStyle(n, cls, decl);
  final old = n.more['states'];
  final all = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
  };
  final cur = all[state];
  // 这个状态里这一版看不懂的条目（值不是字符串的）原样留着。
  final kept = <String, dynamic>{
    if (cur is Map)
      for (final e in cur.entries)
        if (e.value is! String) '${e.key}': e.value,
  };
  final next = {...kept, ...decl};
  if (next.isEmpty) {
    all.remove(state);
  } else {
    all[state] = next;
  }
  if (all.isEmpty) {
    n.more.remove('states');
  } else {
    n.more['states'] = all;
  }
}
