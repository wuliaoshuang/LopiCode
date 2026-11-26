// 设计约束（样式面板各分组的内容；390×844）
// - 面板一次只显示一个分组；每个分组从上到下是若干“一行一个属性”，常用的在前，不常用的收进“更多”。
// - 这个文件放：尺寸、间距、边框、圆角、背景（含不透明度）、文字。阴影、布局、定位在 style_layout_widgets.dart。
// - 主次：每组第一、二行是最常改的（宽高、背景色、文字颜色和字号）；说明性的话一律弱化色小字。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_box_widgets.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_layout_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 面板上的分组标签。比 [LcStyleGroup] 少：外边距和内边距并成“间距”（一张盒模型图），不透明度并进“背景”，溢出并进“定位”。
enum StyleTab {
  size('尺寸', [LcStyleGroup.size]),
  spacing('间距', [LcStyleGroup.margin, LcStyleGroup.padding]),
  border('边框', [LcStyleGroup.border]),
  radius('圆角', [LcStyleGroup.radius]),
  background('背景', [LcStyleGroup.background, LcStyleGroup.opacity]),
  text('文字', [LcStyleGroup.text]),
  shadow('阴影', [LcStyleGroup.shadow]),
  layout('布局', [LcStyleGroup.layout]),
  position('定位', [LcStyleGroup.position, LcStyleGroup.overflow]);

  const StyleTab(this.label, this.groups);
  final String label;
  final List<LcStyleGroup> groups;

  /// 这个分组里有没有自己设过的东西（标签上打点用）。
  bool touched(Map<String, String> own) => groups.any(LcStyle(own).hasAny);
}

/// 某个分组的内容。
Widget styleTabBody(StyleTab tab, StyleEdit ed) => switch (tab) {
  StyleTab.size => _SizeGroup(ed),
  StyleTab.spacing => BoxModelEditor(ed: ed),
  StyleTab.border => _BorderGroup(ed),
  StyleTab.radius => StyleSidesRows(ed, 'border-radius', label: '圆角', sideLabels: const ['左上角', '右上角', '右下角', '左下角']),
  StyleTab.background => _BackgroundGroup(ed),
  StyleTab.text => _TextGroup(ed),
  StyleTab.shadow => ShadowGroup(ed),
  StyleTab.layout => LayoutGroup(ed),
  StyleTab.position => PositionGroup(ed),
};

Widget _column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

class _SizeGroup extends StatelessWidget {
  const _SizeGroup(this.ed);
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final LcNode n = ed.node;
    // “撑满”在简写属性里不是一个宽度值（是 flex / align-self），宽度这一行会是空的；说一声，免得用户以为没设。
    final fills = !ed.isOwn('width') && ed.resolved['width'] == null && (ed.resolved['flex-grow'] == '1' || ed.resolved['align-self'] == 'stretch');
    const more = ['min-width', 'max-width', 'min-height', 'max-height'];
    return _column([
      StyleLengthRow(ed, 'width', '宽度', allowAuto: true),
      if (fills) Text('现在是“撑满”（在属性里设的）。在这里填了宽度就按填的来。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint)),
      StyleLengthRow(ed, 'height', '高度', allowAuto: true),
      MoreSection(
        id: 'size',
        initiallyOpen: more.any(ed.isOwn),
        children: [StyleLengthRow(ed, 'min-width', '最小宽度'), StyleLengthRow(ed, 'max-width', '最大宽度'), StyleLengthRow(ed, 'min-height', '最小高度'), StyleLengthRow(ed, 'max-height', '最大高度')],
      ),
      if (n.type == 'spacer') Text('间隔的大小在“常用”页里改更方便。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint)),
    ]);
  }
}

class _BorderGroup extends StatelessWidget {
  const _BorderGroup(this.ed);
  final StyleEdit ed;

  /// 四边一样就返回那个值，不一样 / 都没设返回 null。
  String? _uniform(String group) {
    final s = ed.shown.sides(group);
    return s.isUniform ? s.top : null;
  }

