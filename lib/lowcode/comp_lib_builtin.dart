/// 内置组件库（第四轮 B5）：应用自带的一份**只读**组件库，标识 `lopi/builtin`（`lopi` 是应用自己留着用的作者段，别人的库用不了这个标识）。
///
/// 里面两类定义（都和页面文件里 `components` 一个写法，读法、装进文档的办法和用户的组件库是同一套）：
/// 1. **现有的封装型内置组件**（卡片、行、列、间隔、分割线、列表、列表行、顶部导航栏）整理出来的定义——
///    每个都是“把那个现成的控件包一层”，给人在“组件库”面板里点开看、“复制一份来改”。组件盒里这八个还是原来那些控件
///    （直接放的是控件本身，不是实例），所以旧页面、旧导出一个字节都不变。
///    底部导航栏、标签页、弹窗没收进来：导航项和页签是成串的对象、弹窗要靠“改控件”积木开关，包一层以后都配不了。
/// 2. **P1 组件**六个（图标按钮、链接、网格、滚动区、步进器、表单项，见 comp_lib_builtin_p1.dart）——纯靠封装拼出来的，
///    组件盒里直接列着；第一次用到哪个，才把哪个定义装进文档（带着 `lib` 那一笔，所以只读；要改先“复制一份来改”）。
///
/// 不碰磁盘、不联网：整份库是代码里的常数。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_builtin_p1.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model.dart';

const String kBuiltinCompLibId = 'lopi/builtin';
const String kBuiltinCompLibName = '内置组件库';
const String kBuiltinCompLibVersion = '1.0.0';

/// 库里的一个组件给界面看的东西：在组件盒哪一类（`null`＝不进组件盒）、搜索用的别名、一句话说明、格子上画哪个图标。
class BuiltinComp {
  const BuiltinComp(this.id, this.note, {this.group, this.aliases = const [], this.icon = 'component'});
  final String id;
  final String note;

  /// `layout` / `basic` / `form`（palette_catalog.dart 里分类的名字）。
  final String? group;
  final List<String> aliases;

  /// 借哪种控件的图标（palette_widgets.dart 的 `lcIcon`）。
  final String icon;
}

const List<BuiltinComp> kBuiltinComps = [
  BuiltinComp('card', '白底圆角的一块，里面放什么都行。包的是现成的“卡片”。'),
  BuiltinComp('row', '里面的东西横着排。包的是现成的“行”。'),
  BuiltinComp('column', '里面的东西竖着排。包的是现成的“列”。'),
  BuiltinComp('spacer', '一段空白。包的是现成的“间隔”。'),
  BuiltinComp('divider', '一条横线。包的是现成的“分割线”。'),
  BuiltinComp('list', '几行文字的清单。包的是现成的“列表”。'),
  BuiltinComp('listItem', '一行：标题、副标题、右侧文字。包的是现成的“列表行”。'),
  BuiltinComp('appBar', '页面顶上的一条：标题。包的是现成的“顶部导航栏”。'),
  BuiltinComp('iconButton', '只有一个图标的圆按钮。图标是个插槽：点中它，往里放一个“图标”。点了往外发“点了”。', group: 'basic', aliases: ['图标按钮', 'iconbutton', 'tubiaoanniu'], icon: 'iconButton'),
  BuiltinComp('link', '带下划线的蓝字。点了往外发“点了”：在页面上给它接“去页面”或“打开网址”。', group: 'basic', aliases: ['超链接', '跳转', 'link', 'a', 'lianjie'], icon: 'link'),
  BuiltinComp('grid', '等宽几列的格子（2、3、4 列），放进去的东西自动一格一格排。', group: 'layout', aliases: ['宫格', '格子', '多列', 'grid', 'wangge'], icon: 'grid'),
  BuiltinComp('scroll', '固定高度的一块，里面的东西放多了能滚；也能改成横着滚。', group: 'layout', aliases: ['滚动', '滑动', 'scroll', 'gundong'], icon: 'scroll'),
  BuiltinComp('stepper', '减号、数字、加号。点加减往外发“改了”（带着新的数）：把“值”绑到一个数字状态，再给“改了”接“把一个状态设成事件带来的值”。', group: 'form', aliases: ['加减', '数量', '计数', 'stepper', 'bujinqi'], icon: 'stepper'),
  BuiltinComp('formItem', '标签、必填的星号、说明、错误提示，中间是个插槽，放输入框之类的控件。', group: 'form', aliases: ['表单行', '字段', '标签', 'formitem', 'field', 'biaodanxiang'], icon: 'formItem'),
];

Map<String, Object?> _wrap(String id, String name, String type, Map<String, Object?> props, {bool slot = false, List<Object?> defProps = const [], Map<String, Object?> more = const {}}) => {
  'id': id,
  'name': name,
  if (defProps.isNotEmpty) 'props': defProps,
  'root': {
    'id': 'box',
    'type': type,
    'props': props,
    ...more,
    if (slot)
      'children': [
        {'id': 'inside', 'type': 'slot'},
      ],
  },
};

