// 设计约束（低代码 · 合一面板“常用”页里第 3 版加的那几行 · 390×844）
// - 按钮多两行：图标（点开一张选图标的面板）、禁用。图片多一行：说明文字。
//   输入框多五行：类型、默认值、标签、必填、禁用。都排在各自原有几行的后面——原来最常改的还在最上面。
// - 一行一项，样子和这一页别的行一样（名字在左、值在右）。没有主操作：改了就生效。
// - 这些都是“内容”不是样式：直接写进 props；关掉 / 清空＝把这个键去掉（没用到的页面导出一个字节都不多）。
// - 选图标的面板：一格一个图标（56 见方，图标在上、中文名在下），第一格是“不要图标”；点一下就选中并关掉。
// - 取用的 tokens：Space.x1/x2/x3/x4、Radii.sm、accent / accentSoft（选中的那格）、textMuted、border。
import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/icon_set_widgets.dart';
import 'package:lopicode/lowcode/inspector_bind_widgets.dart';
import 'package:lopicode/lowcode/inspector_common_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 输入框类型给人看的名字（顺序就是那一行里从左到右的顺序）。
const Map<String, String> kLcInputTypeLabels = {'text': '文字', 'password': '密码', 'number': '数字', 'email': '邮箱', 'tel': '电话'};

/// 写一个内容属性；空的 / 关掉＝把这个键去掉。
void lcSetOrDrop(LcNode n, String prop, Object? value) {
  if (value == null || value == false || value == '') {
    n.props.remove(prop);
  } else {
    n.props[prop] = value;
  }
}

/// 一行开关。[whenUnset]＝这个键没写时算开还是关（默认关）；拨到和它一样就把键去掉。
Widget lcSwitchRow(InspectorEdit ed, String prop, String label, {bool whenUnset = false}) => LcBindableRow(
  ed: ed,
  prop: prop,
  label: label,
  child: InspectorRow(
    label: label,
    scroll: false,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Switch(
        key: Key('lc-common-$prop'),
        value: ed.node.props[prop] is bool ? ed.node.props[prop] as bool : whenUnset,
        onChanged: (v) => ed.apply((n, _) {
          if (v == whenUnset) {
            n.props.remove(prop);
          } else {
            n.props[prop] = v;
          }
        }),
      ),
    ),
  ),
);

/// 一行“图标”：点开选图标的面板。[required]＝必须有一个（图标组件）：选“不要图标”不改。
Widget lcIconRow(BuildContext context, InspectorEdit ed, {bool required = false}) {
  final icon = lcIconByName(ed.node.strProp('icon'));
  return InspectorRow(
    label: '图标',
    scroll: false,
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('lc-common-icon'),
        onPressed: () async {
          final picked = await showLcIconPicker(context, selected: icon?.name);
          if (picked == null || (required && picked.isEmpty)) return;
          ed.apply((n, _) => lcSetOrDrop(n, 'icon', picked.isEmpty ? null : picked));
        },
        icon: Icon(icon == null ? Icons.add : lcIconData[icon.name], size: 18),
        label: Text(icon == null ? '选一个' : icon.label),
      ),
    ),
  );
}

/// 按钮：图标、禁用。
List<Widget> lcButtonV3Rows(BuildContext context, InspectorEdit ed) {
  return [lcIconRow(context, ed), lcSwitchRow(ed, 'disabled', '禁用')];
}

/// 图片：说明文字（看不见图的人、图没加载出来时读到的那句话）。
List<Widget> lcImageV3Rows(InspectorEdit ed) => [LcPropTextRow(ed: ed, prop: 'alt', label: '说明文字', hint: '图上是什么（给读屏和加载失败时用）')];

/// 输入框：类型、默认值、标签、必填、禁用。
List<Widget> lcInputV3Rows(InspectorEdit ed) => [
  InspectorChoiceRow(
    id: 'inputType',
    label: '类型',
    options: kLcInputTypeLabels,
    selected: ed.node.strProp('inputType') ?? 'text',
    onChanged: (v) => ed.apply((n, _) => lcSetOrDrop(n, 'inputType', v == 'text' ? null : v)),
  ),
  LcPropTextRow(ed: ed, prop: 'value', label: '默认值', hint: '一打开就填着的字'),
  LcPropTextRow(ed: ed, prop: 'label', label: '标签', hint: '输入框上面的那行字'),
  lcSwitchRow(ed, 'required', '必填'),
  lcSwitchRow(ed, 'disabled', '禁用'),
];

/// 一行文字属性：打字就生效（连着打算一条撤销），清空＝把这个属性去掉。
class LcPropTextRow extends StatefulWidget {
  const LcPropTextRow({super.key, required this.ed, required this.prop, required this.label, this.hint, this.maxLines = 1, this.number = false});
  final InspectorEdit ed;
  final String prop;
  final String label;
  final String? hint;
  final int maxLines;

  /// 这一项是个正整数（最多几个字）：只收数字，写成数；空的、0＝把这个属性去掉。
  final bool number;

  @override
  State<LcPropTextRow> createState() => _LcPropTextRowState();
}

class _LcPropTextRowState extends State<LcPropTextRow> {
  late final TextEditingController _text = TextEditingController(text: widget.number ? '${widget.ed.node.numProp(widget.prop)?.round() ?? ''}' : widget.ed.node.strProp(widget.prop) ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LcBindableRow(
    ed: widget.ed,
    prop: widget.prop,
    label: widget.label,
    child: InspectorRow(
      label: widget.label,
      scroll: false,
      child: TextField(
        key: Key('lc-common-${widget.prop}'),
        controller: _text,
        minLines: 1,
        maxLines: widget.maxLines,
        keyboardType: widget.number ? TextInputType.number : null,
        decoration: InputDecoration(isDense: true, hintText: widget.hint),
        onChanged: (v) => widget.ed.apply((n, _) {
          final count = int.tryParse(v.trim());
          lcSetOrDrop(n, widget.prop, widget.number ? (count != null && count >= 1 && count <= 100000 ? count : null) : v);
        }, merge: true),
      ),
    ),
  );
}

/// 选图标。返回选中的名字；选“不要图标”返回空串；没选就关了返回 null。
Future<String?> showLcIconPicker(BuildContext context, {String? selected}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _IconPicker(selected: selected),
);

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected});
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget cell(String name, String label, IconData? data) {
      final on = (selected ?? '') == name;
      return InkWell(
        key: Key('lc-icon-pick-${name.isEmpty ? 'none' : name}'),
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => Navigator.pop(context, name),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: on ? c.accentSoft : null,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: on ? c.accent : c.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data ?? Icons.block, size: 22, color: on ? c.accent : c.text),
              const SizedBox(height: Space.x1),
              Text(
                label,
                style: t.labelSmall?.copyWith(color: on ? c.accent : c.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选图标', style: t.titleLarge),
            const SizedBox(height: Space.x3),
            Wrap(spacing: Space.x2, runSpacing: Space.x2, children: [cell('', '不要', null), for (final i in lcIcons) cell(i.name, i.label, lcIconData[i.name])]),
          ],
        ),
      ),
    );
  }
}
