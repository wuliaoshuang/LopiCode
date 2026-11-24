// 设计约束（样式面板里“一行一个属性”的现成排法；390×844）
// - 每个类就是一行：左边属性的中文名，右边一个控件；值来自“属性”时名字下面带一句弱化的“继承自属性”。
// - 显示的是最终值（简写属性被 style 盖过之后），改的是节点自己的 style；清除＝删掉 style 里这一条。
// - 选项多到一行放不下的按钮组（五六个）标签在上、按钮组占满一行。
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/style_color_sheet.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

const String kInheritedHint = '继承自属性';

String? _hint(StyleEdit ed, String name) => ed.inherited(name) ? kInheritedHint : null;

/// 一个长度属性。
class StyleLengthRow extends StatelessWidget {
  const StyleLengthRow(this.ed, this.name, this.label, {super.key, this.allowNegative = false, this.allowAuto = false, this.stepper = false});
  final StyleEdit ed;
  final String name;
  final String label;
  final bool allowNegative;
  final bool allowAuto;
  final bool stepper;

  @override
  Widget build(BuildContext context) => StyleRow(
    label: label,
    hint: _hint(ed, name),
    child: LengthField(
      id: name,
      value: ed.shown.length(name),
      inherited: ed.inherited(name),
      allowNegative: allowNegative,
      allowAuto: allowAuto,
      stepper: stepper,
      onChanged: (v, {required merge}) => ed.apply((s) => s.setLength(name, v), merge: merge),
    ),
  );
}

/// 一个不带单位的数字属性（层级、伸展、行高）。值不是数字（比如行高写了 `24px`）时原样显示，只能清除。
class StyleNumberRow extends StatelessWidget {
  const StyleNumberRow(this.ed, this.name, this.label, {super.key, this.step = 1, this.min, this.integer = false, this.start = 0});
  final StyleEdit ed;
  final String name;
  final String label;
  final double start;
  final double step;
  final double? min;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    final raw = ed.resolved[name];
    final value = ed.shown.number(name);
    if (raw != null && value == null) return StyleRawRow(ed, name, label);
    return StyleRow(
      label: label,
      hint: _hint(ed, name),
      child: NumberField(
        id: name,
        value: value,
        inherited: ed.inherited(name),
        step: step,
        min: min,
        integer: integer,
        start: start,
        onChanged: (v, {required merge}) => ed.apply((s) => s.setNumber(name, v), merge: merge),
      ),
    );
  }
}

/// 面板改不了的写法：把原文摆出来，告诉用户去 CSS 里改，可以清除。
class StyleRawRow extends StatelessWidget {
  const StyleRawRow(this.ed, this.name, this.label, {super.key});
  final StyleEdit ed;
  final String name;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return StyleRow(
      label: label,
      hint: '这种写法要去 CSS 里改',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 150),
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(
              ed.resolved[name] ?? '',
              style: t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StyleIconButton(key: Key('lc-raw-$name-clear'), icon: Icons.close, semantic: '清除', onTap: ed.isOwn(name) ? () => ed.apply((s) => s.set(name, null)) : null),
        ],
      ),
    );
  }
}

/// 按钮组选一个。[fallback] 是没设时浏览器的默认值（弱化地标出来，让用户知道现在是什么）。
/// [aliases]：别的写法当成哪个选项（`bold` 当 `700`）。
class StyleChoiceRow extends StatelessWidget {
  const StyleChoiceRow(this.ed, this.name, this.label, this.options, {super.key, this.fallback, this.stacked = false, this.aliases = const {}});
  final StyleEdit ed;
  final String name;
  final String label;
  final List<ChoiceOption> options;
  final String? fallback;
  final bool stacked;
  final Map<String, String> aliases;

  @override
  Widget build(BuildContext context) {
    final raw = ed.resolved[name]?.trim().toLowerCase();
    final current = aliases[raw] ?? raw;
    final known = current != null && options.any((o) => o.value == current);
    return StyleRow(
      label: label,
      stacked: stacked,
      hint: raw != null && !known ? '现在是 $raw' : _hint(ed, name),
      child: ChoiceButtons(
        id: name,
        options: options,
        selected: known ? current : (raw == null ? fallback : null),
        inherited: !ed.isOwn(name),
        expand: stacked,
        onChanged: (v) => ed.apply((s) => s.set(name, v)),
      ),
    );
  }
}

/// 下拉选一个；菜单最后有“恢复默认”（＝清除）。
class StyleDropdownRow extends StatelessWidget {
  const StyleDropdownRow(this.ed, this.name, this.label, this.options, {super.key, this.fallbackLabel = '默认'});
  final StyleEdit ed;
  final String name;
  final String label;
  final List<ChoiceOption> options;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final raw = ed.resolved[name]?.trim().toLowerCase();
    String text = fallbackLabel;
    if (raw != null) {
      text = raw;
      for (final o in options) {
        if (o.value == raw) text = o.label;
      }
    }
    return StyleRow(
      label: label,
      hint: _hint(ed, name),
      child: StyleMenu(
        key: Key('lc-menu-$name'),
        width: 132,
        text: text,
        faint: !ed.isOwn(name),
        options: [...options, if (ed.isOwn(name)) const ChoiceOption('', '恢复默认')],
        onSelected: (v) => ed.apply((s) => s.set(name, v.isEmpty ? null : v)),
      ),
    );
  }
}

