/// 对象数组（单选组 / 下拉的选项、标签页的页签、底部导航的导航项）怎么增删改排——不带界面，合一面板调它。
///
/// 规矩（和 model_v3_components.dart 读文件时的规矩是同一套，这里保证**界面上改出来的永远合规矩**）：
/// - 选项：1–50 项。`value` 不空、最长 80、互不重复——改成空的或者和别的撞了，这次不写、返回原因。新加的发 `opt数字`。
///   “默认选中”记在组件的 `value` 上；改了某项的 `value`、删了某项，默认选中跟着改 / 去掉。
/// - 页签：1–8 项。`id` 是自动发的（`t数字`），界面上不让改（里面的组件靠它认插槽）。删页签连里面的组件一起删。
///   “当前页签”记在 `current` 上。
/// - 导航项：1–5 项。每项一个图标（必有）、一个名字。“当前项”是 `current`（第几个，从 0 数），排序、删除时跟着那一项走。
/// - 都至少留一项：只剩一项时不能删。满了不能加。
library;

import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

enum LcItemsKind {
  options('options', '选项', kLcMaxOptions),
  tabs('tabs', '页签', kLcMaxTabs),
  nav('items', '导航项', kLcMaxNavItems);

  const LcItemsKind(this.prop, this.label, this.max);
  final String prop;
  final String label;
  final int max;
}

/// 这种组件的对象数组是哪一种；没有返回 null。
LcItemsKind? lcItemsKindOf(LcNode n) => switch (n.type) {
  'radio' || 'select' => LcItemsKind.options,
  'tabs' => LcItemsKind.tabs,
  'bottomNav' => LcItemsKind.nav,
  _ => null,
};

List<Map<String, dynamic>> _read(LcNode n, LcItemsKind kind) => [for (final m in lcObjects(n, kind.prop)) Map<String, dynamic>.of(m)];

bool lcItemsCanAdd(LcNode n, LcItemsKind kind) => lcObjects(n, kind.prop).length < kind.max;
bool lcItemsCanRemove(LcNode n, LcItemsKind kind) => lcObjects(n, kind.prop).length > 1;

/// 第 [index] 项是不是“选中 / 当前”的那一项。
bool lcItemIsCurrent(LcNode n, LcItemsKind kind, int index) {
  final all = lcObjects(n, kind.prop);
  if (index < 0 || index >= all.length) return false;
  return switch (kind) {
    LcItemsKind.options => n.props['value'] == all[index]['value'],
    LcItemsKind.tabs => lcCurrentTab(n) == all[index]['id'],
    LcItemsKind.nav => (n.numProp('current') ?? 0).round() == index,
  };
}

/// 把第 [index] 项设成“选中 / 当前”。选项再点一次已经选中的＝不要默认选中。
void lcItemSetCurrent(LcNode n, LcItemsKind kind, int index) {
  final all = lcObjects(n, kind.prop);
  if (index < 0 || index >= all.length) return;
  switch (kind) {
    case LcItemsKind.options:
      if (lcItemIsCurrent(n, kind, index)) {
        n.props.remove('value');
      } else {
        n.props['value'] = all[index]['value'];
      }
    case LcItemsKind.tabs:
      n.props['current'] = all[index]['id'];
    case LcItemsKind.nav:
      n.props['current'] = index;
  }
}

/// 加一项（排在最后）。满了返回 false。
bool lcItemAdd(LcNode n, LcItemsKind kind) {
  if (!lcItemsCanAdd(n, kind)) return false;
  final all = _read(n, kind);
  switch (kind) {
    case LcItemsKind.options:
      final used = {for (final m in all) m['value']};
      var i = all.length + 1;
      while (used.contains('opt$i')) {
        i++;
      }
      all.add({'value': 'opt$i', 'label': '选项 $i'});
    case LcItemsKind.tabs:
      all.add({'id': lcNewTabId(n), 'label': '页签 ${all.length + 1}'});
    case LcItemsKind.nav:
      all.add({'icon': 'star', 'label': '新的'});
  }
  n.props[kind.prop] = all;
  return true;
}

/// 删第 [index] 项。返回一起删掉了几个组件（只有页签会 > 0）；不能删返回 -1。
int lcItemRemove(LcNode n, LcItemsKind kind, int index) {
  final all = _read(n, kind);
  if (all.length <= 1 || index < 0 || index >= all.length) return -1;
  switch (kind) {
    case LcItemsKind.tabs:
      return lcRemoveTab(n, all[index]['id'] as String);
    case LcItemsKind.options:
      if (n.props['value'] == all[index]['value']) n.props.remove('value');
    case LcItemsKind.nav:
      final cur = (n.numProp('current') ?? 0).round();
      if (cur > index || cur >= all.length - 1) n.props['current'] = (cur - 1).clamp(0, all.length - 2);
  }
  all.removeAt(index);
  n.props[kind.prop] = all;
  return 0;
}

/// 第 [index] 项往前（[by]＝-1）或往后（+1）挪一格。到头了返回 false。
bool lcItemMove(LcNode n, LcItemsKind kind, int index, int by) {
  final all = _read(n, kind);
  final to = index + by;
  if (index < 0 || index >= all.length || to < 0 || to >= all.length) return false;
  if (kind == LcItemsKind.nav) {
    final cur = (n.numProp('current') ?? 0).round();
    if (cur == index) {
      n.props['current'] = to;
    } else if (cur == to) {
      n.props['current'] = index;
    }
  }
  final m = all.removeAt(index);
  all.insert(to, m);
  n.props[kind.prop] = all;
  return true;
}

/// 改第 [index] 项的一个键（`label` / `value` / `icon`；导航项还有 `page`＝点了去哪一页）。不合规矩不写，返回给人看的原因；写了返回 null。
String? lcItemSet(LcNode n, LcItemsKind kind, int index, String key, String text) {
  final all = _read(n, kind);
  if (index < 0 || index >= all.length) return '这一项已经不在了';
  if (key == 'value' && kind == LcItemsKind.options) {
    if (text.isEmpty) return '值不能空着';
    if (text.length > 80) return '值最长 80 个字';
    for (var i = 0; i < all.length; i++) {
      if (i != index && all[i]['value'] == text) return '这个值别的选项用了';
    }
    if (n.props['value'] == all[index]['value']) n.props['value'] = text;
  } else if (key == 'icon' && kind == LcItemsKind.nav) {
    if (text.isEmpty) return '导航项要有图标';
  } else if (key == 'page' && kind == LcItemsKind.nav) {
    // 点了去哪一页（页面 id）；空的＝不跳转，把这个键去掉。
    if (text.isEmpty) {
      all[index].remove('page');
      n.props[kind.prop] = all;
      return null;
    }
  } else if (key != 'label') {
    return '这一项不能改';
  }
  all[index][key] = text;
  n.props[kind.prop] = all;
  return null;
}

/// 页签里现在有几个组件（删之前告诉她）。
int lcTabChildCount(LcNode tabs, int index) {
  final all = lcObjects(tabs, 'tabs');
  if (index < 0 || index >= all.length) return 0;
  return lcSlotChildren(tabs, all[index]['id'] as String).length;
}
