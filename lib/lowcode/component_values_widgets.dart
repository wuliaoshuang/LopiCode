// 设计约束（低代码 · 自定义组件的“值” · 390×844）
// - 一个属性占一块：第一行是名字 + 类型（右边在改过时出现“恢复默认”），第二行是按类型换的控件：
//   文字＝输入框；数字＝数字输入框；开关＝一个开关；颜色＝一排常用色块 + “其它颜色”。
// - 这里的控件既用在属性面板里（改某个实例传的值），也用在“改默认值”的对话框里。
// - 填错（数字框里不是数字）不改数据，输入框下面说明原因。
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_color_sheet.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 属性的中文叫法（绑定列表里用）。
String bindablePropLabel(String attr) => switch (attr) {
  'text' => '文字',
  'src' => '图片地址',
  'placeholder' => '提示文字',
  'bg' => '背景色',
  'color' => '文字颜色',
  _ => attr,
};

/// prop 类型的中文叫法。
String componentPropTypeLabel(String type) => switch (type) {
  'number' => '数字',
  'color' => '颜色',
  'bool' => '开关',
  _ => '文字',
};

/// 一个值写成给人看的短句（列表副标题里用）。
String componentValueSummary(Object? v) => switch (v) {
  final bool b => b ? '开' : '关',
  final String s => s.isEmpty ? '（空）' : '“$s”',
  _ => componentValueText(v),
};

const List<String> _swatches = ['#FFFFFF', '#F6FBFD', '#D3DEE4', '#707A8F', '#222435', '#000000', '#058654', '#29D2B2', '#DC3545', '#D98A0B', '#3B6FE0'];

int _argb(String hex) => 0xFF000000 | int.parse(hex.substring(1), radix: 16);

String _hexOf(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 把输入框里的字读成数字；读不出来返回 null。整数给 int（存盘里是 3 不是 3.0）。
num? _parseNumber(String text) {
  final s = text.trim();
  final v = int.tryParse(s) ?? double.tryParse(s);
  return v != null && v.isFinite ? v : null;
}

/// 按类型换的一个值的编辑控件。[onChanged] 只在值合法时调。
class ComponentValueField extends StatefulWidget {
  const ComponentValueField({super.key, required this.type, required this.value, required this.onChanged, this.autofocus = false});
  final String type;
  final Object value;
  final void Function(Object value) onChanged;
  final bool autofocus;

  @override
  State<ComponentValueField> createState() => _ComponentValueFieldState();
}

class _ComponentValueFieldState extends State<ComponentValueField> {
  late final TextEditingController _text = TextEditingController(text: componentValueText(widget.value));
  String? _error;

  @override
  void didUpdateWidget(ComponentValueField old) {
    super.didUpdateWidget(old);
    // 外面把值换了（恢复默认、撤销）：输入框跟着换；自己正在打字引起的变化不动它，免得光标乱跳。
    final shown = widget.type == 'number' ? _parseNumber(_text.text) : _text.text;
    if (widget.value != old.value && widget.value != shown) {
      _text.text = componentValueText(widget.value);
      _error = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showStyleColorPicker(context, initial: '${widget.value}', title: '选择颜色');
    final argb = cssColorToArgb(picked?.css);
    // 组件的颜色属性只存 #RRGGBB：透明度不带。
    if (argb != null) widget.onChanged(_hexOf(argb));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (widget.type) {
      case 'bool':
        return Align(
          alignment: Alignment.centerLeft,
          child: Switch(value: widget.value == true, onChanged: widget.onChanged),
        );
      case 'color':
        final current = '${widget.value}'.toUpperCase();
        return Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final hex in _swatches)
              GestureDetector(
                key: ValueKey('comp-swatch-$hex'),
                onTap: () => widget.onChanged(hex),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm + 2),
                    border: Border.all(color: current == hex ? c.text : Colors.transparent, width: 2),
                  ),
                  child: ColorDot(argb: _argb(hex), size: 28),
                ),
              ),
            TextButton.icon(
              onPressed: _pickColor,
              icon: ColorDot(argb: cssColorToArgb(current), size: 18),
              label: Text(_swatches.contains(current) ? '其它颜色' : current),
            ),
          ],
        );
      case 'number':
        return TextField(
          controller: _text,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(errorText: _error),
          onChanged: (s) {
            final v = _parseNumber(s);
            setState(() => _error = v == null ? '这里要填数字' : null);
            if (v != null) widget.onChanged(v);
          },
        );
      default:
        return TextField(controller: _text, autofocus: widget.autofocus, minLines: 1, maxLines: 4, onChanged: widget.onChanged);
    }
  }
}