/// 开关：开＝写 [on]，关＝写 [off]（[off] 为 null 就是删掉这一条）。
class StyleSwitchRow extends StatelessWidget {
  const StyleSwitchRow(this.ed, this.name, this.label, {super.key, required this.on, this.off});
  final StyleEdit ed;
  final String name;
  final String label;
  final String on;
  final String? off;

  @override
  Widget build(BuildContext context) => StyleRow(
    label: label,
    hint: _hint(ed, name),
    child: Switch(key: Key('lc-switch-$name'), value: ed.resolved[name]?.trim().toLowerCase() == on, onChanged: (v) => ed.apply((s) => s.set(name, v ? on : off))),
  );
}

/// 颜色按钮：色块 + 原文，点开取色面板。
class ColorButton extends StatelessWidget {
  const ColorButton({super.key, required this.id, required this.value, required this.onChanged, this.faint = false, this.title = '选择颜色'});
  final String id;

  /// 颜色原文；null＝没设。
  final String? value;
  final bool faint;
  final String title;

  /// null＝清除。
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = value;
    return InkWell(
      key: Key('lc-color-$id'),
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () async {
        final r = await showStyleColorPicker(context, initial: v, title: title);
        if (r != null) onChanged(r.css);
      },
      child: Container(
        height: 40,
        width: 148,
        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            ColorDot(argb: cssColorToArgb(v)),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                v ?? '未设置',
                style: t.bodyMedium?.copyWith(color: v == null ? c.textFaint : (faint ? c.textMuted : c.text)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// 一个颜色属性。
class StyleColorRow extends StatelessWidget {
  const StyleColorRow(this.ed, this.name, this.label, {super.key});
  final StyleEdit ed;
  final String name;
  final String label;

  @override
  Widget build(BuildContext context) => StyleRow(
    label: label,
    hint: _hint(ed, name),
    child: ColorButton(id: name, value: ed.resolved[name], faint: ed.inherited(name), title: label, onChanged: (v) => ed.apply((s) => s.setColor(name, v))),
  );
}

/// 四边 / 四角的长度：联动时一行，分开时四行；最后一行是联动开关。
class StyleSidesRows extends StatefulWidget {
  const StyleSidesRows(this.ed, this.group, {super.key, required this.label, required this.sideLabels, this.onSet});
  final StyleEdit ed;

  /// 简写名：border-width / border-radius。
  final String group;
  final String label;

  /// 四个单项各叫什么（顺序同 [LcStyle.sideNames]）。
  final List<String> sideLabels;

  /// 写完长度之后顺手再做点什么（边框：设了宽度却没有样式时补上实线）。names 是这次写了哪几条。
  final void Function(LcStyle s, List<String> names, LcLength? value)? onSet;

  @override
  State<StyleSidesRows> createState() => _StyleSidesRowsState();
}

class _StyleSidesRowsState extends State<StyleSidesRows> {
  /// 默认：四个值一样就联动，不一样就分开（不然一联动就把不一样的值盖了）。
  late bool _linked = widget.ed.shown.lengthSides(widget.group).isUniform;

  @override
  Widget build(BuildContext context) {
    final ed = widget.ed;
    final names = LcStyle.sideNames(widget.group);
    final sides = ed.shown.lengthSides(widget.group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_linked)
          StyleRow(
            label: widget.label,
            hint: sides.isUniform ? (names.every(ed.inherited) ? kInheritedHint : null) : '四个不一样，改了会一起变',
            child: LengthField(
              id: widget.group,
              value: sides.isUniform ? sides.top : null,
              inherited: !names.any(ed.isOwn),
              stepper: true,
              onChanged: (v, {required merge}) => ed.apply((s) {
                s.setAllSides(widget.group, v);
                widget.onSet?.call(s, names, v);
              }, merge: merge),
            ),
          )
        else
          for (var i = 0; i < 4; i++)
            StyleRow(
              label: widget.sideLabels[i],
              hint: _hint(ed, names[i]),
              child: LengthField(
                id: names[i],
                value: sides.values[i],
                inherited: ed.inherited(names[i]),
                stepper: true,
                onChanged: (v, {required merge}) => ed.apply((s) {
                  s.setLength(names[i], v);
                  widget.onSet?.call(s, [names[i]], v);
                }, merge: merge),
              ),
            ),
        StyleRow(
          label: '四个一起改',
          child: Switch(key: Key('lc-link-${widget.group}'), value: _linked, onChanged: (v) => setState(() => _linked = v)),
        ),
      ],
    );
  }
}
