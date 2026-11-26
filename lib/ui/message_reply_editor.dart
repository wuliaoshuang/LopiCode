// 设计约束（编辑 Agent 的回复 · 整页 · 390×844）
// 层级：正在改的文字最重（占满中间，能滚，16 号字）；下面一句小字说清“改了会怎样”；最下面一排是唯二的按钮。
// - 顶栏：左边返回（＝取消）、标题“编辑回复”。没有别的操作。
// - 中间：一个多行输入框占满剩下的高度；键盘弹起时页面跟着缩，输入框和下面的按钮都不会被键盘挡住。
//   不自动弹键盘：回复常常很长，先让她滚到要改的地方再点。
// - 输入框下面一句小字（一次只说一件事）：平时说“只改文字、不重新回答”；这条已被压缩时说摘要不跟着变；
//   内容是空的 / 没存成时换成红色的原因。
// - 改过的回复多一行“恢复原文”（弱按钮，靠左）：把模型的原话放回输入框，还要点“保存”才算数。
// - 最下面一排：取消（弱）、保存（实心，唯一主操作）。内容是空的、和现在一样、正在存的时候“保存”是灰的。
// - 改了没存就要走：先问一句“放弃修改？”。
// - 这一轮有几段正文时（中间夹着工具步骤），先出一个底部面板选改哪一段：一行一段，写“第 N 段”和开头两行字，改过的标“已编辑”。
//   （2026-11-26 自定：比“一页里按段分开好几个输入框”稳——每段各存各的，长回复也不会几个输入框抢滚动。）
// - 只改这段正文；工具步骤、思考内容不在这里，也不能改。规矩见 lib/session/reply_edit.dart。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/reply_edit.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// ── 登记用的小函数 ─────────────────────────────────────
String? editReplyHint(MessageTarget t) => '直接改这段文字，不会让 Agent 重新回答';
String? editReplyBlocked(MessageTarget t) => t.busy ? kEditReplyWhileBusy : null;

/// 点了 Agent 回复下面的“编辑”：打开整页编辑器，存好以后说一声。
Future<void> runEditReply(BuildContext context, MessageTarget t) async {
  var id = t.id;
  if (t.parts.length > 1) {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReplyPartSheet(parts: t.parts),
    );
    if (picked == null || !context.mounted) return;
    id = picked;
  }
  final info = t.session.messageOps.replyEditInfo(id);
  if (info == null) return showSnack(context, '这段回复已经不在记录里了。');
  final messenger = ScaffoldMessenger.of(context);
  final done = await Navigator.of(context).push<ReplyEditOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReplyEditorScreen(session: t.session, messageId: id, info: info),
    ),
  );
  if (done == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(done.edited ? '已保存修改。这段回复标上了“已编辑”，Agent 之后看到的是改后的内容。' : '已恢复成原文，“已编辑”的记号去掉了。')));
}

/// 这一轮有几段正文：选改哪一段。选中那段的 id 作为返回值。
class ReplyPartSheet extends StatelessWidget {
  const ReplyPartSheet({super.key, required this.parts});
  final List<ReplyPart> parts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x1),
              child: Text('改哪一段？', style: t.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2),
              child: Text('这一轮 Agent 说了 ${parts.length} 段话，中间隔着它做的步骤。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, p) in parts.indexed)
                    ListTile(
                      key: ValueKey('reply-part-${p.id}'),
                      title: Text(p.edited ? '第 ${i + 1} 段 · 已编辑' : '第 ${i + 1} 段', style: t.labelMedium?.copyWith(color: c.textMuted)),
                      subtitle: Text(
                        p.text.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(color: c.text),
                      ),
                      trailing: Icon(Icons.chevron_right, color: c.textFaint),
                      onTap: () => Navigator.pop(context, p.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReplyEditorScreen extends StatefulWidget {
  const ReplyEditorScreen({super.key, required this.session, required this.messageId, required this.info});
  final ProjectSession session;
  final String messageId;
  final ReplyEditInfo info;

  @override
  State<ReplyEditorScreen> createState() => _ReplyEditorScreenState();
}

class _ReplyEditorScreenState extends State<ReplyEditorScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.info.text);
  bool _saving = false;
  String? _error;

  ReplyEditInfo get _info => widget.info;
  bool get _dirty => _text.text != _info.text;
  bool get _empty => _text.text.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _error = null);

  Future<void> _leave() async {
    if (_saving) return;
    if (_dirty && !await confirmDialog(context, title: '放弃修改？', message: '改过的内容还没保存。点“取消”可以回去接着改。', confirmLabel: '放弃')) return;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || _empty || !_dirty) return;
    setState(() => _saving = true);
    final done = await widget.session.messageOps.editReply(widget.messageId, _text.text);
    if (!mounted) return;
    if (done.error != null) {
      setState(() {
        _saving = false;
        _error = done.error;
      });
      return;
    }
    Navigator.pop(context, done);
  }

  void _restore() {
    final original = _info.original;
    if (original == null) return;
    _text.value = TextEditingValue(
      text: original,
      selection: TextSelection.collapsed(offset: original.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final problem = _error ?? (_empty ? kReplyEditEmpty : null);
    final note = problem ?? (_info.archived ? '这段已经被压缩进摘要里：这里会显示改后的文字，但 Agent 看到的那份摘要不会跟着变。' : '只改这段文字，不会让 Agent 重新回答。之后它看到的是改后的内容。');
    final original = _info.original;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PageBar(
          titleText: '编辑回复',
          leading: RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: '取消', onPressed: _leave),
        ),
        body: BelowBar(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('reply-edit-input'),
                      controller: _text,
                      enabled: !_saving,
                      expands: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      style: t.bodyLarge,
                      decoration: const InputDecoration(hintText: '这段回复的文字'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x2),
                    child: Text(
                      note,
                      key: const ValueKey('reply-edit-note'),
                      style: t.bodySmall?.copyWith(color: problem == null ? c.textMuted : c.danger, height: 1.45),
                    ),
                  ),
                  if (original != null && _text.text != original)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('reply-edit-restore'),
                        onPressed: _saving ? null : _restore,
                        style: TextButton.styleFrom(
                          foregroundColor: c.textMuted,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                        ),
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('恢复原文'),
                      ),
                    ),
                  const SizedBox(height: Space.x2),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const ValueKey('reply-edit-cancel'),
                          onPressed: _saving ? null : _leave,
                          style: TextButton.styleFrom(foregroundColor: c.textMuted, minimumSize: const Size.fromHeight(48)),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('reply-edit-save'),
                          onPressed: _saving || _empty || !_dirty ? null : _save,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          child: Text(_saving ? '正在保存…' : '保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
