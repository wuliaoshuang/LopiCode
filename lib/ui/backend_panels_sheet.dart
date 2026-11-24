// 设计约束（后端积木页的几个面板 · 390×844，浅色 + 深色）— 2026-11-24
// - 语言面板：一行一种语言（图标 + 名字在上，下面一行弱化的“用什么写的”）；没在本机真跑过的行尾标“未实测”；当前那种带勾。点一行＝选它并关掉。
// - 变量与集合面板：上下两段，各自一行一个（名字等宽在上，下面一行弱化的说明 + 几处在用），点一行＝改；每段末尾一个“新建…”。
//   集合只有名字：改名 / 删除都在同一个小对话框里，删除在左下角（弱化的危险色）。名字不合规矩就地说原因，不关对话框。
// - 服务设置：一个对话框两格（服务名、端口），端口不对就地说原因。
// - 没覆盖的文件：一行一个文件 + 为什么没动；主操作只有一个“用生成的覆盖”（危险色描边），旁边“先不动”。
import 'package:lopicode/backend/backend_edit.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

TextStyle _mono(BuildContext context, {double size = FontSize.base, FontWeight weight = FontWeight.w600}) =>
    TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: size, fontWeight: weight, color: context.colors.text);

/// 语言名（去掉生成器自己带的括号说明，那句话面板里另有位置放）。
String beLanguageName(BackendTarget t) => t.label.split('（').first;

/// 选语言。返回选中的语言 id；取消返回 null。
Future<String?> showBeLanguageSheet(BuildContext context, {required String current}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return LcSheetFrame(
      title: '用哪种语言',
      note: '积木不用改，换了语言会重新生成代码；上一种语言生成的文件会清掉（你手改过的不动）。',
      children: [
        for (final target in backendTargets)
          InkWell(
            key: ValueKey('be-lang-${target.id}'),
            onTap: () => Navigator.pop(context, target.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
              child: Row(
                children: [
                  FileIcon.language(target.id, size: 28),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(beLanguageName(target), style: t.titleSmall),
                            if (!target.verified) ...[
                              const SizedBox(width: Space.x2),
                              Container(
                                key: ValueKey('be-lang-unverified-${target.id}'),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(Radii.sm)),
                                child: Text('未实测', style: t.labelSmall?.copyWith(color: c.text)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(target.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  if (target.id == current) Icon(Icons.check_rounded, key: const ValueKey('be-lang-current'), size: 20, color: c.accent) else const SizedBox(width: 20),
                ],
              ),
            ),
          ),
      ],
    );
  },
);

/// 新建 / 改名一个集合（[editing] 不为 null＝改）。返回新名字；点了“删除”返回空字符串；取消返回 null。
Future<String?> showBeCollectionDialog(BuildContext context, {required Set<String> taken, String? editing, int refCount = 0}) => showDialog<String>(
  context: context,
  builder: (_) => _CollectionDialog(taken: taken, editing: editing, refCount: refCount),
);

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({required this.taken, this.editing, required this.refCount});
  final Set<String> taken;
  final String? editing;
  final int refCount;

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.editing ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    String? error;
    if (!beNamePattern.hasMatch(name)) {
      error = '只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符';
    } else if (name != widget.editing && widget.taken.contains(name)) {
      error = '已经有一个集合叫 $name 了';
    }
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final editing = widget.editing;
    return AlertDialog(
      scrollable: true,
      title: Text(editing == null ? '新建集合' : '集合 $editing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('be-col-name'),
            controller: _name,
            autofocus: editing == null,
            autocorrect: false,
            style: _mono(context, weight: FontWeight.w400),
            decoration: InputDecoration(labelText: '名字', hintText: '比如 todos', errorText: _error, errorMaxLines: 3),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.x3),
          Text(editing != null && widget.refCount > 0 ? '有 ${widget.refCount} 处在用它；改名会一起改过去。' : '集合里一条是一个对象，自动带数字 id（从 1 开始）。', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (editing != null)
          TextButton(
            key: const ValueKey('be-col-delete'),
            onPressed: () => Navigator.pop(context, ''),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('删除'),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: c.textMuted),
              child: const Text('取消'),
            ),
            TextButton(key: const ValueKey('be-col-save'), onPressed: _save, child: Text(editing == null ? '新建' : '保存')),
          ],
        ),
      ],
    );
  }
}