  @override
  Widget build(BuildContext context) {
    final style = _uniform('border-style')?.toLowerCase();
    final styles = ed.shown.sides('border-style');
    final colors = ed.shown.sides('border-color');
    final ownStyle = LcStyle.sideNames('border-style').any(ed.isOwn);
    final ownColor = LcStyle.sideNames('border-color').any(ed.isOwn);
    return _column([
      StyleSidesRows(
        ed,
        'border-width',
        label: '宽度',
        sideLabels: const ['上边框', '右边框', '下边框', '左边框'],
        // 只有宽度没有样式的边框浏览器不画。用户设了宽度多半是想看到边框，所以顺手补上实线（已经选过样式的不动）。
        onSet: (s, names, v) {
          if (v == null || !v.isNumeric || v.value! <= 0) return;
          for (final n in names) {
            final styleName = n.replaceFirst('-width', '-style');
            if (s.get(styleName) == null) s.set(styleName, 'solid');
          }
        },
      ),
      StyleRow(
        label: '样式',
        hint: !styles.isEmpty && !styles.isUniform ? '四边不一样，选了会一起变' : null,
        child: ChoiceButtons(
          id: 'border-style',
          options: const [ChoiceOption('none', '无'), ChoiceOption('solid', '实线'), ChoiceOption('dashed', '虚线'), ChoiceOption('dotted', '点线')],
          selected: style,
          inherited: !ownStyle,
          onChanged: (v) => ed.apply((s) => s.setSides('border-style', LcSides.all(v))),
        ),
      ),
      StyleRow(
        label: '颜色',
        hint: !colors.isEmpty && !colors.isUniform ? '四边不一样，选了会一起变' : null,
        child: ColorButton(id: 'border-color', value: _uniform('border-color'), faint: !ownColor, title: '边框颜色', onChanged: (v) => ed.apply((s) => s.setSides('border-color', LcSides.all(v)))),
      ),
    ]);
  }
}

class _BackgroundGroup extends StatelessWidget {
  const _BackgroundGroup(this.ed);
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final raw = ed.resolved['opacity'];
    final value = ed.shown.number('opacity');
    if (raw != null && value == null) return _column([StyleColorRow(ed, 'background-color', '背景色'), StyleRawRow(ed, 'opacity', '不透明度')]);
    final shown = (value ?? 1).clamp(0.0, 1.0);
    return _column([
      StyleColorRow(ed, 'background-color', '背景色'),
      StyleRow(
        label: '不透明度',
        hint: '整个组件一起变透明',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              child: Slider(
                key: const Key('lc-opacity'),
                value: shown * 100,
                max: 100,
                divisions: 100,
                // 拖的过程只是预览；松手才提交，一次拖动只算一条撤销记录。
                onChanged: (v) => ed.apply((s) => s.setNumber('opacity', v.round() / 100), merge: true),
                onChangeEnd: (_) => ed.apply((_) {}),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${(shown * 100).round()}%', key: const Key('lc-opacity-text'), style: t.bodyMedium, textAlign: TextAlign.right),
            ),
            StyleIconButton(key: const Key('lc-opacity-clear'), icon: Icons.close, semantic: '清除', onTap: ed.isOwn('opacity') ? () => ed.apply((s) => s.set('opacity', null)) : null),
          ],
        ),
      ),
    ]);
  }
}

class _TextGroup extends StatelessWidget {
  const _TextGroup(this.ed);
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) => _column([
    StyleColorRow(ed, 'color', '颜色'),
    StyleLengthRow(ed, 'font-size', '字号', stepper: true),
    StyleChoiceRow(
      ed,
      'font-weight',
      '粗细',
      const [ChoiceOption('400', '常规'), ChoiceOption('500', '中等'), ChoiceOption('600', '半粗'), ChoiceOption('700', '加粗')],
      fallback: '400',
      aliases: const {'normal': '400', 'bold': '700'},
    ),
    StyleChoiceRow(ed, 'text-align', '对齐', const [
      ChoiceOption('left', '靠左', icon: Icons.format_align_left),
      ChoiceOption('center', '居中', icon: Icons.format_align_center),
      ChoiceOption('right', '靠右', icon: Icons.format_align_right),
      ChoiceOption('justify', '两端对齐', icon: Icons.format_align_justify),
    ]),
    StyleNumberRow(ed, 'line-height', '行高（倍数）', step: 0.1, min: 0, start: 1.4),
    StyleSwitchRow(ed, 'font-style', '斜体', on: 'italic'),
    StyleChoiceRow(ed, 'text-decoration-line', '装饰线', const [ChoiceOption('none', '无'), ChoiceOption('underline', '下划线'), ChoiceOption('line-through', '删除线')]),
    MoreSection(
      id: 'text',
      initiallyOpen: ed.isOwn('letter-spacing'),
      children: [
        StyleLengthRow(ed, 'letter-spacing', '字间距', allowNegative: true, stepper: true),
        StyleDropdownRow(ed, 'font-weight', '精确粗细', [for (var w = 100; w <= 900; w += 100) ChoiceOption('$w', '$w')], fallbackLabel: '默认（400）'),
      ],
    ),
  ]);
}
