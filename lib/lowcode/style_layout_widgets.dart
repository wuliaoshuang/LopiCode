// 设计约束（样式面板分组内容之二：阴影、布局、定位；390×844）
// - 阴影：第一行是总开关，开了才出现下面的数值；面板改不了的写法（多层）只显示原文并说明去哪里改。
// - 布局：容器第一行是“排法（弹性 / 网格）”，选网格时下面换成列数、列间距、行间距（见 style_grid_widgets.dart）；放在网格里的组件多一行“跨几列”。
// - 布局：容器才有“里面怎么排”的那几行；任何组件都有“自己在父容器里怎么放”的几行。两段之间用小标题分开。
// - 定位：没选定位方式时不摆“上右下左”（设了也不起作用），只说一句为什么。
// - 五六个选项的按钮组（主轴分布、交叉轴对齐、定位方式）标签在上、占满一行；用文字不用图标——
//   这几个选项的图标（两端 / 环绕 / 均分）在手机上分不清。
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_grid_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

Widget _column(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);

Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: Space.x2),
  child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textFaint, height: 1.5)),
);

Widget _heading(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: Space.x4, bottom: Space.x1),
  child: Text(text, style: Theme.of(context).textTheme.labelMedium),
);

/// 打开阴影开关时给的默认阴影：往下 2px、模糊 8px、20% 的黑。
const LcShadow kDefaultShadow = LcShadow(y: LcLength.px(2), blur: LcLength.px(8), color: '#00000033');

class ShadowGroup extends StatelessWidget {
  const ShadowGroup(this.ed, {super.key});
  final StyleEdit ed;

  void _set(LcShadow old, {LcLength? x, LcLength? y, LcLength? blur, LcLength? spread, String? color, bool clearColor = false, bool? inset, bool merge = false}) {
    final next = LcShadow(x: x ?? old.x, y: y ?? old.y, blur: blur ?? old.blur, spread: spread ?? old.spread, color: clearColor ? null : (color ?? old.color), inset: inset ?? old.inset);
    ed.apply((s) => s.setShadow(next), merge: merge);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final raw = ed.resolved['box-shadow']?.trim();
    final on = raw != null && raw.toLowerCase() != 'none';
    final sh = ed.shown.shadow;
    Widget len(String id, String label, LcLength value, void Function(LcLength v, bool merge) set, {bool negative = false}) => StyleRow(
      label: label,
      // 阴影的四个数必须都在，所以这里没有“清除”；清成空就当 0。
      child: LengthField(id: 'shadow-$id', value: value, allowNegative: negative, stepper: true, clearable: false, onChanged: (v, {required merge}) => set(v ?? const LcLength.px(0), merge)),
    );
    return _column([
      StyleRow(
        label: '阴影',
        child: Switch(key: const Key('lc-shadow-on'), value: on, onChanged: (v) => ed.apply((s) => v ? s.setShadow(kDefaultShadow) : s.set('box-shadow', null))),
      ),
      if (on && sh == null) ...[
        Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
          child: Text(
            raw,
            key: const Key('lc-shadow-raw'),
            style: t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, color: c.text),
          ),
        ),
        _note(context, '这是多层阴影（或面板认不出的写法），这里改不了：点右上角“CSS”去改 box-shadow。关掉上面的开关会把它整个删掉。'),
      ],
      if (sh != null) ...[
        len('x', '左右偏移', sh.x, (v, m) => _set(sh, x: v, merge: m), negative: true),
        len('y', '上下偏移', sh.y, (v, m) => _set(sh, y: v, merge: m), negative: true),
        len('blur', '模糊', sh.blur, (v, m) => _set(sh, blur: v, merge: m)),
        len('spread', '扩散', sh.spread, (v, m) => _set(sh, spread: v, merge: m), negative: true),
        StyleRow(
          label: '颜色',
          hint: sh.color == null ? '没写：跟着文字颜色' : null,
          child: ColorButton(
            id: 'shadow',
            value: sh.color,
            title: '阴影颜色',
            onChanged: (v) => _set(sh, color: v, clearColor: v == null),
          ),
        ),
        StyleRow(
          label: '内阴影',
          hint: '画在组件里面',
          child: Switch(
            key: const Key('lc-shadow-inset'),
            value: sh.inset,
            onChanged: (v) => _set(sh, inset: v),
          ),
        ),
      ],
    ]);
  }
}

const List<ChoiceOption> _justify = [
  ChoiceOption('flex-start', '起点'),
  ChoiceOption('center', '居中'),
  ChoiceOption('flex-end', '终点'),
  ChoiceOption('space-between', '两端'),
  ChoiceOption('space-around', '环绕'),
  ChoiceOption('space-evenly', '均分'),
];
const List<ChoiceOption> _alignItems = [ChoiceOption('flex-start', '起点'), ChoiceOption('center', '居中'), ChoiceOption('flex-end', '终点'), ChoiceOption('stretch', '拉伸'), ChoiceOption('baseline', '基线')];
const List<ChoiceOption> _alignSelf = [ChoiceOption('auto', '跟着容器'), ..._alignItems];
const List<ChoiceOption> _display = [
  ChoiceOption('flex', '弹性（flex）'),
  ChoiceOption('block', '块（block）'),
  ChoiceOption('inline-block', '行内块'),
  ChoiceOption('inline', '行内'),
  ChoiceOption('grid', '网格（grid）'),
  ChoiceOption('none', '隐藏'),
];

