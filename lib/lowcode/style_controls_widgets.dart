// 设计约束（样式面板的通用小控件；390×844，浅色 + 深色）
// - 一行只做一件事：左边是标签（下面可带一句弱化的说明），右边是控件；控件太宽的（五六个选项的按钮组）标签在上、控件占满一行。
// - 所有可点的目标至少 40px 高。
// - 层级靠颜色深浅：自己设的值用正文色，来自“属性”的值用弱化色，非法输入用危险色描边。
// - 这里的控件都不直接改模型，只把新值交给回调；`merge` 为 true 表示“连续操作的一步”（打字、加减），由面板合并成一条撤销记录。
import 'package:flutter/services.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:material_ui/material_ui.dart';

/// 面板交给各分组的“当前样子”和“怎么改”。每次重画换一份，分组自己不存样式。
class StyleEdit {
  const StyleEdit({required this.node, required this.own, required this.resolved, required this.apply, this.parentColumns});

  /// 它放在网格里：那个网格一共几列；不在网格里是 null。
  final int? parentColumns;

  /// 只用来看类型（是不是容器、是不是行）。样式不要从这里读，读 [own] / [resolved]。
  final LcNode node;

  /// 这个节点自己的 style（已经算上还没提交的预览值）。
  final Map<String, String> own;

  /// 最终样式：简写属性翻出来的被 [own] 盖过之后。控件显示的是这一份。
  final Map<String, String> resolved;

  /// 改样式。[merge] 为 true 时和紧接着的改动合并成一条撤销记录（停 400ms 才提交）。
  final void Function(void Function(LcStyle s) change, {bool merge}) apply;

  LcStyle get shown => LcStyle(resolved);
  bool isOwn(String name) => own.containsKey(name);

  /// 值是从“属性”里来的（自己没设）。
  bool inherited(String name) => !own.containsKey(name) && resolved.containsKey(name);
}

/// 数字写成最短的样子：整数不带小数点，小数最多两位。
String fmtNum(double v) {
  if (v == v.roundToDouble()) return '${v.round()}';
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// 一行：标签在左、控件在右。[stacked] 时标签在上、控件占满一行。
class StyleRow extends StatelessWidget {
  const StyleRow({super.key, required this.label, required this.child, this.hint, this.stacked = false});
  final String label;
  final String? hint;
  final Widget child;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (hint != null)
          Text(
            hint!,
            style: t.labelSmall?.copyWith(color: c.textFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: Space.x2),
            child,
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: Space.x2),
          child,
        ],
      ),
    );
  }
}

/// 40×40 的小图标按钮（加、减、清除）。不可用时变淡。
class StyleIconButton extends StatelessWidget {
  const StyleIconButton({super.key, required this.icon, required this.onTap, this.semantic});
  final IconData icon;
  final VoidCallback? onTap;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 18, color: onTap == null ? c.border : c.textMuted, semanticLabel: semantic),
      ),
    );
  }
}

/// 只收数字的输入框。合法就把数交给 [onChanged]；不合法（`-`、`1.2.3`、不许负却是负数）不交、框描红。
/// 没在输入的时候跟着 [value] 走；正在输入时不去改用户敲的字。
class NumberBox extends StatefulWidget {
  const NumberBox({
    super.key,
    required this.id,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowNegative = false,
    this.integer = false,
    this.faint = false,
    this.width = 60,
    this.placeholder,
  });
  final String id;
  final double? value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final bool allowNegative;
  final bool integer;

  /// 弱化显示（值来自属性）。
  final bool faint;
  final double width;
  final String? placeholder;

