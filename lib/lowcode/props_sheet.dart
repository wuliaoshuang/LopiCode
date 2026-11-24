// 设计约束（低代码 · 属性面板 · 390×844）
// - 底部面板，一行一个属性：标签在上（或在左），控件在下（或在右）。
// - 这里只管“内容属性”和第 1 版的简写属性；细的样式在样式面板（style_editor_sheet.dart）。
// - 选中的是自定义组件的实例时，最上面先是它的可配置属性（每个一块，见 component_values_widgets.dart），下面才是宽度、外边距。
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

Color _hex(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

const Map<String, String> _fieldLabels = {
  'text': '文字',
  'src': '图片地址',
  'placeholder': '提示文字',
  'items': '列表项（一行一项）',
  'width': '宽度',
  'height': '高度',
  'padding': '内边距',
  'margin': '外边距',
  'radius': '圆角',
  'gap': '子项间距',
  'fontSize': '字号',
  'size': '间隔大小',
  'bg': '背景色',
  'color': '文字颜色',
  'align': '交叉方向对齐',
  'justify': '主方向分布',
  'textAlign': '文字对齐',
  'bold': '加粗',
};

const List<String> _swatches = ['#FFFFFF', '#F6FBFD', '#D3DEE4', '#707A8F', '#222435', '#058654', '#29D2B2', '#DC3545', '#D98A0B', '#3B6FE0'];

class PropertySheet extends StatefulWidget {
  const PropertySheet({super.key, required this.node, required this.onChanged, this.doc});
  final LcNode node;

  /// 页面文档。选中的是自定义组件的实例时要靠它找到组件定义（有哪些可配置属性）；不给就不显示那一段。
  final LcDocument? doc;
  final void Function(String key, Object? value) onChanged;

  @override
  State<PropertySheet> createState() => PropertySheetState();
}

class PropertySheetState extends State<PropertySheet> {
  final Map<String, TextEditingController> _text = {};

  LcNode get n => widget.node;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, Object? value) {
    widget.onChanged(key, value);
    setState(() {});
  }

  TextEditingController _controller(String key, String initial) => _text.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x6),
        children: [
          Text('${n.type == 'component' && widget.doc != null ? componentLabel(widget.doc!, n) : n.spec.label}属性', style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.x2),
          if (n.type == 'component' && widget.doc != null) ...[
            const SizedBox(height: Space.x2),
            // 改的是这个实例自己传的值（props.values）；整张表交回去，空了就把 values 去掉。
            ComponentValuesForm(doc: widget.doc!, node: n, onChanged: (values) => _set('values', values)),
          ],
          for (final key in n.spec.fields) ...[const SizedBox(height: Space.x3), _field(context, key)],
        ],
      ),
    );
  }

  Widget _labeled(BuildContext context, String key, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_fieldLabels[key] ?? key, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _field(BuildContext context, String key) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    switch (key) {
      case 'text' || 'src' || 'placeholder':
        return _labeled(
          context,
          key,
          TextField(
            controller: _controller(key, n.strProp(key) ?? ''),
            minLines: 1,
            maxLines: key == 'text' ? 4 : 1,
            keyboardType: key == 'src' ? TextInputType.url : null,
            decoration: InputDecoration(hintText: key == 'src' ? 'https://…（留空显示占位图）' : null),
            onChanged: (v) => _set(key, v),
          ),
        );
      case 'items':
        final items = ((n.props['items'] as List?) ?? const []).join('\n');
        return _labeled(context, key, TextField(controller: _controller(key, items), minLines: 3, maxLines: 8, onChanged: (v) => _set(key, v.split('\n').where((s) => s.trim().isNotEmpty).toList())));
      case 'width':
        final w = n.props['width'];
        final mode = w == 'fill' ? 'fill' : (w is num ? 'fixed' : 'auto');
        return _labeled(
          context,
          key,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('自适应')),
                  ButtonSegment(value: 'fill', label: Text('撑满')),
                  ButtonSegment(value: 'fixed', label: Text('固定')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => _set('width', switch (s.first) {
                  'fill' => 'fill',
                  'fixed' => 160,
                  _ => null,
                }),
              ),
              if (w is num) ...[const SizedBox(height: Space.x2), _Stepper(value: w, step: 8, onChanged: (v) => _set('width', v ?? 0))],
            ],
          ),
        );
      case 'height' || 'padding' || 'margin' || 'radius' || 'gap' || 'fontSize' || 'size':
        return Row(
          children: [
            Expanded(child: Text(_fieldLabels[key]!, style: t.bodyMedium)),
            _Stepper(value: n.numProp(key), step: key == 'fontSize' ? 2 : (key == 'height' ? 8 : 4), clearable: key != 'size', onChanged: (v) => _set(key, v)),
          ],
        );
      case 'bg' || 'color':
        final current = n.strProp(key);
        return _labeled(
          context,
          key,
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              if (key == 'bg') _Swatch(color: null, selected: current == null, onTap: () => _set(key, null)),
              for (final hex in _swatches) _Swatch(color: _hex(hex), selected: current == hex, onTap: () => _set(key, hex)),
            ],
          ),
        );
      case 'align' || 'justify' || 'textAlign':
        final options = switch (key) {
          'align' => const {'start': '起点', 'center': '居中', 'end': '终点', 'stretch': '拉伸'},
          'justify' => const {'start': '起点', 'center': '居中', 'end': '终点', 'between': '两端'},
          _ => const {'left': '靠左', 'center': '居中', 'right': '靠右'},
        };
        final fallback = switch (key) {
          'align' => n.type == 'row' ? 'center' : 'start',
          'justify' => 'start',
          _ => 'left',
        };
        return _labeled(
          context,
          key,
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {n.strProp(key) ?? fallback},
              onSelectionChanged: (s) => _set(key, s.first),
            ),
          ),
        );
      case 'bold':
        return Row(
          children: [
            Expanded(child: Text(_fieldLabels[key]!, style: t.bodyMedium)),
            Switch(value: n.props['bold'] == true, onChanged: (v) => _set('bold', v ? true : null)),
          ],
        );
    }
    return Text(key, style: TextStyle(color: c.textFaint));
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.step, required this.onChanged, this.clearable = true});
  final num? value;
  final num step;
  final bool clearable;
  final void Function(num? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = value;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 18, color: onTap == null ? c.border : c.text)),
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            Icons.remove,
            v == null
                ? null
                : () {
                    final next = v - step;
                    // 减到 0 以下：可清除的属性回到“不设置”，其余停在 0。
                    onChanged(next < 0 ? (clearable ? null : 0) : next);
                  },
          ),
          SizedBox(
            width: 56,
            child: Text(v == null ? '默认' : (v == v.roundToDouble() ? '${v.round()}' : '$v'), textAlign: TextAlign.center, style: v == null ? t.bodySmall : t.titleSmall),
          ),
          btn(Icons.add, () => onChanged((v ?? 0) + step)),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        // 选中 = 外圈一道环 + 留白，和色块本身的颜色无关（绿色块上的绿边框看不出来）
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? c.text : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
          child: color == null ? Icon(Icons.block, size: 16, color: c.textFaint) : null,
        ),
      ),
    );
  }
}
