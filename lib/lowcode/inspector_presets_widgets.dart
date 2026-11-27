// 设计约束（低代码 · 合一面板里的几种“行” · 390×844）
// - 内容主次：一行一项——左边 72 宽的名字（次要色），右边是值（主要色）；值是这一行的主角。
// - 数值项＝“预设档 + 自定义”：常用的三四档直接点，选中的那档实心；最后一个“…”展开第二行：
//   整条刻度 + 数字框（能打字）+ 加减（步长 1，按住连加）。值不在常用档上时“…”亮着并写出数值。
//   项目有这一类的主题变量时，展开区最下面多一排变量（第 4 期）；用着变量时这一行最前面是变量的小牌子，各档都不亮。
// - 档位一行放不下时横向滑，不换行、不挤压；每个能点的东西高 36、最小宽 40（排得密，靠 8 的间隔分开）。
// - 这一页没有“主操作”：改了就生效，靠撤销反悔。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accentSoft / accent（选中）、surfaceMuted（没选中）、textMuted（名字）。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/lowcode/inspector_bp_widgets.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:material_ui/material_ui.dart';

/// 一行：名字在左，内容在右（内容太宽就横向滑）。[below] 是展开出来的第二行。
class InspectorRow extends StatelessWidget {
  const InspectorRow({super.key, required this.label, required this.child, this.below, this.scroll = true, this.labelWidth = 72});
  final String label;
  final Widget child;
  final Widget? below;
  final bool scroll;

  /// 名字那一栏的宽度。名字有五个字的单子（比如“重复”的设置）传宽一点，名字和右边的内容才不会贴在一起。
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: t.bodyMedium?.copyWith(color: c.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 画布切到平板 / 桌面档时：内容类的行标一句“不分屏宽”（样子类的行包在 LcPerBp 里，不标）。
                      const LcNoBpTag(),
                    ],
                  ),
                ),
                Expanded(
                  child: scroll ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: child) : child,
                ),
              ],
            ),
          ),
          ?below,
        ],
      ),
    );
  }
}