  @override
  State<NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<NumberBox> {
  late final TextEditingController _text = TextEditingController(text: _show(widget.value));
  final FocusNode _focus = FocusNode();
  bool _invalid = false;

  String _show(double? v) => v == null ? '' : fmtNum(v);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  /// 离开输入框：没敲完的（空的、非法的）恢复成当前值，不留一个红框在那里。
  void _onFocus() {
    if (_focus.hasFocus) return;
    if (_invalid || _parse(_text.text) != widget.value) {
      _text.text = _show(widget.value);
      if (_invalid) setState(() => _invalid = false);
    }
  }

  double? _parse(String s) {
    final v = RegExp(r'^-?(\d+\.?\d*|\.\d+)$').hasMatch(s) ? double.tryParse(s) : null;
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (!widget.allowNegative && v < 0) return null;
    if (widget.integer && v != v.roundToDouble()) return null;
    return v;
  }

  @override
  void didUpdateWidget(NumberBox old) {
    super.didUpdateWidget(old);
    // 外面的值变了（点了加减、换了联动、撤销）：输入框里的字和它对不上才换，免得把用户正敲的 “1.” 改成 “1”。
    final typing = _focus.hasFocus && (_invalid || _text.text.isEmpty);
    if (!typing && _parse(_text.text) != widget.value) {
      _text.text = _show(widget.value);
      _invalid = false;
    }
  }

  void _onChanged(String s) {
    if (s.isEmpty) {
      if (_invalid) setState(() => _invalid = false);
      return;
    }
    final v = _parse(s);
    if ((v == null) != _invalid) setState(() => _invalid = v == null);
    if (v != null && v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: w),
    );
    final pattern = widget.integer ? (widget.allowNegative ? r'[0-9-]' : r'[0-9]') : (widget.allowNegative ? r'[0-9.-]' : r'[0-9.]');
    return SizedBox(
      width: widget.width,
      height: 40,
      child: TextField(
        key: Key('lc-num-${widget.id}'),
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer, signed: widget.allowNegative),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(pattern)), LengthLimitingTextInputFormatter(8)],
        // 键盘弹出时把这一行滚进视野，底下多留一点，别贴着键盘。
        scrollPadding: const EdgeInsets.all(Space.x12),
        style: t.bodyMedium?.copyWith(
          color: !widget.enabled ? c.textFaint : (_invalid ? c.danger : (widget.faint ? c.textMuted : c.text)),
          fontWeight: widget.faint ? FontWeight.w400 : FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: widget.placeholder ?? '–',
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: 10),
          fillColor: widget.enabled ? c.surface : c.surfaceMuted,
          enabledBorder: border(_invalid ? c.danger : c.border, _invalid ? 2 : 1),
          disabledBorder: border(c.border),
          focusedBorder: border(_invalid ? c.danger : c.accentFill, 2),
        ),
        onChanged: _onChanged,
      ),
    );
  }
}

/// 长度：数值 + 单位下拉 +（可选）加减 + 清除。
/// `auto` 时数值框禁用；`calc(…)` 这类面板改不了的写法原样显示，只能清除或去 CSS 里改。
class LengthField extends StatefulWidget {
  const LengthField({
    super.key,
    required this.id,
    required this.value,
    required this.onChanged,
    this.inherited = false,
    this.allowNegative = false,
    this.allowAuto = false,
    this.stepper = false,
    this.clearable = true,
  });

  /// 测试和找控件用的名字（一般就是 CSS 属性名）。
  final String id;

  /// 显示的值（最终值）。
  final LcLength? value;

  /// 这个值是从“属性”来的：弱化显示，清除按钮不可用（没什么可清的）。
  final bool inherited;
  final bool allowNegative;
  final bool allowAuto;
  final bool stepper;
  final bool clearable;
  final void Function(LcLength? value, {required bool merge}) onChanged;

  @override
  State<LengthField> createState() => _LengthFieldState();
}

class _LengthFieldState extends State<LengthField> {
  /// 还没填数字时先选的单位：只记在控件里，等填了数字才一起写进去。
  String _unit = 'px';

  @override
  void initState() {
    super.initState();
    _syncUnit();
  }

  @override
  void didUpdateWidget(LengthField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _syncUnit();
  }

