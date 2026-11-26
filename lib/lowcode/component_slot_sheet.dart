// 设计约束（低代码 · 编辑组件 · 给插槽起名 · 390×844）
// - 一个小对话框，只做一件事：给插槽起名。从上到下：标题 → 一句灰字说明插槽是什么 → 名字输入框（自动聚焦，错误写在框下面）→
//   “默认插槽”开关（一行：左边名字和一句灰字，右边开关）→ 取消 / 确定。
// - 组件里已经有默认插槽时，开关是灰的，灰字换成原因。
// - 名字不合适（空的、太长、和别的插槽重名）时不关对话框，原因直接写在输入框下面。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 问一个插槽的名字。[check]：名字合不合适，合适返回 null，不合适返回原因（写在输入框下面）。
/// [canDefault]：还能不能设成默认插槽（组件里已经有一个了就不能）。取消返回 null。
Future<({String label, bool asDefault})?> showSlotNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  bool initialDefault = false,
  required bool canDefault,
  required String? Function(String label, bool asDefault) check,
}) => showDialog<({String label, bool asDefault})>(
  context: context,
  builder: (_) => _SlotNameDialog(title: title, initial: initial, initialDefault: initialDefault, canDefault: canDefault, check: check),
);

class _SlotNameDialog extends StatefulWidget {
  const _SlotNameDialog({required this.title, required this.initial, required this.initialDefault, required this.canDefault, required this.check});
  final String title;
  final String initial;
  final bool initialDefault;
  final bool canDefault;
  final String? Function(String label, bool asDefault) check;

  @override
  State<_SlotNameDialog> createState() => _SlotNameDialogState();
}

class _SlotNameDialogState extends State<_SlotNameDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial);
  late bool _asDefault = widget.initialDefault;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.check(_name.text, _asDefault);
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, (label: _name.text, asDefault: _asDefault));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final locked = !widget.canDefault && !widget.initialDefault;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('插槽是组件里留给外面填内容的空位。用这个组件的时候，可以往里拖别的组件；不填就显示这里放的默认内容。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.x3),
            TextField(
              key: const ValueKey('slot-name-field'),
              controller: _name,
              autofocus: true,
              maxLength: LcNode.maxNameLength,
              decoration: InputDecoration(labelText: '名字', hintText: '比如：内容、底部按钮', errorText: _error, errorMaxLines: 3),
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.x1),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('默认插槽', style: t.bodyMedium),
                      Text(locked ? '这个组件已经有默认插槽了' : '没说放哪儿的内容都进这里；一个组件只有一个', style: t.bodySmall?.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                Switch(
                  key: const ValueKey('slot-default-switch'),
                  value: _asDefault,
                  onChanged: locked
                      ? null
                      : (v) => setState(() {
                          _asDefault = v;
                          _error = null;
                        }),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: c.textMuted),
          child: const Text('取消'),
        ),
        TextButton(key: const ValueKey('slot-name-ok'), onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
