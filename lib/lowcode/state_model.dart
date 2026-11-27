/// 状态放在哪儿（第 5 期，设计见 docs/blocks-v5-parts/E-editor-components.md §10.8）。
///
/// - **页面级**：就是每页自己那份“变量”（`page.logic.variables`）。“现在的变量自动就是状态”——同一份表，
///   积木编辑器的变量面板和搭建页的“状态”页是它的两个入口，旧页面什么都不用改。
/// - **项目级**（跨页共用）：页面文件最外层的 `state` 字段，一个数组，每项的写法和页面变量一模一样。
///   这一版的模型不认识这个字段，它原样待在 `LcDocument.more` 里；这里是读写它的地方。
/// - 重名：页面里有同名的，页面自己的优先（这一页看不到项目级那个）。
///
/// 读不懂的项（名字不合规矩、不是对象）不解释、原样留着，写回去时排在后面。
library;

import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 最外层放项目级状态的字段名。
const String kLcProjectStateKey = 'state';

/// 项目级状态（读出来的是副本，改它不会动文档；要改用 [lcEditProjectStates]）。重名只留第一个。
List<LcVariable> lcProjectStates(LcDocument doc) {
  final raw = doc.more[kLcProjectStateKey];
  if (raw is! List) return const [];
  final seen = <String>{};
  return [
    for (final item in raw)
      if (LcVariable.tryParse(item, wide: true) case final v? when seen.add(v.name)) v,
  ];
}

/// 改项目级状态：[change] 拿到现在的那份表，随便增删改；改完整份写回去。空了就把字段去掉。
void lcEditProjectStates(LcDocument doc, void Function(List<LcVariable> states) change) {
  final raw = doc.more[kLcProjectStateKey];
  final list = lcProjectStates(doc).toList();
  change(list);
  final kept = [
    if (raw is List)
      for (final item in raw)
        if (LcVariable.tryParse(item, wide: true) == null) item,
  ];
  final seen = <String>{};
  final out = <dynamic>[
    for (final v in list)
      if (LcVariable.namePattern.hasMatch(v.name) && seen.add(v.name)) v.toJson(),
    ...kept,
  ];
  if (out.isEmpty) {
    doc.more.remove(kLcProjectStateKey);
  } else {
    doc.more[kLcProjectStateKey] = out;
  }
}

/// 一个状态和它在哪一层。
class LcStateRef {
  const LcStateRef(this.variable, {required this.project});
  final LcVariable variable;

  /// 是不是项目级的。
  final bool project;
  String get name => variable.name;
}

/// 当前这一页看得到的全部状态：先是这一页自己的，再是没被盖住的项目级的。
List<LcStateRef> lcStatesInScope(LcDocument doc) {
  final own = {for (final v in doc.logic.variables) v.name};
  return [
    for (final v in doc.logic.variables) LcStateRef(v, project: false),
    for (final v in lcProjectStates(doc))
      if (!own.contains(v.name)) LcStateRef(v, project: true),
  ];
}

/// 按名字找状态：页面的优先，再找项目级的。
LcStateRef? lcStateOf(LcDocument doc, String name) {
  final own = doc.logic.variable(name);
  if (own != null) return LcStateRef(own, project: false);
  for (final v in lcProjectStates(doc)) {
    if (v.name == name) return LcStateRef(v, project: true);
  }
  return null;
}

/// 这一页用得到的项目级状态的名字（没被页面同名的盖住的）。
Set<String> lcProjectNamesInScope(LcDocument doc) => {
  for (final s in lcStatesInScope(doc))
    if (s.project) s.name,
};

/// 类型的叫法。
String lcStateTypeLabel(String type) => switch (type) {
  'number' => '数字',
  'bool' => '是 / 否',
  'list' => '列表',
  'record' => '记录',
  _ => '文字',
};