  void _syncUnit() {
    final v = widget.value;
    if (v != null && v.isNumeric) _unit = v.unit;
  }

  double get _step => _unit == 'em' || _unit == 'rem' ? 0.1 : 1;

  void _bump(int dir) {
    final base = widget.value?.value ?? 0;
    var next = double.parse((base + dir * _step).toStringAsFixed(2));
    if (!widget.allowNegative && next < 0) next = 0;
    widget.onChanged(LcLength(next, _unit), merge: true);
  }

  void _pickUnit(String unit) {
    if (unit == 'auto') {
      widget.onChanged(const LcLength.auto(), merge: false);
      return;
    }
    setState(() => _unit = unit);
    final v = widget.value;
    // 已经有数字：换单位立刻生效。从 auto 换回来：先给个 0，不然“auto”还留在那里，看着像没换成。
    if (v != null && v.isNumeric) {
      widget.onChanged(LcLength(v.value!, unit), merge: false);
    } else if (v != null && v.isAuto) {
      widget.onChanged(LcLength(0, unit), merge: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = widget.value;
    final isAuto = v?.isAuto ?? false;
    final isRaw = v != null && !v.isNumeric && !isAuto;
    final canClear = widget.clearable && v != null && !widget.inherited;
    final clear = widget.clearable
        ? StyleIconButton(key: Key('lc-len-${widget.id}-clear'), icon: Icons.close, semantic: '清除', onTap: canClear ? () => widget.onChanged(null, merge: false) : null)
        : null;
    if (isRaw) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 128,
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(
              v.toCss(),
              style: t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?clear,
        ],
      );
    }
    final stepOk = !isAuto;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.stepper)
          KeyboardKeep(
            child: StyleIconButton(key: Key('lc-len-${widget.id}-minus'), icon: Icons.remove, semantic: '减', onTap: stepOk ? () => _bump(-1) : null),
          ),
        NumberBox(
          id: widget.id,
          value: v?.value,
          enabled: !isAuto,
          allowNegative: widget.allowNegative,
          faint: widget.inherited,
          width: widget.stepper ? 56 : 64,
          placeholder: isAuto ? 'auto' : null,
          onChanged: (n) => widget.onChanged(LcLength(n, _unit), merge: true),
        ),
        if (widget.stepper)
          KeyboardKeep(
            child: StyleIconButton(key: Key('lc-len-${widget.id}-plus'), icon: Icons.add, semantic: '加', onTap: stepOk ? () => _bump(1) : null),
          ),
        const SizedBox(width: Space.x1),
        StyleMenu(
          key: Key('lc-len-${widget.id}-unit'),
          width: 60,
          text: isAuto ? 'auto' : _unit,
          faint: widget.inherited,
          options: [for (final u in LcLength.units) ChoiceOption(u, u), if (widget.allowAuto) const ChoiceOption('auto', 'auto（自动）')],
          onSelected: _pickUnit,
        ),
        ?clear,
      ],
    );
  }
}

/// 不带单位的数字（层级、伸展、行高）：加减 + 输入 + 清除。
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.id, required this.value, required this.onChanged, this.inherited = false, this.step = 1, this.min, this.integer = false, this.start = 0});
  final String id;
  final double? value;
  final bool inherited;
  final double step;

  /// 还没设值时点加减从哪个数算起（行高从 1.4 起，点一下加号是 1.5，而不是 0.1）。
  final double start;

  /// 最小值；null＝可以为负。
  final double? min;
  final bool integer;
  final void Function(double? value, {required bool merge}) onChanged;

  void _bump(int dir) {
    var next = double.parse(((value ?? start) + dir * step).toStringAsFixed(2));
    final lo = min;
    if (lo != null && next < lo) next = lo;
    onChanged(next, merge: true);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      KeyboardKeep(
        child: StyleIconButton(key: Key('lc-num-$id-minus'), icon: Icons.remove, semantic: '减', onTap: () => _bump(-1)),
      ),
      NumberBox(id: id, value: value, allowNegative: min == null, integer: integer, faint: inherited, width: 56, onChanged: (n) => onChanged(n, merge: true)),
      KeyboardKeep(
        child: StyleIconButton(key: Key('lc-num-$id-plus'), icon: Icons.add, semantic: '加', onTap: () => _bump(1)),
      ),
      StyleIconButton(key: Key('lc-num-$id-clear'), icon: Icons.close, semantic: '清除', onTap: value != null && !inherited ? () => onChanged(null, merge: false) : null),
    ],
  );
}

