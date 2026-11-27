/// 组件盒里“有哪些组件、怎么分类、怎么搜、哪些算常用”的纯逻辑（不带界面）。
///
/// - 一个条目＝一个内置组件类型，或者一个自定义组件。条目的 key：内置的就是类型名（`text`），自定义的是 `component:<id>`。
/// - 分类是固定的几组（第 3 期有了导航、弹层类组件以后多了“导航”“反馈”两组）；没有条目的分类不显示。“常用”排第一，“我的”（自定义组件）排最后。
/// - 搜索按名字和别名（中文别名、英文、拼音），不分大小写，包含就算。
/// - “常用”＝最近用过的 [kPaletteRecentMax] 个（最新的在前）；不够就用内置的起步组件补齐。
library;

import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// “常用”里最多放几个。
const int kPaletteRecentMax = 8;

/// 一次没用过的时候，“常用”里先放这 8 个。
const List<String> kPaletteStarters = ['text', 'button', 'image', 'input', 'container', 'row', 'card', 'list'];

/// 组件盒的分类。
enum PaletteGroup {
  recent('常用'),
  layout('布局'),
  basic('基础'),
  form('表单'),
  show('展示'),
  nav('导航'),
  mine('我的');

  const PaletteGroup(this.label);
  final String label;
}

const Map<String, PaletteGroup> _groupOf = {
  'container': PaletteGroup.layout,
  'row': PaletteGroup.layout,
  'column': PaletteGroup.layout,
  'card': PaletteGroup.layout,
  'spacer': PaletteGroup.layout,
  'text': PaletteGroup.basic,
  'button': PaletteGroup.basic,
  'image': PaletteGroup.basic,
  'input': PaletteGroup.form,
  'list': PaletteGroup.show,
  'divider': PaletteGroup.show,
  'icon': PaletteGroup.basic,
  'textarea': PaletteGroup.form,
  'switch': PaletteGroup.form,
  'checkbox': PaletteGroup.form,
  'radio': PaletteGroup.form,
  'select': PaletteGroup.form,
  'listItem': PaletteGroup.show,
  'appBar': PaletteGroup.nav,
  'bottomNav': PaletteGroup.nav,
  'tabs': PaletteGroup.nav,
  // 弹窗只有一个，不单开一类（分类条在 390 宽上最多放得下 7 个，再多“我的”就被挤出屏幕了）；它是装东西的一层，归布局。
  'dialog': PaletteGroup.layout,
};

/// 搜索用的别名（名字本身不用写）。
const Map<String, List<String>> _aliases = {
  'container': ['盒子', '块', '框', 'div', 'box', 'container', 'rongqi'],
  'row': ['横排', '水平', '一行', 'row', 'hang', 'hengpai'],
  'column': ['竖排', '垂直', '一列', 'column', 'col', 'lie', 'shupai'],
  'card': ['面板', '卡', 'card', 'kapian'],
  'spacer': ['空白', '间隔', '占位', 'spacer', 'kongbai'],
  'text': ['文字', '标题', '段落', '字', 'text', 'label', 'wenben', 'wenzi'],
  'button': ['按键', '点击', 'button', 'btn', 'anniu'],
  'image': ['图', '照片', '图像', 'image', 'img', 'tupian'],
  'input': ['文本框', '输入', '表单', 'input', 'textfield', 'shurukuang'],
  'list': ['清单', '条目', 'list', 'liebiao'],
  'divider': ['分隔线', '横线', '线', 'divider', 'line', 'hr', 'fengexian'],
  'icon': ['图标', '小图', '符号', 'icon', 'tubiao'],
  'textarea': ['多行', '文本域', '留言', '备注', 'textarea', 'duohang'],
  'switch': ['开关', '切换', 'switch', 'toggle', 'kaiguan'],
  'checkbox': ['勾选', '复选', '多选', '打勾', 'checkbox', 'gouxuan'],
  'radio': ['单选', '选项', 'radio', 'danxuan'],
  'select': ['下拉', '选择', '菜单', 'select', 'dropdown', 'xiala'],
  'listItem': ['列表行', '一行', '单元格', '设置项', 'cell', 'listitem', 'liebiaohang'],
  'appBar': ['导航栏', '标题栏', '顶栏', '顶部', 'appbar', 'navbar', 'daohanglan'],
  'bottomNav': ['底栏', '底部导航', '标签栏', 'tabbar', 'bottomnav', 'dibu'],
  'tabs': ['标签页', '页签', '选项卡', 'tabs', 'tab', 'biaoqianye'],
  'dialog': ['弹窗', '对话框', '提示框', '弹层', 'dialog', 'modal', 'tanchuang'],
};

