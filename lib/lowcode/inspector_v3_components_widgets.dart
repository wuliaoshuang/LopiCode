// 设计约束（低代码 · 合一面板“常用”页 · 11 个新组件各自的行 · 390×844）
// - 每个组件的行按“她最常改的在最上面”排：先内容（文字 / 标题 / 选项），再样子（两三档的选择），再开关，最后尺寸颜色。
// - 一行一项，样子和这一页别的行一样（名字在左、值在右）；改了就生效，没有主操作。
//   行名最多 4 个字（左边那一栏只有 72 宽，再长会被截掉）：说不清的靠值那边的提示字补。
// - 选项 / 页签 / 导航项是一整块（inspector_items_widgets.dart），排在最上面：这几个组件改得最多的就是它。
// - 都是“内容”：直接写进 props；和默认一样 / 清空＝把这个键去掉（文件里不留废话，导出不多一个字节）。
// - 带插槽的组件（列表行、顶部导航栏、标签页、弹窗）最后有一句灰字，说明还能往哪里拖东西——面板里不放“插槽”的编辑，
//   那是画布上拖的事。
// - 取用的 tokens：Space.x2、textFaint（那句灰字）。
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_items_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/inspector_top_shared_widgets.dart';
import 'package:lopicode/lowcode/inspector_v3_rows_widgets.dart';
import 'package:lopicode/lowcode/items_edit.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 各组件“样子”那一行的名字（键的顺序同 [lcVariants]）。
const Map<String, Map<String, String>> kLcVariantLabels = {
  'radio': {'dot': '圆点', 'button': '按钮式'},
  'listItem': {'one': '单行', 'two': '两行'},
  'appBar': {'left': '居左', 'center': '居中'},
  'bottomNav': {'labeled': '有字', 'iconOnly': '只有图标'},
  'tabs': {'underline': '下划线', 'pill': '胶囊'},
  'dialog': {'alert': '一个按钮', 'confirm': '两个按钮'},
};

/// 带插槽的组件：那句“还能往里拖什么”。
const Map<String, String> kLcSlotTips = {
  'listItem': '还可以往这一行的左边、右边拖组件（比如左边放图标、右边放开关）。',
  'appBar': '还可以往导航栏的左边、右边拖组件（比如右边放一个按钮）。',
  'tabs': '每个页签里放什么：在画布上点页签切过去，再往里拖组件。',
  'dialog': '弹窗里还可以拖组件：放在文字下面（内容区），或者按钮那一排（底部）。',
};

Widget _variant(InspectorEdit ed) => InspectorChoiceRow(
  id: 'variant',
  label: '样子',
  options: kLcVariantLabels[ed.node.type]!,
  selected: lcVariantOf(ed.node),
  onChanged: (v) => ed.apply((n, _) => lcSetOrDrop(n, 'variant', v == lcVariants[n.type]!.first ? null : v)),
);

Widget _text(InspectorEdit ed, String prop, String label, {String? hint, int maxLines = 1}) =>
    LcPropTextRow(key: ValueKey('${ed.node.id}-$prop'), ed: ed, prop: prop, label: label, hint: hint, maxLines: maxLines);