Map<String, Object?> _text(String name, String value) => {'name': name, 'type': 'text', 'default': value};
Map<String, Object?> _from(String name) => {'from': 'var', 'name': name};

/// 八个“包一层”的定义。属性照那种控件放到画布上时的默认值写。
List<Map<String, Object?>> _wrapDefs() => [
  _wrap(
    'card',
    '卡片',
    'card',
    {...lcSpecs['card']!.defaults},
    slot: true,
    defProps: [
      {'name': 'bg', 'type': 'color', 'default': '#FFFFFF'},
    ],
    more: {
      'bind': {'bg': 'bg'},
    },
  ),
  _wrap('row', '行', 'row', {...lcSpecs['row']!.defaults}, slot: true),
  _wrap('column', '列', 'column', {...lcSpecs['column']!.defaults}, slot: true),
  _wrap('spacer', '间隔', 'spacer', {...lcSpecs['spacer']!.defaults}),
  _wrap('divider', '分割线', 'divider', const {}),
  _wrap('list', '列表', 'list', {...lcSpecs['list']!.defaults}),
  _wrap(
    'listItem',
    '列表行',
    'listItem',
    {...lcSpecs['listItem']!.defaults},
    defProps: [_text('title', '标题'), _text('subtitle', ''), _text('trailing', '')],
    more: {
      'data': {'title': _from('title'), 'subtitle': _from('subtitle'), 'trailing': _from('trailing')},
    },
  ),
  _wrap(
    'appBar',
    '顶部导航栏',
    'appBar',
    {...lcSpecs['appBar']!.defaults},
    defProps: [_text('title', '标题')],
    more: {
      'data': {'title': _from('title')},
    },
  ),
];

CompLib? _cached;

/// 整份内置组件库（只读；别改它交回来的东西）。
CompLib lcBuiltinCompLib() => _cached ??= CompLib(
  id: kBuiltinCompLibId,
  name: kBuiltinCompLibName,
  version: kBuiltinCompLibVersion,
  author: 'LopiCode',
  defs: [
    for (final json in [..._wrapDefs(), ...lcBuiltinP1Defs()]) ?LcComponentDef.tryParse((jsonDecode(jsonEncode(json)) as Map).cast<String, dynamic>()),
  ],
);

BuiltinComp? lcBuiltinComp(String id) {
  for (final c in kBuiltinComps) {
    if (c.id == id) return c;
  }
  return null;
}

/// 内置库里的组件装进文档以后的 id。
String lcBuiltinDefId(String id) => compLibDefId(kBuiltinCompLibId, id);

final String _prefix = lcBuiltinDefId('');

/// 这个 id 是不是“内置库里的某个组件装进文档以后的 id”；是就返回它在库里的 id。
String? lcBuiltinIdOf(String? docDefId) {
  if (docDefId == null || !docDefId.startsWith(_prefix)) return null;
  final id = docDefId.substring(_prefix.length);
  return lcBuiltinComp(id) == null ? null : id;
}

/// 这个定义是不是内置库装进来的（还带着来源那一笔）。
bool lcIsBuiltinDef(LcComponentDef def) => compLibOf(def)?.id == kBuiltinCompLibId;

/// 用到内置库的某个组件之前调一下：文档里还没有它的定义就装进去（只装这一个，带着来源那一笔）。
/// [docDefId] 不是内置库的 id、或者已经装了：什么都不做。返回这次装没装。
bool lcEnsureBuiltin(LcDocument doc, String? docDefId) {
  final id = lcBuiltinIdOf(docDefId);
  if (id == null || doc.component(docDefId!) != null) return false;
  LcComponentDef? src;
  for (final d in lcBuiltinCompLib().defs) {
    if (d.id == id) src = d;
  }
  if (src == null) return false;
  final json = (jsonDecode(jsonEncode(src.toJson())) as Map).cast<String, dynamic>();
  json['id'] = docDefId;
  json[kCompLibMark] = {'id': kBuiltinCompLibId, 'name': kBuiltinCompLibName, 'version': kBuiltinCompLibVersion, 'component': id};
  final copy = LcComponentDef.tryParse(json);
  if (copy == null) return false;
  doc.components.add(copy);
  return true;
}

/// “复制一份来改”：把内置库里的一个组件另存成项目自己的组件，返回新组件的 id。
/// 为了复制临时装进来的那份定义，没人用就再拿掉（不在“自定义组件”里多留一个只读的）。
String? lcForkBuiltin(LcDocument doc, String id) {
  final docId = lcBuiltinDefId(id);
  final added = lcEnsureBuiltin(doc, docId);
  final made = compLibFork(doc, docId);
  if (added) doc.components.removeWhere((c) => c.id == docId);
  return made;
}
