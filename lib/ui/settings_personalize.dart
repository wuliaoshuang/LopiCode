// 设计约束（个性化 / 预设编辑 · 390×844）— 2026-11-24 从 settings_agent.dart 拆出来并按设置的统一样式重排
// - 个性化两组：〔个人偏好〕一个多行输入框 + 保存（表单组），用途写在组的脚注里；
//   〔Agent 预设〕一行一个预设（名字，副标题是“内置 / 几个工具”，新对话默认的那个右边写“默认”）；
//     复制 / 设为默认 / 删除收进行尾菜单，点行进编辑页；最后一行是“新建预设”。
// - 预设编辑页：〔基本〕名称 → 系统提示词（表单组）；〔可用工具〕一行一个工具勾选；最底下一个实心“保存”。
//   内置“标准模式”只能看不能改，页面顶上一条说明。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/state/presets_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class PersonalizeScreen extends ConsumerStatefulWidget {
  const PersonalizeScreen({super.key});

  @override
  ConsumerState<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends ConsumerState<PersonalizeScreen> {
  final _prefs = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _prefs.text = ref.read(presetsProvider).preferences;
    }
  }

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _savePrefs() async {
    await ref.read(presetsProvider.notifier).setPreferences(_prefs.text);
    if (mounted) {
      FocusScope.of(context).unfocus();
      showSnack(context, _prefs.text.trim().isEmpty ? '已清空：不再带个人偏好' : '已保存：之后的对话都会带上');
    }
  }

  Future<void> _edit([AgentPreset? preset]) async {
    await pushSettingsPage<void>(context, PresetEditScreen(preset: preset));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetsProvider);
    final edit = ref.read(presetsProvider.notifier);
    final c = context.colors;
    final defaultId = presets.defaultId;
    return SettingsPage(
      title: '个性化',
      children: [
        SettingsGroup(
          title: '个人偏好',
          footer: '写给 Agent 的长期习惯，所有工作区、所有对话都会带上。清空再保存就是删掉。',
          padded: true,
          children: [
            TextField(
              key: const Key('prefs-field'),
              controller: _prefs,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: '比如：用简体中文回答；先说结论；改完告诉我改了哪些文件。'),
            ),
            const SizedBox(height: Space.x3),
            FilledButton(key: const Key('prefs-save'), onPressed: _savePrefs, child: const Text('保存偏好')),
          ],
        ),
        SettingsGroup(
          title: 'Agent 预设',
          footer: '预设＝一套系统提示词加上允许用的工具。新对话用“默认”那个，对话里可以在右上角的菜单里换。',
          children: [
            for (final p in presets.all)
              SettingsRow(
                title: p.name,
                subtitle: '${p.builtIn ? '内置 · ' : ''}${p.tools == null ? '全部工具' : '${p.tools!.length} 个工具'}',
                value: p.id == defaultId ? '默认' : null,
                trailing: PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: Icon(Icons.more_vert, color: c.textFaint),
                  onSelected: (v) async {
                    if (v == 'default') await edit.setDefault(p.id);
                    if (v == 'copy') await edit.copy(p);
                    if (v == 'delete' && context.mounted) {
                      final ok = await confirmDialog(context, title: '删除预设“${p.name}”？', message: '用着它的对话会改回“标准模式”。', confirmLabel: '删除', danger: true);
                      if (ok) await edit.delete(p.id);
                    }
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (_) => [
                    if (p.id != defaultId) const PopupMenuItem(value: 'default', child: Text('设为新对话默认')),
                    const PopupMenuItem(value: 'copy', child: Text('复制一份')),
                    if (!p.builtIn)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('删除', style: TextStyle(color: c.danger)),
                      ),
                  ],
                ),
                onTap: () => _edit(p),
              ),
            SettingsRow(key: const Key('preset-new'), icon: Icons.add, title: '新建预设', accent: true, onTap: _edit),
          ],
        ),
      ],
    );
  }
}

class PresetEditScreen extends ConsumerStatefulWidget {
  const PresetEditScreen({super.key, this.preset});
  final AgentPreset? preset;

  @override
  ConsumerState<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends ConsumerState<PresetEditScreen> {
  late final _name = TextEditingController(text: widget.preset?.name ?? '');
  late final _prompt = TextEditingController(text: widget.preset?.prompt ?? '');
  late final Set<String> _tools = {...(widget.preset?.tools ?? kToolLabels.keys)};

  bool get _readOnly => widget.preset?.builtIn ?? false;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final all = _tools.length == kToolLabels.length;
    await ref.read(presetsProvider.notifier).upsert(id: widget.preset?.id, name: _name.text, prompt: _prompt.text, tools: all ? null : {..._tools});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: widget.preset == null ? '新建预设' : (_readOnly ? '标准模式' : '编辑预设'),
      children: [
        if (_readOnly) const InfoBanner('内置的“标准模式”带全部工具，不能改。想改就回上一页“复制一份”再改。', margin: EdgeInsets.only(bottom: Space.x6)),
        SettingsGroup(
          title: '基本',
          padded: true,
          children: [
            TextField(
              key: const Key('preset-name'),
              controller: _name,
              enabled: !_readOnly,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              key: const Key('preset-prompt'),
              controller: _prompt,
              enabled: !_readOnly,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '系统提示词', hintText: '这个预设下 Agent 要怎么做事。可以留空。', alignLabelWithHint: true),
            ),
          ],
        ),
        SettingsGroup(
          title: '可用工具（${_tools.length} / ${kToolLabels.length}）',
          footer: '没勾的工具 Agent 看不到，硬调用也会被拒绝。有些工具还要先在设置里开通（联网搜索、团队、技能）。',
          children: [
            for (final e in kToolLabels.entries)
              SettingsCheckRow(
                key: Key('tool-${e.key}'),
                title: e.value,
                subtitle: e.key,
                checked: _tools.contains(e.key),
                onChanged: _readOnly ? null : (v) => setState(() => v ? _tools.add(e.key) : _tools.remove(e.key)),
              ),
          ],
        ),
        if (!_readOnly) FilledButton(key: const Key('preset-save'), onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
