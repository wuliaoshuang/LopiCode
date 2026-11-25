// 设计约束（一次问几个问题的提问卡 · 390×844）
// - 一页一问。理由：390 宽、输入框上方能给卡片的高度约 380，一个问题连同 4 个选项和“自己写”就要 300 左右，
//   几个问题摊在一页必然要在卡片里滚，她看不到后面还有几个、也容易漏答；一页一问每次只需要做一个决定。
// - 从上到下：标题行（Agent 想问你）→ 进度（第 2 / 3 个 + 单选 / 可多选）→ 问题 → 选项（一行一个）→“自己写”输入框 → 一行两个按钮。
// - 问题很长或选项多（最多 6 个）时，只有“问题 + 选项”那一块在卡片里上下滑；进度、“自己写”和底部按钮一直看得见。
// - 选项点了只是选中（描边变强调色 + 左边的勾），不会自己翻页；单选再点别的就换，多选可以勾几个。
// - 底部按钮：左“上一个”（描边；第一页没有），右“下一个 / 提交”（实心，唯一的主操作）。这一页没答就点不了。
// - “自己写”每页都有：单选时写了字就以写的为准（选中的会取消）；多选时是额外补充。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/ask_user.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_cards.dart';
import 'package:material_ui/material_ui.dart';

/// 问题 + 选项这一块最高多少：大约放得下一个两行的问题和 4 个选项，再多就在块里滑。
const double _kScrollMax = 264;

class MultiQuestionCard extends StatefulWidget {
  const MultiQuestionCard({super.key, required this.question, required this.onAnswer});
  final PendingQuestion question;
  final void Function(String answer) onAnswer;

  @override
  State<MultiQuestionCard> createState() => _MultiQuestionCardState();
}

class _MultiQuestionCardState extends State<MultiQuestionCard> {
  late final List<QuestionPart> _parts = widget.question.parts;
  late final List<Set<String>> _picked = [for (final _ in _parts) <String>{}];
  late final List<TextEditingController> _written = [for (final _ in _parts) TextEditingController()];
  int _page = 0;

  @override
  void dispose() {
    for (final c in _written) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _answered => _picked[_page].isNotEmpty || _written[_page].text.trim().isNotEmpty;
  bool get _last => _page == _parts.length - 1;

  void _pick(String option) => setState(() {
    final set = _picked[_page];
    if (_parts[_page].multiple) {
      if (!set.remove(option)) set.add(option);
    } else {
      set
        ..clear()
        ..add(option);
      _written[_page].clear();
    }
  });

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_last) return setState(() => _page++);
    widget.onAnswer(formatAnswers(_parts, [for (var i = 0; i < _parts.length; i++) (picked: _picked[i].toList(), written: _written[i].text)]));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final q = widget.question;
    final part = _parts[_page];
    final neutral = OutlinedButton.styleFrom(
      foregroundColor: c.text,
      side: BorderSide(color: c.border),
    );
    return ChatCard(
      icon: Icons.help_outline,
      title: q.agentName.isEmpty ? 'Agent 想问你' : '子代理“${q.agentName}”想问你',
      children: [
        const SizedBox(height: Space.x1),
        Text(
          '${_parts.length > 1 ? '第 ${_page + 1} / ${_parts.length} 个 · ' : ''}${part.multiple ? '可以选多个' : '选一个'}',
          key: const Key('ask-progress'),
          style: t.bodySmall?.copyWith(color: c.textFaint),
        ),
        const SizedBox(height: Space.x2),
        // 问题和选项多了在这一块里上下滑；下面的输入框和按钮一直看得见。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _kScrollMax),
          child: SingleChildScrollView(
            key: const Key('ask-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(part.question, style: t.bodyLarge),
                const SizedBox(height: Space.x3),
                for (final o in part.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: OutlinedButton(
                      key: ValueKey('ask-option-$o'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.text,
                        side: BorderSide(color: _picked[_page].contains(o) ? c.accent : c.border, width: _picked[_page].contains(o) ? 1.5 : 1),
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => _pick(o),
                      child: Row(
                        children: [
                          Icon(
                            _picked[_page].contains(o)
                                ? (part.multiple ? Icons.check_box : Icons.radio_button_checked)
                                : (part.multiple ? Icons.check_box_outline_blank : Icons.radio_button_unchecked),
                            size: 18,
                            color: _picked[_page].contains(o) ? c.accent : c.textFaint,
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(child: Text(o)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x1),
        TextField(
          key: ValueKey('ask-written-$_page'),
          controller: _written[_page],
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(hintText: part.options.isEmpty ? '写下你的回答' : (part.multiple ? '还有别的？自己写（可以不填）' : '都不合适？自己写')),
          onChanged: (v) => setState(() {
            if (!part.multiple && v.trim().isNotEmpty) _picked[_page].clear();
          }),
        ),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            if (_page > 0) ...[
              Expanded(
                child: OutlinedButton(key: const Key('ask-prev'), style: neutral, onPressed: () => setState(() => _page--), child: const Text('上一个')),
              ),
              const SizedBox(width: Space.x2),
            ],
            Expanded(
              child: FilledButton(key: const Key('ask-next'), onPressed: _answered ? _next : null, child: Text(_last ? '提交' : '下一个')),
            ),
          ],
        ),
      ],
    );
  }
}
