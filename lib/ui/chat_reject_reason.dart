// 设计约束（确认卡里“拒绝并说明原因”这一小块 · 390×844）
// - 入口是一个小号灰字按钮，和“本对话都允许”并排，不抢“拒绝 / 允许这一次”两个主按钮。
// - 点开以后只有三样东西，从上到下：一行输入框（可以不填）→ 一行两个按钮“取消”“拒绝”。
// - “拒绝”是描边的中性按钮（和卡片上原来的“拒绝”一个样）：拒绝不是值得强调的主操作。原因不填也能点，等于直接拒绝。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class RejectReasonLink extends StatelessWidget {
  const RejectReasonLink({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('reject-reason-open'),
    style: TextButton.styleFrom(foregroundColor: context.colors.textFaint, backgroundColor: Colors.transparent, textStyle: Theme.of(context).textTheme.bodySmall, visualDensity: VisualDensity.compact),
    onPressed: onTap,
    child: const Text('拒绝并说明原因'),
  );
}

class RejectReasonForm extends StatefulWidget {
  const RejectReasonForm({super.key, required this.onCancel, required this.onReject});
  final VoidCallback onCancel;
  final void Function(String reason) onReject;

  @override
  State<RejectReasonForm> createState() => _RejectReasonFormState();
}

class _RejectReasonFormState extends State<RejectReasonForm> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final neutral = OutlinedButton.styleFrom(
      foregroundColor: c.text,
      side: BorderSide(color: c.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('reject-reason-field'),
          controller: _text,
          autofocus: true,
          maxLines: 1,
          maxLength: kDenyReasonMaxChars,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '为什么拒绝？Agent 会看到这句话（可以不填）', counterText: ''),
          onSubmitted: widget.onReject,
        ),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(key: const Key('reject-reason-cancel'), style: neutral, onPressed: widget.onCancel, child: const Text('取消')),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: OutlinedButton(key: const Key('reject-reason-submit'), style: neutral, onPressed: () => widget.onReject(_text.text), child: const Text('拒绝')),
            ),
          ],
        ),
      ],
    );
  }
}