/// 变量与集合面板。[read] 每次都给最新的文档（撤销重做后会换对象）；[edit] 提交一次改动（一条撤销记录）。
class BeDataSheet extends StatefulWidget {
  const BeDataSheet({super.key, required this.read, required this.edit});
  final BeDocument Function() read;
  final void Function(void Function(BeDocument doc) change) edit;

  @override
  State<BeDataSheet> createState() => _BeDataSheetState();
}

class _BeDataSheetState extends State<BeDataSheet> {
  BeDocument get _doc => widget.read();

  Future<void> _newVariable() async {
    final draft = await showLcVariableDialog(context, taken: {for (final v in _doc.variables) v.name});
    if (draft == null || draft.delete || !mounted) return;
    widget.edit((d) => d.addVariable(draft.name, type: draft.type, initial: draft.initial));
    setState(() {});
  }

  Future<void> _editVariable(LcVariable v) async {
    final old = v.name;
    final refs = _doc.variableRefCount(old);
    final draft = await showLcVariableDialog(context, taken: {for (final x in _doc.variables) x.name}, editing: v, refCount: refs);
    if (draft == null || !mounted) return;
    if (draft.delete) {
      if (refs > 0) {
        final ok = await confirmDialog(context, title: '删除变量 $old？', message: '有 $refs 处在用它。删掉以后那些积木会被标出问题，要你一个个改。', confirmLabel: '删除', danger: true);
        if (!ok || !mounted) return;
      }
      widget.edit((d) => d.removeVariable(old));
    } else {
      if (draft.name == old && draft.type == v.type && draft.initial == v.initial) return;
      widget.edit((d) {
        if (!d.renameVariable(old, draft.name)) return;
        d.retypeVariable(draft.name, draft.type);
        d.setVariableInitial(draft.name, draft.initial);
      });
    }
    setState(() {});
  }

  Future<void> _newCollection() async {
    final name = await showBeCollectionDialog(context, taken: {for (final c in _doc.collections) c.name});
    if (name == null || name.isEmpty || !mounted) return;
    widget.edit((d) => d.addCollection(name));
    setState(() {});
  }

  Future<void> _editCollection(String old) async {
    final refs = _doc.collectionRefCount(old);
    final name = await showBeCollectionDialog(context, taken: {for (final c in _doc.collections) c.name}, editing: old, refCount: refs);
    if (name == null || !mounted || name == old) return;
    if (name.isEmpty) {
      if (refs > 0) {
        final ok = await confirmDialog(context, title: '删除集合 $old？', message: '有 $refs 处在用它。删掉以后那些积木会被标出问题，要你一个个改。', confirmLabel: '删除', danger: true);
        if (!ok || !mounted) return;
      }
      widget.edit((d) => d.removeCollection(old));
    } else {
      widget.edit((d) => d.renameCollection(old, name));
    }
    setState(() {});
  }

  Widget _row(String key, String name, String detail, VoidCallback onTap) {
    final c = context.colors;
    return InkWell(
      key: ValueKey(key),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _mono(context)),
                  const SizedBox(height: 2),
                  Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _add(String key, String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2),
      child: TextButton.icon(key: ValueKey(key), onPressed: onTap, icon: const Icon(Icons.add_rounded, size: 18), label: Text(label)),
    ),
  );

  String _used(int refs) => refs == 0 ? '还没用到' : '$refs 处在用';

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final c = context.colors;
    Widget empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted)),
    );
    return LcSheetFrame(
      title: '变量与集合',
      children: [
        const SectionLabel('集合 · 存数据的地方'),
        if (doc.collections.isEmpty) empty('还没有集合。'),
        for (final col in doc.collections) _row('be-col-row-${col.name}', col.name, '一条是一个对象，自动带 id · ${_used(doc.collectionRefCount(col.name))}', () => _editCollection(col.name)),
        _add('be-col-add', '新建集合', _newCollection),
        const SectionLabel('变量 · 每次请求开始时回到初始值'),
        if (doc.variables.isEmpty) empty('还没有变量。'),
        for (final v in doc.variables) _row('be-var-row-${v.name}', v.name, '${describeVarType(v.type)} · ${_used(doc.variableRefCount(v.name))}', () => _editVariable(v)),
        _add('be-var-add', '新建变量', _newVariable),
      ],
    );
  }
}