/// 组件盒里的一个条目。
class PaletteEntry {
  const PaletteEntry({required this.type, required this.label, required this.group, this.ref, this.lib});

  /// 来自哪个组件库（库的名字）；项目自己的和内置的是 null。组件盒“我的”里一个库一组。
  final String? lib;

  /// 组件类型；自定义组件是 `component`。
  final String type;
  final String label;
  final PaletteGroup group;

  /// 自定义组件的 id（内置的是 null）。
  final String? ref;

  String get key => ref == null ? type : 'component:$ref';
}

/// 全部条目：内置的按固定顺序，自定义组件排在后面。
List<PaletteEntry> paletteEntries(List<LcComponentDef> components) => [
  for (final type in lcPaletteTypes) PaletteEntry(type: type, label: lcSpecs[type]!.label, group: _groupOf[type] ?? PaletteGroup.basic),
  for (final c in components)
    if (compLibOf(c) == null) PaletteEntry(type: 'component', label: c.name, group: PaletteGroup.mine, ref: c.id),
  for (final c in components)
    if (compLibOf(c) != null) PaletteEntry(type: 'component', label: c.name, group: PaletteGroup.mine, ref: c.id, lib: compLibOf(c)!.name),
];

/// “常用”里放哪些：最近用过的（已经不存在的跳过）在前，不够 [kPaletteRecentMax] 个用起步组件补。
List<PaletteEntry> paletteRecent(List<PaletteEntry> all, List<String> recentKeys) {
  final byKey = {for (final e in all) e.key: e};
  final out = <PaletteEntry>[];
  final seen = <String>{};
  for (final key in [...recentKeys, ...kPaletteStarters]) {
    final e = byKey[key];
    if (e == null || !seen.add(key)) continue;
    out.add(e);
    if (out.length >= kPaletteRecentMax) break;
  }
  return out;
}

/// 某个分类下的条目。
List<PaletteEntry> paletteInGroup(List<PaletteEntry> all, PaletteGroup group, List<String> recentKeys) => group == PaletteGroup.recent
    ? paletteRecent(all, recentKeys)
    : [
        for (final e in all)
          if (e.group == group) e,
      ];

/// 要显示的分类：“常用”总在；别的有条目才显示。
List<PaletteGroup> paletteGroups(List<PaletteEntry> all) => [
  for (final g in PaletteGroup.values)
    if (g == PaletteGroup.recent || all.any((e) => e.group == g)) g,
];

/// 搜索：名字或别名里包含 [query]（去掉首尾空格、不分大小写）。空的 query 返回全部。
List<PaletteEntry> paletteSearch(List<PaletteEntry> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  bool hit(PaletteEntry e) {
    if (e.label.toLowerCase().contains(q)) return true;
    if (e.ref != null) return false;
    return (_aliases[e.type] ?? const <String>[]).any((a) => a.contains(q));
  }

  return [
    for (final e in all)
      if (hit(e)) e,
  ];
}

/// 用了一个条目以后新的“最近用过”：它排到最前，重复的去掉，最多留 [kPaletteRecentMax] 个。
List<String> paletteTouch(List<String> recentKeys, String key) => [key, ...recentKeys.where((k) => k != key)].take(kPaletteRecentMax).toList();

/// 一个搭建页手里的“最近用过”：页面自己建、自己丢；变了通过 [onChanged] 交给页面去存。
class PaletteRecents {
  PaletteRecents({List<String>? keys, this.onChanged}) : keys = keys ?? const [];

  /// 新的在前。
  List<String> keys;
  final void Function(List<String> keys)? onChanged;

  /// 用了一个：排到最前。顺序没变就什么都不做。
  void touch(String key) {
    if (keys.isNotEmpty && keys.first == key) return;
    keys = paletteTouch(keys, key);
    onChanged?.call(keys);
  }
}
