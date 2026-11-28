/// 格式第 3 版的 11 个新组件：登记表（类型、默认值、面板里的字段、插槽）和它们各自属性的规矩。
/// 类型名、属性名、插槽名都是 docs/lowcode-page-format-v3.md 里定死的，这里只是照着登记。
///
/// 对象数组（选项、页签、导航项）的规矩——**整串都合规矩才算数**，有一项不对整个键就不生效、原样留着：
/// - `options`（单选组、下拉选择）：1–50 项；每项是对象，`value` 是不空的字符串（最长 80）且互不重复；`label` 没有或是字符串。
/// - `tabs`（标签页）：1–8 项；每项 `id` 合 [lcSlotName] 的写法且互不重复；`label` 没有或是字符串。
/// - `items`（底部导航栏）：1–5 项；每项 `icon` 合图标名的写法、`label` 没有或是字符串、`page` 没有或是字符串。
/// 对象里别的键不解释、原样留着。
library;

import 'package:lopicode/lowcode/model.dart';

/// 插槽名（也是页签 id）的写法。
final RegExp lcSlotName = RegExp(r'^[A-Za-z0-9_]{1,24}$');
final RegExp _iconName = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

const int kLcMaxOptions = 50;
const int kLcMaxTabs = 8;
const int kLcMaxNavItems = 5;

const List<Map<String, String>> _twoOptions = [
  {'value': 'a', 'label': '选项一'},
  {'value': 'b', 'label': '选项二'},
];

const Map<String, LcSpec> lcV3Specs = {
  'icon': LcSpec('icon', '图标', defaults: {'icon': 'star', 'size': 24, 'color': '#222435'}, fields: ['margin']),
  'textarea': LcSpec('textarea', '多行输入', defaults: {'placeholder': '请输入', 'rows': 3, 'radius': 8, 'width': 'fill'}, fields: ['width', 'radius', 'margin']),
  'switch': LcSpec('switch', '开关', defaults: {'checked': true}, fields: ['margin']),
  // 滑块（第四轮 B5）：值、最小、最大、一步走多少都是数；网页是 <input type="range">，Flutter 是 Slider。
  'slider': LcSpec('slider', '滑块', defaults: {'value': 50, 'min': 0, 'max': 100, 'step': 1, 'width': 'fill'}, fields: ['width', 'margin']),
  'checkbox': LcSpec('checkbox', '勾选框', defaults: {'text': '选项'}, fields: ['fontSize', 'color', 'margin']),
  'radio': LcSpec('radio', '单选组', defaults: {'options': _twoOptions, 'value': 'a'}, fields: ['fontSize', 'color', 'margin']),
  'select': LcSpec('select', '下拉选择', defaults: {'options': _twoOptions, 'placeholder': '请选择', 'radius': 8, 'width': 'fill'}, fields: ['width', 'radius', 'margin']),
  'listItem': LcSpec('listItem', '列表行', isContainer: true, slots: ['left', 'right'], defaults: {'title': '标题', 'chevron': true, 'width': 'fill'}, fields: ['bg', 'width', 'margin']),
  'appBar': LcSpec('appBar', '顶部导航栏', isContainer: true, slots: ['left', 'right'], defaults: {'title': '标题', 'bg': '#FFFFFF', 'color': '#222435', 'width': 'fill'}, fields: ['bg', 'color']),
  'bottomNav': LcSpec(
    'bottomNav',
    '底部导航栏',
    defaults: {
      'items': [
        {'icon': 'home', 'label': '首页'},
        {'icon': 'search', 'label': '发现'},
        {'icon': 'person', 'label': '我的'},
      ],
      'current': 0,
      'bg': '#FFFFFF',
      'color': '#058654',
      'width': 'fill',
    },
    fields: ['bg', 'color'],
  ),
  'tabs': LcSpec(
    'tabs',
    '标签页',
    isContainer: true,
    slots: [],
    defaults: {
      'tabs': [
        {'id': 't1', 'label': '页签一'},
        {'id': 't2', 'label': '页签二'},
      ],
      'current': 't1',
      'color': '#058654',
      'width': 'fill',
    },
    fields: ['color', 'width', 'margin'],
  ),
  'dialog': LcSpec('dialog', '弹窗', isContainer: true, slots: ['content', 'footer'], defaults: {'title': '提示', 'text': '这里写内容', 'okText': '确定', 'dismissible': true}, fields: []),
};