/// 新组件在“常用”页的行，和“这些简写属性已经单列了”。不是新组件返回 null。
/// [color]、[more] 是那一页自己的行（颜色、宽度 / 圆角 / 字号…），传进来复用。
(List<Widget>, Set<String>)? lcV3ComponentRows(
  BuildContext context,
  InspectorEdit ed, {
  required Widget Function(String prop, String label, String cssName) color,
  required Widget? Function(String prop) more,
}) {
  final n = ed.node;
  final tip = kLcSlotTips[n.type];
  final tail = [
    if (tip != null)
      Padding(
        padding: const EdgeInsets.only(top: Space.x2),
        child: Text(
          tip,
          key: const Key('lc-common-slot-tip'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textFaint),
        ),
      ),
  ];
  final kind = lcItemsKindOf(n);
  final items = [if (kind != null) LcItemsEditor(key: ValueKey('items-${n.id}'), ed: ed, kind: kind)];
  switch (n.type) {
    case 'icon':
      return (
        [
          lcIconRow(context, ed, required: true),
          PresetRow(
            key: const Key('lc-common-size'),
            id: 'size',
            label: '大小',
            value: n.numProp('size') ?? 24,
            quick: const [16, 24, 32, 48],
            scale: const [12, 16, 20, 24, 32, 40, 48, 64, 96],
            clearable: false,
            onChanged: (v, {typing = false}) => ed.apply((n, _) => n.props['size'] = v ?? 24, merge: typing),
          ),
          color('color', '颜色', 'color'),
        ],
        {'color'},
      );
    case 'textarea':
      return (
        [
          _text(ed, 'placeholder', '提示文字'),
          _text(ed, 'value', '默认值', hint: '一打开就填着的字', maxLines: 3),
          _text(ed, 'label', '标签', hint: '输入框上面的那行字'),
          InspectorChoiceRow(
            id: 'rows',
            label: '几行高',
            options: const {'2': '2', '3': '3', '4': '4', '6': '6', '8': '8'},
            selected: '${(n.numProp('rows') ?? 3).round()}',
            onChanged: (v) => ed.apply((n, _) => n.props['rows'] = int.parse(v)),
          ),
          lcSwitchRow(ed, 'autoGrow', '自动变高'),
          LcPropTextRow(key: ValueKey('${n.id}-maxLength'), ed: ed, prop: 'maxLength', label: '字数上限', hint: '不填＝不限', number: true),
          lcSwitchRow(ed, 'required', '必填'),
          lcSwitchRow(ed, 'disabled', '禁用'),
          ?more('width'),
          ?more('radius'),
        ],
        {'width', 'radius'},
      );
    case 'switch':
      return ([lcSwitchRow(ed, 'checked', '默认打开'), lcSwitchRow(ed, 'disabled', '禁用')], const {});
    case 'slider':
      return (
        [
          LcPropTextRow(key: ValueKey('${n.id}-value'), ed: ed, prop: 'value', label: '现在的值', hint: '不填＝最小值', number: true, lowest: -100000),
          LcPropTextRow(key: ValueKey('${n.id}-min'), ed: ed, prop: 'min', label: '最小', hint: '不填＝0', number: true, lowest: -100000),
          LcPropTextRow(key: ValueKey('${n.id}-max'), ed: ed, prop: 'max', label: '最大', hint: '不填＝100', number: true, lowest: -100000),
          LcPropTextRow(key: ValueKey('${n.id}-step'), ed: ed, prop: 'step', label: '一步走多少', hint: '不填＝1', number: true),
          lcSwitchRow(ed, 'disabled', '禁用'),
          ?more('width'),
        ],
        {'width'},
      );
    case 'checkbox':
      return ([_text(ed, 'text', '文字'), lcSwitchRow(ed, 'checked', '默认勾上'), lcSwitchRow(ed, 'disabled', '禁用'), ?more('fontSize'), color('color', '文字颜色', 'color')], {'fontSize', 'color'});
    case 'radio':
      return (
        [
          ...items,
          _variant(ed),
          InspectorChoiceRow(
            id: 'direction',
            label: '排法',
            options: const {'column': '竖着排', 'row': '横着排'},
            selected: n.props['direction'] == 'row' ? 'row' : 'column',
            onChanged: (v) => ed.apply((n, _) => lcSetOrDrop(n, 'direction', v == 'column' ? null : v)),
          ),
          lcSwitchRow(ed, 'disabled', '禁用'),
        ],
        const {},
      );
    case 'select':
      return ([...items, _text(ed, 'placeholder', '提示文字', hint: '没选的时候显示的字'), lcSwitchRow(ed, 'disabled', '禁用'), ?more('width'), ?more('radius')], {'width', 'radius'});
    case 'listItem':
      return (
        [
          _text(ed, 'title', '标题'),
          _variant(ed),
          if (lcVariantOf(n) == 'two') _text(ed, 'subtitle', '副标题', hint: '标题下面的小字'),
          _text(ed, 'trailing', '右侧文字', hint: '比如“未设置”'),
          lcSwitchRow(ed, 'chevron', '右箭头'),
          color('bg', '背景', 'background-color'),
          ...tail,
        ],
        {'bg'},
      );
    case 'appBar':
      return (
        [
          _text(ed, 'title', '标题'),
          _variant(ed),
          lcSwitchRow(ed, 'back', '返回箭头'),
          lcSwitchRow(ed, 'sticky', '固定顶部'),
          color('bg', '背景', 'background-color'),
          color('color', '文字颜色', 'color'),
          ...tail,
          LcTopShareBlock(ed: ed),
        ],
        {'bg', 'color'},
      );
    case 'bottomNav':
      return ([...items, _variant(ed), color('bg', '背景', 'background-color'), color('color', '选中颜色', 'color')], {'bg', 'color'});
    case 'tabs':
      return ([...items, _variant(ed), color('color', '选中颜色', 'color'), ...tail], {'color'});
    case 'dialog':
      final confirm = lcVariantOf(n) == 'confirm';
      return (
        [
          _text(ed, 'title', '标题'),
          _text(ed, 'text', '内容', maxLines: 4),
          _variant(ed),
          _text(ed, 'okText', '确定按钮', hint: '确定'),
          if (confirm) _text(ed, 'cancelText', '取消按钮', hint: '取消'),
          lcSwitchRow(ed, 'dismissible', '点外关闭', whenUnset: true),
          lcSwitchRow(ed, 'open', '默认弹出'),
          ...tail,
        ],
        const {},
      );
  }
  return null;
}
