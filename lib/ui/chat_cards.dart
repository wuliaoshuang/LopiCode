// 设计约束（确认卡 / 提问卡 · 390×844）— 2026-11-24 霜霜嫌原来的配色难看（整张橙底 + 橙字），重做
// - 一个卡壳两种卡共用：白色（深色下是深灰）中性底 + 一圈细边，圆角 24，内边距 16。不用色块底。
// - 层级靠字重和深浅：
//   · 第一行是问题本身（600 字重、正文色）：“Agent 想执行命令，要允许吗？”
//   · 第二行是唯一带颜色的地方：一个小圆点 + “普通 / 需留意 / 危险” + 一句原因（原因是灰的）。普通灰、需留意橙、危险红。
//   · 命令或路径放在等宽小块里（代码底色），最多露几行，多了自己滚。
// - 按钮一行最多两个：左“拒绝”（描边、中性），右“允许这一次”（实心强调色——整张卡唯一最突出的东西）。
//   “本对话都允许”是更次要的操作：另起一行，小号灰字，不抢主按钮。
// - 提问卡：同一个卡壳；选项一行一个（描边、左对齐），“其他回答”是灰色文字按钮。
// - 安全规则不在这里：哪些要确认、能不能“都允许”由传进来的请求决定，这里只管画。
import 'package:lopicode/agent/approval_risk.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 钉在输入卡片上方：最前面的一张确认卡，或一张提问卡。
class PendingArea extends StatelessWidget {
  const PendingArea({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context) {
    final approval = session.pendingApproval;
    if (approval != null) return ApprovalCard(pending: approval, onAnswer: session.resolveApproval);
    final question = session.pendingQuestion;
    if (question != null) return QuestionCard(key: ObjectKey(question), question: question, onAnswer: session.answerQuestion);
    return const SizedBox.shrink();
  }
}

/// 确认卡、提问卡共用的卡壳。
class ChatCard extends StatelessWidget {
  const ChatCard({super.key, required this.icon, required this.title, required this.children, this.maxHeight});
  final IconData icon;
  final String title;
  final List<Widget> children;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: c.textMuted),
            ),
            const SizedBox(width: Space.x2),
            Expanded(child: Text(title, style: t.titleSmall)),
          ],
        ),
        ...children,
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
      padding: const EdgeInsets.all(Space.x4),
      constraints: maxHeight == null ? null : BoxConstraints(maxHeight: maxHeight!),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: maxHeight == null ? body : SingleChildScrollView(child: body),
    );
  }
}

class ApprovalCard extends StatelessWidget {
  const ApprovalCard({super.key, required this.pending, required this.onAnswer});
  final PendingApproval pending;
  final void Function(bool allow, {bool always}) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final req = pending.request;
    final isSchedule = req.tool == 'schedule_task';
    final who = pending.agentName.isEmpty ? 'Agent' : '子代理“${pending.agentName}”';
    final icon = switch (req.tool) {
      'delete_file' => Icons.delete_outline,
      'schedule_task' => Icons.event_repeat,
      _ => Icons.terminal,
    };
    final risk = approvalRisk(req);
    final riskColor = switch (risk.level) {
      RiskLevel.normal => c.textFaint,
      RiskLevel.caution => c.warning,
      RiskLevel.danger => c.danger,
    };
    return ChatCard(
      icon: icon,
      title: isSchedule ? '$who 想${req.title}，请核对后再确认' : '$who 想${req.title}，要允许吗？',
      children: [
        const SizedBox(height: Space.x2),
        // 整张卡唯一带颜色的地方：危险程度。
        Row(
          key: ValueKey('risk-${risk.level.name}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 5, right: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: riskColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: risk.level.label,
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.w600),
                  children: [
                    TextSpan(
                      text: ' · ${risk.reason}',
                      style: TextStyle(color: c.textMuted, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
                style: t.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        Container(
          constraints: BoxConstraints(maxHeight: isSchedule ? 220 : 104),
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
          child: SingleChildScrollView(
            child: SelectableText(
              req.tool == 'run_command' ? '\$ ${req.detail}' : req.detail,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.5, color: c.text),
            ),
          ),
        ),
        const SizedBox(height: Space.x4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.border),
                ),
                onPressed: () => onAnswer(false),
                child: const Text('拒绝'),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: FilledButton(onPressed: () => onAnswer(true), child: Text(isSchedule ? '确认保存' : '允许这一次')),
            ),
          ],
        ),
        if (req.allowAlways)
          Padding(
            padding: const EdgeInsets.only(top: Space.x1),
            child: Center(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: c.textFaint, backgroundColor: Colors.transparent, textStyle: t.bodySmall, visualDensity: VisualDensity.compact),
                onPressed: () => onAnswer(true, always: true),
                child: const Text('本对话都允许'),
              ),
            ),
          ),
      ],
    );
  }
}

class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.question, required this.onAnswer});
  final PendingQuestion question;
  final void Function(String answer) onAnswer;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final _other = TextEditingController();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _typing = widget.question.options.isEmpty;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = widget.question;
    return ChatCard(
      icon: Icons.help_outline,
      title: q.agentName.isEmpty ? 'Agent 想问你' : '子代理“${q.agentName}”想问你',
      maxHeight: 380,
      children: [
        const SizedBox(height: Space.x2),
        Text(q.question, style: t.bodyLarge),
        const SizedBox(height: Space.x3),
        for (final o in q.options)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.border),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => widget.onAnswer(o),
              child: Text(o),
            ),
          ),
        if (!_typing)
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: c.textMuted, backgroundColor: Colors.transparent, textStyle: t.bodySmall, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _typing = true),
              child: const Text('其他回答'),
            ),
          )
        else ...[
          TextField(
            controller: _other,
            autofocus: q.options.isNotEmpty,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '写下你的回答'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.x2),
          FilledButton(onPressed: _other.text.trim().isEmpty ? null : () => widget.onAnswer(_other.text), child: const Text('回答')),
        ],
      ],
    );
  }
}