/// 组件盒里的顺序。
const List<String> lcV3PaletteTypes = ['icon', 'textarea', 'switch', 'slider', 'checkbox', 'radio', 'select', 'listItem', 'appBar', 'bottomNav', 'tabs', 'dialog'];

/// 各组件 `props.variant` 能取的值（第一个是不写时的默认）。
const Map<String, List<String>> lcVariants = {
  'radio': ['dot', 'button'],
  'listItem': ['one', 'two'],
  'appBar': ['left', 'center'],
  'bottomNav': ['labeled', 'iconOnly'],
  'tabs': ['underline', 'pill'],
  'dialog': ['alert', 'confirm', 'toast'],
};

/// 轻提示：弹窗的第三种样子——屏幕下方一句话，过几秒自己消失；没有遮罩、标题、按钮，里面也不放组件。
bool lcIsToast(LcNode n) => n.type == 'dialog' && lcVariantOf(n) == 'toast';

/// 组件盒里“轻提示”那一格的名字（不是一种新组件：放出来的是样子为“轻提示”的弹窗）。
const String kLcToastPaletteType = 'toast';

/// 新放出来的轻提示带的属性。
const Map<String, dynamic> kLcToastDefaults = {'variant': 'toast', 'text': '已保存'};

/// 轻提示几秒后消失（1–5，不写是 2）。
int lcToastSeconds(LcNode n) {
  final v = n.props['seconds'];
  return v is num ? v.round().clamp(1, 5) : 2;
}

/// 这个组件现在是哪种样子。
String lcVariantOf(LcNode n) {
  final all = lcVariants[n.type];
  if (all == null) return '';
  final v = n.props['variant'];
  return all.contains(v) ? v as String : all.first;
}

/// 哪个键只有哪些类型能用（不在表里的类型上，这个键不认识＝原样留着）。
const Map<String, List<String>> _keyTypes = {
  'rows': ['textarea'],
  'maxLength': ['textarea'],
  'autoGrow': ['textarea'],
  'checked': ['switch', 'checkbox'],
  'options': ['radio', 'select'],
  'direction': ['radio'],
  'variant': ['radio', 'listItem', 'appBar', 'bottomNav', 'tabs', 'dialog'],
  'title': ['listItem', 'appBar', 'dialog'],
  'subtitle': ['listItem'],
  'trailing': ['listItem'],
  'chevron': ['listItem'],
  'back': ['appBar'],
  'sticky': ['appBar'],
  'current': ['bottomNav', 'tabs'],
  'tabs': ['tabs'],
  'open': ['dialog'],
  'dismissible': ['dialog'],
  'okText': ['dialog'],
  'cancelText': ['dialog'],
  'seconds': ['dialog'],
};

/// 新组件带来的键（都只在第 3 版的文件里算数）。
const Set<String> lcV3ComponentKeys = {
  'rows',
  'maxLength',
  'autoGrow',
  'checked',
  'options',
  'direction',
  'variant',
  'title',
  'subtitle',
  'trailing',
  'chevron',
  'back',
  'sticky',
  'current',
  'tabs',
  'open',
  'dismissible',
  'okText',
  'cancelText',
  'seconds',
};

/// 这个键归不归这里管（[lcCleanV3] 说了算，model_props.dart 不再往下看）。
bool lcIsV3ComponentKey(String type, String key) => lcV3ComponentKeys.contains(key) || (key == 'items' && type == 'bottomNav') || (type == 'slider' && kLcSliderKeys.contains(key));