/// 服务设置（服务名、端口）。取消返回 null。
Future<({String name, int port})?> showBeSettingsDialog(BuildContext context, {required String name, required int port}) => showDialog<({String name, int port})>(
  context: context,
  builder: (_) => _SettingsDialog(name: name, port: port),
);

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.name, required this.port});
  final String name;
  final int port;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _port = TextEditingController(text: '${widget.port}');
  String? _nameError;
  String? _portError;

  @override
  void dispose() {
    _name.dispose();
    _port.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final port = int.tryParse(_port.text.trim());
    final nameError = name.isEmpty ? '起个名字' : (name.length > 60 ? '太长了（最多 60 个字）' : null);
    final portError = port == null || port < 1 || port > 65535 ? '端口要是 1 到 65535 之间的整数（手机上 1024 以下的一般用不了）' : null;
    if (nameError != null || portError != null) {
      return setState(() {
        _nameError = nameError;
        _portError = portError;
      });
    }
    Navigator.pop(context, (name: name, port: port!));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('服务设置'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('be-set-name'),
          controller: _name,
          decoration: InputDecoration(labelText: '服务名', errorText: _nameError),
        ),
        const SizedBox(height: Space.x4),
        TextField(
          key: const ValueKey('be-set-port'),
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '端口', hintText: '$kBeDefaultPort', errorText: _portError, errorMaxLines: 3),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
        child: const Text('取消'),
      ),
      TextButton(key: const ValueKey('be-set-save'), onPressed: _save, child: const Text('保存')),
    ],
  );
}

/// 生成情况：上次生成写了什么、哪些文件没覆盖（为什么）。返回 true＝用户选了“用生成的覆盖”。
Future<bool> showBeRegenSheet(BuildContext context, BackendRegenResult result) async {
  final picked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final c = context.colors;
      final t = Theme.of(context).textTheme;
      final conflicts = result.conflicts;
      final String note;
      if (!result.ok) {
        note = '没有生成：${result.error}';
      } else {
        final where = result.dir.isEmpty ? '项目根目录' : '${result.dir}/';
        final changed = '写了 ${result.written.length} 个文件，${result.unchanged.length} 个没有变化${result.removed.isEmpty ? '' : '，清掉 ${result.removed.length} 个旧文件'}';
        note = '按 ${result.languageLabel} 生成到$where：$changed。';
      }
      return LcSheetFrame(
        title: conflicts.isEmpty ? '代码生成情况' : '有 ${conflicts.length} 个文件没有覆盖',
        note: note,
        footer: conflicts.isEmpty
            ? null
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('先不动')),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('be-regen-overwrite'),
                      onPressed: () => Navigator.pop(context, true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.danger,
                        side: BorderSide(color: c.danger),
                      ),
                      child: const Text('用生成的覆盖'),
                    ),
                  ),
                ],
              ),
        children: [
          if (result.errorCount > 0)
            InfoBanner('${blockErrorsHeadline(result.errorCount)}（上一次生成的文件原样留着）。点顶栏的“问题”逐条看。', tone: BannerTone.warning, margin: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2)),
          if (conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2),
              child: Text('下面这些文件和积木生成的不一样，为了不冲掉你的修改，没有动：', style: t.bodySmall),
            ),
          for (final f in conflicts)
            Padding(
              key: ValueKey('be-regen-conflict-${f.path}'),
              padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.path, style: _mono(context, size: FontSize.sm)),
                  const SizedBox(height: 2),
                  Text(f.reason, style: t.bodySmall),
                ],
              ),
            ),
          if (conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
              child: Text('覆盖以后这些文件里你手改的内容就没有了。只覆盖内容不一样的文件；上一种语言留下、你改过的旧文件不会删。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
        ],
      );
    },
  );
  return picked ?? false;
}
