// 设计约束（样式面板的数字类小控件；390×844，浅色 + 深色）——从 style_controls_widgets.dart 拆出来的，规矩同那边：
// - 一行只做一件事；可点的目标至少 40px 高；非法输入用危险色描边。
// - 不直接改模型，只把新值交给回调；`merge` 为 true 表示“连续操作的一步”。
import 'package:flutter/services.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:material_ui/material_ui.dart';

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

const String _useVar = '\u0000var';

/// 菜单从这个控件的右下角弹出来。
RelativeRect _menuPosition(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  return RelativeRect.fromLTRB(at.dx - 200, at.dy, overlay.size.width - at.dx, 0);
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
    // 主题变量：这种属性有能用的变量时，单位菜单里多一项“用变量…”；值已经是变量时整格换成变量的小牌子（点它换一个）。
    final theme = LcThemeScope.of(context);
    final choices = lcVarChoices(theme, widget.id);
    final named = isRaw ? lcVarNameIn(v.toCss()) : null;
    final varName = named != null && theme.values.containsKey(named) ? named : null;
    Future<void> pickVar() async {
      final name = await showMenu<String>(
        context: context,
        position: _menuPosition(context),
        items: [for (final o in choices) PopupMenuItem(key: Key('lc-len-${widget.id}-var-${o.name}'), value: o.name, height: 44, child: Text('${o.label}　${o.value}'))],
      );
      if (name != null) widget.onChanged(LcLength.raw(lcVarRef(name)), merge: false);
    }

    if (varName != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 168),
            child: LcVarBadge(key: Key('lc-len-${widget.id}-var'), label: theme.labelOf(varName), value: theme.resolved(varName), onTap: choices.isEmpty ? null : pickVar),
          ),
          ?clear,
        ],
      );
    }
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
          options: [for (final u in LcLength.units) ChoiceOption(u, u), if (widget.allowAuto) const ChoiceOption('auto', 'auto（自动）'), if (choices.isNotEmpty) const ChoiceOption(_useVar, '用变量…')],
          onSelected: (u) => u == _useVar ? pickVar() : _pickUnit(u),
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