/// 滑块的四个数。只在滑块上归这里管：`value` 在别的控件上是一段文字（model_props.dart），`min` / `max` / `step` 别的控件不认识。
const Set<String> kLcSliderKeys = {'value', 'min', 'max', 'step'};

/// 滑块现在的四个数（没写、写得不对的用默认；最大不比最小大时当成最小 + 1；值夹在最小和最大之间）。
({num value, num min, num max, num step}) lcSliderOf(LcNode n) {
  final min = n.numProp('min') ?? 0;
  final rawMax = n.numProp('max') ?? 100;
  final max = rawMax > min ? rawMax : min + 1;
  final step = n.numProp('step') ?? 1;
  final value = (n.numProp('value') ?? min).clamp(min, max);
  return (value: value, min: min, max: max, step: step > 0 ? step : 1);
}

Map<String, dynamic>? _obj(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': e.value} : null;

List<Map<String, dynamic>>? _objects(Object? value, int max, bool Function(Map<String, dynamic> m) ok) {
  if (value is! List || value.isEmpty || value.length > max) return null;
  final out = <Map<String, dynamic>>[];
  for (final v in value) {
    final m = _obj(v);
    if (m == null || !ok(m)) return null;
    out.add(m);
  }
  return out;
}

bool _optLabel(Map<String, dynamic> m) => m['label'] == null || m['label'] is String;

/// 新组件那批键的规矩：合就返回整理好的值；不合、或者这种组件没有这个键，返回 null。
Object? lcCleanV3(String type, String key, Object? value) {
  if (key == 'items') {
    return _objects(value, kLcMaxNavItems, (m) => m['icon'] is String && _iconName.hasMatch(m['icon'] as String) && _optLabel(m) && (m['page'] == null || m['page'] is String));
  }
  if (type == 'slider' && kLcSliderKeys.contains(key)) {
    if (value is! num || !value.isFinite || value.abs() > 1e9) return null;
    return key == 'step' && value <= 0 ? null : value;
  }
  if (!(_keyTypes[key]?.contains(type) ?? false)) return null;
  switch (key) {
    case 'rows' || 'maxLength':
      return value is num && value >= 1 && value <= 100000 ? value.round() : null;
    case 'autoGrow' || 'checked' || 'chevron' || 'back' || 'sticky' || 'open' || 'dismissible':
      return value is bool ? value : null;
    case 'title' || 'subtitle' || 'trailing' || 'okText' || 'cancelText':
      return value is String ? value : null;
    case 'seconds':
      return value is num && value >= 1 && value <= 5 ? value.round() : null;
    case 'direction':
      return value == 'row' || value == 'column' ? value : null;
    case 'variant':
      return lcVariants[type]!.contains(value) ? value : null;
    case 'current':
      if (type == 'bottomNav') return value is int && value >= 0 ? value : null;
      return value is String && lcSlotName.hasMatch(value) ? value : null;
    case 'options':
      final seen = <String>{};
      return _objects(value, kLcMaxOptions, (m) {
        final v = m['value'];
        return v is String && v.isNotEmpty && v.length <= 80 && seen.add(v) && _optLabel(m);
      });
    case 'tabs':
      final seen = <String>{};
      return _objects(value, kLcMaxTabs, (m) {
        final id = m['id'];
        return id is String && lcSlotName.hasMatch(id) && seen.add(id) && _optLabel(m);
      });
  }
  return null;
}

/// 读出来的对象数组（选项、页签、导航项）；没有、不合规矩都是空的。
List<Map<String, dynamic>> lcObjects(LcNode n, String key) {
  final v = n.props[key];
  return v is List ? [for (final m in v) ?_obj(m)] : const [];
}

/// 一项给人看的字：`label` 没写就用 [fallbackKey] 那个键的值。
String lcItemLabel(Map<String, dynamic> m, String fallbackKey) {
  final l = m['label'];
  if (l is String && l.isNotEmpty) return l;
  final f = m[fallbackKey];
  return f is String ? f : '';
}