/// 一个档位 / 选项。选中的实心。
class InspectorChip extends StatelessWidget {
  const InspectorChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.tooltip});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.accent : c.text;
    final chip = Padding(
      padding: const EdgeInsets.only(right: Space.x2),
      child: Material(
        color: selected ? c.accentSoft : c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 36,
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            // 用 Center(widthFactor: 1) 而不是 alignment：宽度跟着字走，放进会换行的一排里也不会把自己撑满整行
            child: Center(
              widthFactor: 1,
              child: icon != null
                  ? Icon(icon, size: 18, color: fg)
                  : Text(
                      label,
                      style: t.bodyMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                    ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

/// 选一个（样子、大小、对齐…）。[options]：值 → 显示的字。
class InspectorChoiceRow extends StatelessWidget {
  const InspectorChoiceRow({super.key, required this.id, required this.label, required this.options, required this.selected, required this.onChanged});
  final String id;
  final String label;
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InspectorRow(
    label: label,
    child: Row(
      children: [for (final e in options.entries) InspectorChip(key: Key('lc-common-$id-${e.key}'), label: e.value, selected: e.key == selected, onTap: () => onChanged(e.key))],
    ),
  );
}

String _fmt(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// 数值项：常用档 + “…”（整条刻度、数字框、加减）。
class PresetRow extends StatefulWidget {
  const PresetRow({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.quick,
    required this.scale,
    required this.onChanged,
    this.names = const {},
    this.clearable = true,
    this.unit = 'px',
    this.vars = const [],
    this.varName,
    this.onVar,
  });
  final String id;
  final String label;

  /// 现在的值；null＝没设（默认）。
  final num? value;

  /// 这一项能用的主题变量（名字、给人看的名字、现在的值）；空＝不提供“用变量”。展开以后列在整条刻度下面。
  final List<({String name, String label, String value})> vars;

  /// 现在用着的变量（[value] 这时是它现在的数）；没用是 null。
  final String? varName;
  final void Function(String name)? onVar;

  /// 直接摆在行里的三四档。
  final List<int> quick;

  /// 展开后的整条刻度。
  final List<int> scale;

  /// 档位显示成别的字（0 → 无，999 → 全圆）。
  final Map<int, String> names;
  final bool clearable;
  final String unit;

  /// [typing]＝打字 / 加减（连续操作，合并成一条撤销）；点档不是。
  final void Function(num? value, {bool typing}) onChanged;

  @override
  State<PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<PresetRow> {
  bool _open = false;
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PresetRow old) {
    super.didUpdateWidget(old);
    // 正在打字时不回填（不然打到一半被改掉）。
    if (!_focus.hasFocus) _sync();
  }

  void _sync() {
    final v = widget.value;
    final s = v == null ? '' : _fmt(v);
    if (_text.text != s) _text.text = s;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _name(int v) => widget.names[v] ?? '$v';

  void _step(int by) {
    final next = ((widget.value ?? 0) + by).clamp(0, 9999);
    widget.onChanged(next, typing: true);
    _text.text = _fmt(next);
  }

  void _hold(int by) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) => _step(by));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = widget.value;
    // 用着变量时不点亮任何一档（那个数是变量给的，不是她点的档）。
    final used = widget.varName == null ? null : widget.vars.where((o) => o.name == widget.varName).firstOrNull;
    final offScale = used == null && v != null && !widget.quick.contains(v);
    return InspectorRow(
      label: widget.label,
      below: !_open
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 72, bottom: Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    runSpacing: Space.x2,
                    children: [for (final s in widget.scale) InspectorChip(key: Key('lc-scale-${widget.id}-$s'), label: _name(s), selected: used == null && v == s, onTap: () => widget.onChanged(s))],
                  ),
                  if (widget.vars.isNotEmpty && widget.onVar != null) ...[
                    const SizedBox(height: Space.x3),
                    Text('主题变量（改了变量，用到的地方一起变）', style: t.labelSmall?.copyWith(color: c.textMuted)),
                    const SizedBox(height: Space.x1),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x2,
                      children: [
                        for (final o in widget.vars)
                          LcVarBadge(key: Key('lc-var-${widget.id}-${o.name}'), label: o.label, value: o.value, selected: o.name == widget.varName, onTap: () => widget.onVar!(o.name)),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.x2),
                  Row(
                    children: [
                      _stepButton(context, 'minus', Icons.remove, -1),
                      SizedBox(
                        width: 72,
                        height: 40,
                        child: TextField(
                          key: Key('lc-num-${widget.id}'),
                          controller: _text,
                          focusNode: _focus,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          style: t.bodyMedium,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '默认',
                            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 10),
                            suffixText: widget.unit.isEmpty ? null : widget.unit,
                          ),
                          onChanged: (s) {
                            final n = num.tryParse(s);
                            if (n != null) widget.onChanged(n, typing: true);
                          },
                        ),
                      ),
                      _stepButton(context, 'plus', Icons.add, 1),
                      if (widget.clearable && v != null)
                        TextButton(
                          key: Key('lc-num-${widget.id}-clear'),
                          onPressed: () {
                            widget.onChanged(null);
                            _text.clear();
                          },
                          style: TextButton.styleFrom(foregroundColor: c.textMuted),
                          child: const Text('恢复默认'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      child: Row(
        children: [
          // 展开以后整条刻度就在下面：这一行不再重复摆那几档（不然像同一行出现了两遍），只说现在是多少。
          if (_open)
            Padding(
              key: Key('lc-preset-${widget.id}-now'),
              padding: const EdgeInsets.only(right: Space.x2),
              child: Text(
                used != null
                    ? used.label
                    : v == null
                    ? '默认'
                    : (widget.names[v] ?? '${_fmt(v)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}'),
                style: t.bodyMedium?.copyWith(color: c.textMuted),
              ),
            )
          else ...[
            if (used != null)
              Padding(
                padding: const EdgeInsets.only(right: Space.x2),
                child: LcVarBadge(key: Key('lc-preset-${widget.id}-var'), label: used.label, value: used.value, onTap: () => setState(() => _open = true)),
              ),
            for (final q in widget.quick) InspectorChip(key: Key('lc-preset-${widget.id}-$q'), label: _name(q), selected: used == null && v == q, onTap: () => widget.onChanged(q)),
          ],
          InspectorChip(
            key: Key('lc-preset-${widget.id}-more'),
            label: _open ? '收起' : (offScale ? '${widget.names[v] ?? _fmt(v)} …' : '…'),
            selected: offScale || _open,
            tooltip: '更多档位和自定义',
            onTap: () => setState(() => _open = !_open),
          ),
        ],
      ),
    );
  }

  // 加减是帮着输入的按钮：包一层 KeyboardKeep，点它不收键盘。
  Widget _stepButton(BuildContext context, String name, IconData icon, int by) => KeyboardKeep(
    child: GestureDetector(
      onLongPressStart: (_) => _hold(by),
      onLongPressEnd: (_) => _repeat?.cancel(),
      onLongPressCancel: () => _repeat?.cancel(),
      child: IconButton(key: Key('lc-num-${widget.id}-$name'), tooltip: by < 0 ? '减 1' : '加 1', icon: Icon(icon, size: 18), onPressed: () => _step(by)),
    ),
  );
}

/// 3×3 九宫格：点哪儿，里面的东西就靠哪儿。[h] / [v] 是 0 / 1 / 2（起点 / 居中 / 终点），不在这三样上是 null。
class AlignGrid extends StatelessWidget {
  const AlignGrid({super.key, required this.h, required this.v, required this.onChanged});
  final int? h;
  final int? v;
  final void Function(int h, int v) onChanged;

  static const List<String> _hName = ['左', '中', '右'];
  static const List<String> _vName = ['上', '中', '下'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.sm)),
      padding: const EdgeInsets.all(Space.x1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var y = 0; y < 3; y++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var x = 0; x < 3; x++)
                  Tooltip(
                    message: '靠${_vName[y]}${_hName[x]}',
                    child: InkWell(
                      key: Key('lc-align-$x-$y'),
                      onTap: () => onChanged(x, y),
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: SizedBox(
                        width: 40,
                        height: 32,
                        child: Center(
                          child: Container(
                            width: h == x && v == y ? 14 : 6,
                            height: h == x && v == y ? 14 : 6,
                            decoration: BoxDecoration(color: h == x && v == y ? c.accent : c.textFaint, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
