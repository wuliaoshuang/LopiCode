/// 每种组件的登记表：叫什么、能不能放子组件、默认属性、面板里显示哪些字段。
/// （从 model.dart 里挪出来的，model.dart 原样 export 它；内容一个字没改。）
library;

import 'package:lopicode/lowcode/model_v3_components.dart';

class LcSpec {
  const LcSpec(this.type, this.label, {this.isContainer = false, this.defaults = const {}, this.fields = const [], this.slots});
  final String type;
  final String label;
  final bool isContainer;
  final Map<String, dynamic> defaults;

  /// 带插槽的组件：固定的插槽名（标签页的插槽跟着页签走，这里是空表）。null＝没有插槽。读法见 slots.dart。
  final List<String>? slots;

  /// 属性面板里显示哪些字段、按什么顺序。
  final List<String> fields;
}

const _boxFields = ['width', 'height', 'padding', 'margin', 'bg', 'radius'];
const _layoutFields = ['gap', 'align', 'justify'];

/// 这一版不认识的组件类型用的说明（不在 [lcSpecs] 里：组件盒、各处“每种组件”的清单都不该有它）。
const LcSpec lcUnknownSpec = LcSpec('unknown', '新版组件', defaults: {}, fields: []);

const Map<String, LcSpec> lcSpecs = {
  'page': LcSpec('page', '页面', isContainer: true, defaults: {'padding': 16, 'gap': 12, 'bg': '#F6FBFD'}, fields: ['padding', 'bg', ..._layoutFields]),
  'container': LcSpec('container', '容器', isContainer: true, defaults: {'padding': 12, 'gap': 8, 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'row': LcSpec('row', '行', isContainer: true, defaults: {'gap': 8, 'align': 'center', 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'column': LcSpec('column', '列', isContainer: true, defaults: {'gap': 8}, fields: [..._boxFields, ..._layoutFields]),
  'card': LcSpec('card', '卡片', isContainer: true, defaults: {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'text': LcSpec(
    'text',
    '文本',
    defaults: {'text': '一段文本', 'fontSize': 16, 'color': '#222435'},
    fields: ['text', 'fontSize', 'bold', 'color', 'textAlign', 'width', 'padding', 'margin', 'bg', 'radius'],
  ),
  'button': LcSpec(
    'button',
    '按钮',
    defaults: {'text': '按钮', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'fontSize': 16},
    fields: ['text', 'fontSize', 'bg', 'color', 'radius', 'padding', 'width', 'margin'],
  ),
  'image': LcSpec('image', '图片', defaults: {'src': '', 'height': 160, 'radius': 8, 'width': 'fill'}, fields: ['src', 'width', 'height', 'radius', 'margin']),
  'input': LcSpec('input', '输入框', defaults: {'placeholder': '请输入', 'radius': 8, 'width': 'fill'}, fields: ['placeholder', 'width', 'radius', 'margin']),
  'list': LcSpec(
    'list',
    '列表',
    defaults: {
      'items': ['第一项', '第二项', '第三项'],
      'fontSize': 16,
      'color': '#222435',
    },
    fields: ['items', 'fontSize', 'color', 'width', 'padding', 'margin', 'bg', 'radius'],
  ),
  'divider': LcSpec('divider', '分割线', defaults: {}, fields: ['margin']),
  'spacer': LcSpec('spacer', '间隔', defaults: {'size': 16}, fields: ['size']),
  // 这一版不认识的类型（LcNode.raw）：不能放子组件、不在组件盒里、没有可改的属性。
  // 自定义组件的实例：props.ref 指向 LcDocument.components 里的定义。不在组件栏的固定清单里。
  'component': LcSpec('component', '组件', defaults: {}, fields: ['width', 'margin']),
  // 插槽占位：只在自定义组件的定义里用（props.name 是插槽名，子节点是没填时显示的默认内容）。不在组件盒里。
  'slot': LcSpec('slot', '插槽', isContainer: true, defaults: {}, fields: []),
  // 第 3 版的 11 个新组件（model_v3_components.dart）。
  ...lcV3Specs,
};

/// 组件面板里可拖出来的类型（page 只能是根）。
const List<String> lcPaletteTypes = ['container', 'row', 'column', 'card', 'text', 'button', 'image', 'input', 'list', 'divider', 'spacer', ...lcV3PaletteTypes];