class LayoutGroup extends StatelessWidget {
  const LayoutGroup(this.ed, {super.key});
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) {
    // 带插槽的组件（列表行、导航栏、标签页、弹窗）里面怎么排是它自己定的，不出“排法”这些行。
    final container = ed.node.isContainer && !ed.node.hasSlots;
    final rowGap = ed.shown.length('row-gap');
    final colGap = ed.shown.length('column-gap');
    final sameGap = rowGap == colGap;
    final hidden = ed.resolved['display']?.trim().toLowerCase() == 'none';
    const more = ['flex-shrink', 'flex-basis'];
    final grid = container && lcIsGrid(ed.resolved);
    final span = ed.parentColumns;
    return _column([
      if (container) ...[_heading(context, '里面的组件怎么排'), GridModeRow(ed), if (grid) GridRows(ed)],
      if (container && !grid) ...[
        // 没设时的方向跟组件类型走（“行”是横的，其余容器是竖的），和导出的页面一致。
        StyleChoiceRow(ed, 'flex-direction', '方向', const [ChoiceOption('row', '横向'), ChoiceOption('column', '竖向')], fallback: ed.node.type == 'row' ? 'row' : 'column'),
        StyleSwitchRow(ed, 'flex-wrap', '放不下时换行', on: 'wrap'),
        StyleChoiceRow(ed, 'justify-content', '主轴分布（顺着排列方向）', _justify, stacked: true, fallback: 'flex-start'),
        StyleChoiceRow(ed, 'align-items', '交叉轴对齐（垂直于排列方向）', _alignItems, stacked: true),
        StyleRow(
          label: '子项间距',
          hint: sameGap ? (ed.inherited('row-gap') && ed.inherited('column-gap') ? (ed.inheritedHint ?? kInheritedHint) : null) : '行、列间距不一样',
          child: LengthField(
            id: 'gap',
            value: sameGap ? rowGap : null,
            inherited: !ed.isOwn('row-gap') && !ed.isOwn('column-gap'),
            stepper: true,
            onChanged: (v, {required merge}) => ed.apply((s) {
              s.setLength('row-gap', v);
              s.setLength('column-gap', v);
            }, merge: merge),
          ),
        ),
      ],
      if (container) _heading(context, '自己在父容器里怎么放'),
      if (span != null) GridSpanRow(ed, columns: span),
      StyleDropdownRow(ed, 'align-self', '自身对齐', _alignSelf, fallbackLabel: '跟着容器'),
      StyleNumberRow(ed, 'flex-grow', '伸展（分剩余空间）', min: 0),
      StyleDropdownRow(ed, 'display', '显示方式', _display),
      if (hidden) _note(context, '现在是“隐藏”：页面上看不到这个组件，也不占位置。'),
      MoreSection(
        id: 'layout',
        initiallyOpen: more.any(ed.isOwn) || (container && !grid && !sameGap),
        children: [
          StyleNumberRow(ed, 'flex-shrink', '收缩（空间不够时）', min: 0),
          StyleLengthRow(ed, 'flex-basis', '基准尺寸', allowAuto: true),
          if (container && !grid) ...[StyleLengthRow(ed, 'row-gap', '行间距', stepper: true), StyleLengthRow(ed, 'column-gap', '列间距', stepper: true)],
        ],
      ),
    ]);
  }
}

const List<ChoiceOption> _position = [ChoiceOption('static', '默认'), ChoiceOption('relative', '相对'), ChoiceOption('absolute', '绝对'), ChoiceOption('fixed', '固定'), ChoiceOption('sticky', '吸顶')];
const List<ChoiceOption> _overflow = [ChoiceOption('visible', '照常显示'), ChoiceOption('hidden', '裁掉'), ChoiceOption('scroll', '总是可滚动'), ChoiceOption('auto', '超出才滚动')];

class PositionGroup extends StatelessWidget {
  const PositionGroup(this.ed, {super.key});
  final StyleEdit ed;

  @override
  Widget build(BuildContext context) {
    final pos = ed.resolved['position']?.trim().toLowerCase();
    final positioned = pos != null && pos != 'static';
    const sides = {'top': '距上', 'right': '距右', 'bottom': '距下', 'left': '距左'};
    // 以前设过上右下左、后来把定位改回默认：值还在，得让用户看得到、清得掉。
    final leftover = sides.keys.any(ed.isOwn);
    return _column([
      StyleChoiceRow(ed, 'position', '定位方式', _position, stacked: true, fallback: 'static'),
      if (positioned || leftover)
        for (final e in sides.entries) StyleLengthRow(ed, e.key, e.value, allowNegative: true, allowAuto: true, stepper: true),
      if (!positioned) _note(context, leftover ? '定位方式是“默认”时，上面这四个值不起作用。' : '选了相对 / 绝对 / 固定 / 吸顶之后，才能设距上、距右、距下、距左。'),
      StyleNumberRow(ed, 'z-index', '层级（大的在上面）', integer: true),
      _heading(context, '内容超出时'),
      StyleDropdownRow(ed, 'overflow-x', '横向超出', _overflow, fallbackLabel: '照常显示'),
      StyleDropdownRow(ed, 'overflow-y', '纵向超出', _overflow, fallbackLabel: '照常显示'),
    ]);
  }
}
