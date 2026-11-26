// 设计约束（盒模型示意编辑器；390×844）
// - 上面是示意图：外圈＝外边距，里圈＝内边距，中间写尺寸。每个方向一个可点的数值（点击目标 48×40）。
// - 示意图只负责“看”和“选哪一边”；改数值在示意图下面那一行（数值 + 加减 + 单位 + 清除），一次只改选中的那一边。
// - 再下面一行是“四边联动”开关，管的是选中的那一圈（外边距、内边距各记各的）。
// - 颜色：选中的数值用实心强调色；自己设的值用正文色加粗，来自“属性”的弱化，没设的画一个短横。
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

const List<String> _sideText = ['上', '右', '下', '左'];

class BoxModelEditor extends StatefulWidget {
  const BoxModelEditor({super.key, required this.ed});
  final StyleEdit ed;

  @override
  State<BoxModelEditor> createState() => _BoxModelEditorState();
}

class _BoxModelEditorState extends State<BoxModelEditor> {
  String _ring = 'padding';
  int _side = 0;

  /// 两圈各自的联动开关。默认：四边一样就联动，不一样就分开（不然一改就把不一样的盖了）。
  late final Map<String, bool> _linked = {
    for (final r in const ['margin', 'padding']) r: widget.ed.shown.lengthSides(r).isUniform,
  };

  StyleEdit get ed => widget.ed;
  String get _name => '$_ring-${cssSides[_side]}';
  String get _ringLabel => _ring == 'margin' ? '外边距' : '内边距';

  String _show(LcLength? v) {
    if (v == null) return '–';
    if (v.isAuto) return 'auto';
    if (!v.isNumeric) return '…';
    return v.unit == 'px' ? fmtNum(v.value!) : '${fmtNum(v.value!)}${v.unit}';
  }

  Widget _cell(String ring, int side) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final name = '$ring-${cssSides[side]}';
    final v = ed.shown.length(name);
    // 联动时四边是一个整体，一起亮。
    final selected = ring == _ring && (side == _side || _linked[ring]!);
    final fg = selected ? c.onAccent : (v == null ? c.textFaint : (ed.isOwn(name) ? c.text : c.textMuted));
    return InkWell(
      key: Key('lc-box-$name'),
      onTap: () => setState(() {
        _ring = ring;
        _side = side;
      }),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: SizedBox(
        width: 48,
        height: 40,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 32),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: selected ? c.accentFill : null, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Text(
              _show(v),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: t.bodySmall?.copyWith(color: fg, fontWeight: ed.isOwn(name) || selected ? FontWeight.w600 : FontWeight.w400, height: 1.2),
            ),
          ),
        ),
      ),
    );
  }

  /// 一圈：上面一条（左上角写这一圈叫什么，中间是“上”的数值），中间一行（左、内容、右），下面一条。
  Widget _ringBox(String ring, String label, Color bg, Widget child) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            // 占满整行：这一圈的名字才能贴在左上角，不和中间“上”的数值叠在一起。
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: Space.x2,
                  top: 6,
                  child: Text(label, style: t.labelSmall?.copyWith(color: c.textMuted)),
                ),
                _cell(ring, 0),
              ],
            ),
          ),
          Row(
            children: [
              _cell(ring, 3),
              Expanded(child: child),
              _cell(ring, 1),
            ],
          ),
          _cell(ring, 2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final linked = _linked[_ring]!;
    final sides = ed.shown.lengthSides(_ring);
    final names = LcStyle.sideNames(_ring);
    final w = ed.resolved['width'];
    final h = ed.resolved['height'];
    final size = w == null && h == null ? '尺寸跟着内容' : '${w ?? '自动'} × ${h ?? '自动'}';
    final margin = _ring == 'margin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: _ringBox(
            'margin',
            '外边距',
            c.surfaceMuted,
            _ringBox(
              'padding',
              '内边距',
              c.accentSoft,
              Container(
                height: 44,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  size,
                  style: t.bodySmall?.copyWith(color: c.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.x2),
        StyleRow(
          label: linked ? '$_ringLabel（四边）' : '${_sideText[_side]}$_ringLabel',
          hint: linked
              ? (sides.isUniform ? (names.every(ed.inherited) ? (ed.inheritedHint ?? kInheritedHint) : null) : '四边不一样，改了会一起变')
              : (ed.inherited(_name) ? (ed.inheritedHint ?? kInheritedHint) : null),
          child: LengthField(
            // 换了圈 / 换了边就是另一个输入框：不带着上一个框里敲到一半的字。
            key: ValueKey('box-$_ring-${linked ? 'all' : _side}'),
            id: 'box',
            value: linked ? (sides.isUniform ? sides.top : null) : sides.values[_side],
            inherited: linked ? !names.any(ed.isOwn) : ed.inherited(_name),
            // 外边距可以是负的、可以是 auto（居中用）；内边距不行。
            allowNegative: margin,
            allowAuto: margin,
            stepper: true,
            onChanged: (v, {required merge}) {
              final ring = _ring;
              final name = _name;
              ed.apply((s) => linked ? s.setAllSides(ring, v) : s.setLength(name, v), merge: merge);
            },
          ),
        ),
        StyleRow(
          label: '$_ringLabel四边联动',
          hint: '开着：改一边，四边一起变',
          child: Switch(key: const Key('lc-box-link'), value: linked, onChanged: (v) => setState(() => _linked[_ring] = v)),
        ),
      ],
    );
  }
}