/// 一个可选项：值、给人看的名字、可选的图标（有图标时按钮上只画图标，名字当无障碍说明）。
class ChoiceOption {
  const ChoiceOption(this.value, this.label, {this.icon});
  final String value;
  final String label;
  final IconData? icon;
}

/// 按钮组：选一个。再点一下已经选中的＝清除（回到默认 / 属性里的值）。
class ChoiceButtons extends StatelessWidget {
  const ChoiceButtons({super.key, required this.id, required this.options, required this.selected, required this.onChanged, this.inherited = false, this.expand = false});
  final String id;
  final List<ChoiceOption> options;
  final String? selected;

  /// 选中的那个不是自己设的（来自属性或默认）：弱化显示，再点它是“明确设成它”而不是清除。
  final bool inherited;

  /// 占满一行、各项等宽（用在标签在上的宽按钮组）。
  final bool expand;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget cell(ChoiceOption o) {
      final on = o.value == selected;
      final strong = on && !inherited;
      final fg = strong ? c.accent : (on ? c.text : c.textMuted);
      final inner = InkWell(
        key: Key('lc-opt-$id-${o.value}'),
        onTap: () => onChanged(strong ? null : o.value),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          alignment: Alignment.center,
          color: strong ? c.accentSoft : (on ? c.surfaceMuted : null),
          child: o.icon != null
              ? Icon(o.icon, size: 20, color: fg, semanticLabel: o.label)
              : Text(
                  o.label,
                  style: t.bodyMedium?.copyWith(color: fg, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                  maxLines: 1,
                  softWrap: false,
                ),
        ),
      );
      return expand ? Expanded(child: inner) : inner;
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[if (i > 0) Container(width: 1, height: 40, color: c.border), cell(options[i])],
          ],
        ),
      ),
    );
  }
}

/// 下拉：一个 40px 高的框，点开是菜单。选项多、或者不常用的用它。
class StyleMenu extends StatelessWidget {
  const StyleMenu({super.key, required this.text, required this.options, required this.onSelected, this.width, this.faint = false});
  final String text;
  final List<ChoiceOption> options;
  final ValueChanged<String> onSelected;
  final double? width;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.value, height: 44, child: Text(o.label))],
      child: Container(
        width: width,
        height: 40,
        padding: const EdgeInsets.only(left: Space.x2, right: 2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (width == null)
              Text(text, style: t.bodyMedium?.copyWith(color: faint ? c.textMuted : c.text), maxLines: 1)
            else
              Expanded(
                child: Text(
                  text,
                  style: t.bodyMedium?.copyWith(color: faint ? c.textMuted : c.text),
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

/// “更多”：不常用的收在里面，点开才显示。里面已经设过东西时默认展开（不然用户找不到自己设过的）。
class MoreSection extends StatefulWidget {
  const MoreSection({super.key, required this.id, required this.children, this.initiallyOpen = false, this.label = '更多'});
  final String id;
  final List<Widget> children;
  final bool initiallyOpen;
  final String label;

  @override
  State<MoreSection> createState() => _MoreSectionState();
}

class _MoreSectionState extends State<MoreSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('lc-more-${widget.id}'),
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(Radii.md),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Text(widget.label, style: t.labelLarge?.copyWith(color: c.textMuted)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textMuted),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}