/// 属性面板里“组件实例的值”那一段：每个 prop 一块。改的是实例的 `props.values`：
/// [onChanged] 拿到整张新的表（空了给 null，调用方把 `values` 整个去掉）。
class ComponentValuesForm extends StatelessWidget {
  const ComponentValuesForm({super.key, required this.doc, required this.node, required this.onChanged});
  final LcDocument doc;
  final LcNode node;
  final void Function(Map<String, dynamic>? values) onChanged;

  void _set(LcComponentProp p, Object? value) {
    final old = node.props['values'];
    final next = <String, dynamic>{
      if (old is Map)
        for (final MapEntry(:key, value: v) in old.entries)
          if (key is String && key != p.name) key: v,
      if (value != null && valueFitsProp(p, value)) p.name: value,
    };
    onChanged(next.isEmpty ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ref = node.props['ref'];
    final def = ref is String ? doc.component(ref) : null;
    if (def == null) {
      return Text('这个组件的定义已经不存在了（可能被删掉了）。可以把它删除，或者撤销刚才的操作。', style: t.bodyMedium?.copyWith(color: c.danger));
    }
    if (def.props.isEmpty) {
      return Text('这个组件还没有可配置的属性。到“更多操作 › 编辑组件”里添加后，就能在这里给每个实例填不同的内容。', style: t.bodySmall);
    }
    final values = instanceValues(def, node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in def.props) ...[
          Row(
            children: [
              Expanded(
                child: Text('${p.name} · ${componentPropTypeLabel(p.type)}', style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (instanceOverrides(def, node, p.name))
                TextButton(
                  key: ValueKey('comp-reset-${p.name}'),
                  onPressed: () => _set(p, null),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('恢复默认'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ComponentValueField(key: ValueKey('comp-value-${p.name}'), type: p.type, value: values[p.name] ?? p.defaultValue, onChanged: (v) => _set(p, v)),
          const SizedBox(height: Space.x4),
        ],
      ],
    );
  }
}

/// 问一行文字（组件名、属性名）。[validate] 返回 null＝可以；否则把原因显示在输入框下面，不关对话框。取消返回 null。
Future<String?> askComponentText(BuildContext context, {required String title, String initial = '', String? hint, String confirmLabel = '确定', required String? Function(String text) validate}) {
  final controller = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final problem = validate(controller.text);
          if (problem == null) {
            Navigator.pop(context, controller.text.trim());
          } else {
            setState(() => error = problem);
          }
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            key: const ValueKey('comp-ask-text'),
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint, errorText: error, errorMaxLines: 3),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
              child: const Text('取消'),
            ),
            TextButton(onPressed: submit, child: Text(confirmLabel)),
          ],
        );
      },
    ),
  );
}

/// 问一个值（改属性的默认值）。取消返回 null。
Future<Object?> askComponentValue(BuildContext context, {required String title, required String type, required Object initial}) {
  var value = initial;
  return showDialog<Object>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: ComponentValueField(key: const ValueKey('comp-ask-value'), type: type, value: value, autofocus: true, onChanged: (v) => setState(() => value = v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
            child: const Text('取消'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, value), child: const Text('保存')),
        ],
      ),
    ),
  );
}

/// 说一句话的对话框（操作没做成时说明原因）。
Future<void> tellComponentProblem(BuildContext context, String message) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    content: Text(message),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
  ),
);
