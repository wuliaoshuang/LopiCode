// 设计约束（个性化 / 子代理与团队 / 联网搜索 / 技能 · 390×844）
// - 每个页面只管一件事；页面里每行只做一件事，开关在右，说明在标题下面一行小字。
// - 预设列表：一行一个预设；复制 / 设为默认 / 删除收进行尾菜单，点行进编辑页。
// - 预设编辑页：名称 → 系统提示词 → 工具勾选（一行一个工具）→ 保存。内置“标准模式”只能看不能改。
// - 技能页：分“这个工作区”和“全局”两段，一行一个技能，右边是开关；点行看全文，删除在全文页的菜单里。
// - Key 输入框默认遮住，已保存的不回显。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// ── 个性化 ───────────────────────────────────────────
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
      _prefs.text = appOf(context).presets.preferences;
    }
  }

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  Future<void> _savePrefs() async {
    final app = appOf(context);
    await app.presets.setPreferences(_prefs.text);
    if (mounted) {
      FocusScope.of(context).unfocus();
      showSnack(context, _prefs.text.trim().isEmpty ? '已清空：不再带个人偏好' : '已保存：之后的对话都会带上');
    }
  }

  Future<void> _edit([AgentPreset? preset]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PresetEditScreen(preset: preset)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(presetsRevProvider);
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final defaultId = app.presets.defaultId;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: const Text('个性化')),
      body: SectionedList(
        children: [
          const SectionLabel('个人偏好'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('写给 Agent 的长期习惯，所有工作区、所有对话都会带上。清空再保存就是删掉。', style: t.bodySmall),
                const SizedBox(height: Space.x3),
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
          ),
          const SectionLabel('Agent 预设'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('预设＝一套系统提示词加上允许用的工具。新对话用“默认”那个，对话里可以在右上角的菜单里换。', style: t.bodySmall),
          ),
          for (final p in app.presets.all)
            ListTile(
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${p.id == defaultId ? '新对话默认 · ' : ''}${p.builtIn ? '内置 · ' : ''}${p.tools == null ? '全部工具' : '${p.tools!.length} 个工具'}',
                style: t.bodySmall?.copyWith(color: p.id == defaultId ? c.accent : null),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_vert, color: c.textFaint),
                onSelected: (v) async {
                  if (v == 'default') await app.presets.setDefault(p.id);
                  if (v == 'copy') await app.presets.copy(p);
                  if (v == 'delete' && context.mounted) {
                    final ok = await confirmDialog(context, title: '删除预设“${p.name}”？', message: '用着它的对话会改回“标准模式”。', confirmLabel: '删除', danger: true);
                    if (ok) await app.presets.delete(p.id);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
            child: OutlinedButton.icon(key: const Key('preset-new'), onPressed: _edit, icon: const Icon(Icons.add, size: 18), label: const Text('新建预设')),
          ),
        ],
      ),
    );
  }
}

class PresetEditScreen extends StatefulWidget {
  const PresetEditScreen({super.key, this.preset});
  final AgentPreset? preset;

  @override
  State<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends State<PresetEditScreen> {
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
    final app = appOf(context);
    final all = _tools.length == kToolLabels.length;
    await app.presets.upsert(id: widget.preset?.id, name: _name.text, prompt: _prompt.text, tools: all ? null : {..._tools});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: Text(widget.preset == null ? '新建预设' : (_readOnly ? '标准模式' : '编辑预设'))),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          if (_readOnly) const InfoBanner('内置的“标准模式”带全部工具，不能改。想改就回上一页“复制一份”再改。', margin: EdgeInsets.only(bottom: Space.x3)),
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
          const SizedBox(height: Space.x6),
          Text('可用工具（${_tools.length} / ${kToolLabels.length}）', style: t.labelMedium),
          const SizedBox(height: Space.x1),
          Text('没勾的工具 Agent 看不到，硬调用也会被拒绝。有些工具还要先在设置里开通（联网搜索、团队、技能）。', style: t.bodySmall),
          for (final e in kToolLabels.entries)
            CheckboxListTile(
              key: Key('tool-${e.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _tools.contains(e.key),
              title: Text(e.value),
              subtitle: Text(e.key, style: t.bodySmall),
              onChanged: _readOnly ? null : (v) => setState(() => v == true ? _tools.add(e.key) : _tools.remove(e.key)),
            ),
          const SizedBox(height: Space.x4),
          if (!_readOnly) FilledButton(key: const Key('preset-save'), onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

// ── 子代理与团队 ─────────────────────────────────────
class SubagentSettingsScreen extends ConsumerStatefulWidget {
  const SubagentSettingsScreen({super.key});

  @override
  ConsumerState<SubagentSettingsScreen> createState() => _SubagentSettingsScreenState();
}

class _SubagentSettingsScreenState extends ConsumerState<SubagentSettingsScreen> {
  Future<void> _set(String key, Object? value) async {
    final app = appOf(context);
    await app.settings.set(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(agentSettingsRevProvider)
      ..watch(modelsRevProvider);
    final app = appOf(context);
    final t = Theme.of(context).textTheme;
    final on = app.settings.getBool(SettingKeys.subagentEnabled, true);
    final depth = (app.settings.get<int>(SettingKeys.subagentMaxDepth) ?? 1).clamp(0, 3);
    final conc = (app.settings.get<int>(SettingKeys.subagentMaxConcurrent) ?? 2).clamp(1, 4);
    final allowed = {
      for (final m in app.settings.get<List<dynamic>>(SettingKeys.subagentAllowedModels) ?? const [])
        if (m is String) m,
    };
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: const Text('子代理与团队')),
      body: SectionedList(
        children: [
          const SectionLabel('子代理'),
          SwitchListTile(
            key: const Key('subagent-enabled'),
            title: const Text('允许派出子代理'),
            subtitle: const Text('Agent 可以把一件事交给另一个独立的 Agent 去做，做完把结果交回来'),
            value: on,
            onChanged: (v) => _set(SettingKeys.subagentEnabled, v),
          ),
          if (on) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x2),
              child: Text('最多委派几层', style: t.bodyMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: SegmentedButton<int>(
                key: const Key('subagent-depth'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1 层')),
                  ButtonSegment(value: 2, label: Text('2 层')),
                  ButtonSegment(value: 3, label: Text('3 层')),
                ],
                selected: {depth.clamp(1, 3)},
                onSelectionChanged: (v) => _set(SettingKeys.subagentMaxDepth, v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, 0),
              child: Text('1 层＝只有主智能体能派；2 层＝子代理还能再派一层。层数越多越费钱。', style: t.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x2),
              child: Text('最多同时跑几个', style: t.bodyMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: SegmentedButton<int>(
                key: const Key('subagent-concurrent'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {conc},
                onSelectionChanged: (v) => _set(SettingKeys.subagentMaxConcurrent, v.first),
              ),
            ),
            const SectionLabel('子代理可以换用的模型'),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('默认和上级用同一个模型。勾上的模型，Agent 派子代理时可以指定改用（比如便宜的小模型）。', style: t.bodySmall),
            ),
            if (app.models.channels.every((ch) => ch.models.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
                child: Text('还没有模型。先到“模型与渠道”添加。', style: t.bodySmall),
              ),
            for (final ch in app.models.channels)
              for (final m in ch.models)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: allowed.contains('${ch.id}/${m.id}'),
                  title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(ch.name, style: t.bodySmall),
                  onChanged: (v) {
                    final next = {...allowed};
                    v == true ? next.add('${ch.id}/${m.id}') : next.remove('${ch.id}/${m.id}');
                    _set(SettingKeys.subagentAllowedModels, next.toList()..sort());
                  },
                ),
          ],
          const SectionLabel('智能体团队'),
          SwitchListTile(
            key: const Key('team-enabled'),
            title: const Text('开启智能体团队'),
            subtitle: const Text('主智能体和子代理共用一块任务板：谁负责什么、先后顺序、各自能改哪些文件'),
            value: app.settings.getBool(SettingKeys.teamEnabled),
            onChanged: (v) => _set(SettingKeys.teamEnabled, v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, 0),
            child: Text('默认关闭。开启后在对话页右上角的菜单里能看到“智能体团队”。团队会明显多花钱，适合大任务。', style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ── 联网搜索 ─────────────────────────────────────────
class WebSearchSettingsScreen extends StatefulWidget {
  const WebSearchSettingsScreen({super.key});

  @override
  State<WebSearchSettingsScreen> createState() => _WebSearchSettingsScreenState();
}

class _WebSearchSettingsScreenState extends State<WebSearchSettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _hasKey = false;
  bool _loaded = false;
  bool _busy = false;
  String? _status;
  bool _statusOk = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = appOf(context);
    _url.text = app.settings.getString(WebSearchConfig.kUrl);
    app.secrets.read(WebSearchConfig.secretKey).then((v) {
      if (mounted) setState(() => _hasKey = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = appOf(context);
    await app.settings.set(WebSearchConfig.kUrl, _url.text.trim().isEmpty ? null : _url.text.trim());
    if (_key.text.trim().isNotEmpty) {
      await app.secrets.write(WebSearchConfig.secretKey, _key.text.trim());
      _key.clear();
      _hasKey = true;
    }
    app.container.read(webSearchRevProvider.notifier).bump();
    if (mounted) {
      setState(() {});
      FocusScope.of(context).unfocus();
      showSnack(context, _url.text.trim().isNotEmpty && _hasKey ? '已保存：Agent 现在有联网搜索工具了' : '已保存。地址和 Key 都填好，Agent 才有搜索工具');
    }
  }

  Future<void> _clear() async {
    final app = appOf(context);
    await app.secrets.delete(WebSearchConfig.secretKey);
    app.container.read(webSearchRevProvider.notifier).bump();
    if (mounted) setState(() => _hasKey = false);
  }

  Future<void> _test() async {
    final app = appOf(context);
    final ok = await confirmDialog(context, title: '搜一次试试？', message: '会真的向搜索服务发一次搜索（关键词“LopiCode”），按服务商的规则可能消耗一次额度。', confirmLabel: '搜一次');
    if (!ok) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final key = _key.text.trim().isNotEmpty ? _key.text.trim() : (await app.secrets.read(WebSearchConfig.secretKey) ?? '');
    final outcome = await WebSearchClient(WebSearchConfig(_url.text.trim(), key)).search('LopiCode', count: 1);
    if (mounted) {
      setState(() {
        _busy = false;
        _statusOk = outcome.ok;
        _status = outcome.ok ? '搜索服务可以用。' : outcome.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: const Text('联网搜索')),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          Text('填好之后，Agent 多一个“联网搜索”工具，需要查资料时会自己用。没填的时候 Agent 没有这个工具。', style: t.bodySmall),
          const SizedBox(height: Space.x3),
          const InfoBanner('目前按 Tavily 搜索服务的接口格式对接。Key 要你自己去它的官网申请，费用和免费额度以它官网为准；LopiCode 不会替你注册或付费。'),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('search-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '搜索服务地址', hintText: WebSearchConfig.defaultUrl),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _url.text = WebSearchConfig.defaultUrl), child: const Text('填入 Tavily 的官方地址')),
          ),
          TextField(
            key: const Key('search-key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: _hasKey ? '已保存，留空表示不改' : '粘贴你的 Key',
              helperText: _hasKey ? '已保存一个 Key（不显示明文）' : null,
              suffixIcon: _hasKey ? IconButton(tooltip: '清除已保存的 Key', icon: const Icon(Icons.delete_outline), onPressed: _clear) : null,
            ),
          ),
          const SizedBox(height: Space.x4),
          FilledButton(key: const Key('search-save'), onPressed: _save, child: const Text('保存')),
          const SizedBox(height: Space.x2),
          OutlinedButton(onPressed: _busy || _url.text.trim().isEmpty ? null : _test, child: const Text('搜一次试试')),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: Space.x2),
              child: LinearProgressIndicator(),
            ),
          if (_status != null)
            InfoBanner(
              _status!,
              tone: _statusOk ? BannerTone.info : BannerTone.danger,
              margin: const EdgeInsets.only(top: Space.x2),
            ),
        ],
      ),
    );
  }
}

// ── 技能 ─────────────────────────────────────────────
class SkillsScreen extends ConsumerStatefulWidget {
  const SkillsScreen({super.key, this.workspace});
  final Project? workspace;

  @override
  ConsumerState<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends ConsumerState<SkillsScreen> {
  List<Skill>? _skills;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skills == null) _reload();
  }

  Future<void> _reload() async {
    final list = await appOf(context).skills.list(workspaceDir: widget.workspace?.dir);
    if (mounted) setState(() => _skills = list);
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SkillEditScreen(workspace: widget.workspace)));
    if (created == true) await _reload();
  }

  Future<void> _open(Skill skill) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SkillViewScreen(skill: skill)));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(skillsRevProvider);
    final app = appOf(context);
    final t = Theme.of(context).textTheme;
    final skills = _skills;
    final ws = skills?.where((s) => !s.global).toList() ?? const <Skill>[];
    final global = skills?.where((s) => s.global).toList() ?? const <Skill>[];
    Widget row(Skill s) => SwitchListTile(
      key: Key('skill-${s.key}'),
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(s.description.isEmpty ? '（没有写描述）' : s.description, maxLines: 2, overflow: TextOverflow.ellipsis),
      value: s.enabled,
      secondary: IconButton(tooltip: '查看全文', icon: const Icon(Icons.article_outlined), onPressed: () => _open(s)),
      onChanged: (v) async {
        await app.skills.setEnabled(s, v);
        await _reload();
      },
    );
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: const Text('技能')),
      floatingActionButton: skills == null || skills.isEmpty
          ? null
          : FloatingActionButton.extended(onPressed: _create, elevation: 2, shape: const StadiumBorder(), icon: const Icon(Icons.add), label: const Text('新建技能')),
      body: skills == null
          ? const Center(child: CircularProgressIndicator())
          : skills.isEmpty
          ? EmptyState(
              icon: Icons.menu_book_outlined,
              title: '还没有技能',
              message: '技能是一份写给 Agent 的做事说明书（SKILL.md）。\nAgent 平时只看到名字和描述，用得上时再读全文。',
              action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('新建技能')),
            )
          : SectionedList(
              bottom: 96,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
                  child: Text('开着的技能，名字和描述会告诉 Agent；它用得上时自己读全文。同名时工作区的优先。', style: t.bodySmall),
                ),
                if (widget.workspace != null) ...[
                  SectionLabel('工作区“${widget.workspace!.name}”的技能'),
                  if (ws.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                      child: Text('这个工作区还没有自己的技能（放在工作区的 .lopicode/skills/ 里）。', style: t.bodySmall),
                    ),
                  for (final s in ws) row(s),
                ],
                const SectionLabel('全局技能（所有工作区都能用）'),
                if (global.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                    child: Text('还没有全局技能。', style: t.bodySmall),
                  ),
                for (final s in global) row(s),
              ],
            ),
    );
  }
}

class SkillEditScreen extends StatefulWidget {
  const SkillEditScreen({super.key, this.workspace});
  final Project? workspace;

  @override
  State<SkillEditScreen> createState() => _SkillEditScreenState();
}

class _SkillEditScreenState extends State<SkillEditScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _body = TextEditingController();
  late bool _global = widget.workspace == null;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = appOf(context);
    try {
      await app.skills.create(name: _name.text, description: _desc.text, body: _body.text, workspaceDir: _global ? null : widget.workspace!.dir);
      if (mounted) Navigator.pop(context, true);
    } on SkillException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Exception catch (e) {
      if (mounted) showSnack(context, '没建成：$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.canvas,
    appBar: PageBar(background: context.colors.canvas, title: const Text('新建技能')),
    body: SectionedList(
      inner: const EdgeInsets.all(Space.x4),
      children: [
        TextField(
          key: const Key('skill-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: '技能名', hintText: '短一点，不带空格，如 写周报'),
        ),
        const SizedBox(height: Space.x3),
        TextField(
          key: const Key('skill-desc'),
          controller: _desc,
          maxLines: 2,
          decoration: const InputDecoration(labelText: '一句话描述', hintText: '什么时候该用它。Agent 靠这句话决定要不要读全文'),
        ),
        const SizedBox(height: Space.x3),
        TextField(
          key: const Key('skill-body'),
          controller: _body,
          minLines: 6,
          maxLines: 14,
          decoration: const InputDecoration(labelText: '正文', hintText: '一步步写清楚该怎么做', alignLabelWithHint: true),
        ),
        if (widget.workspace != null) ...[
          const SizedBox(height: Space.x3),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('只给这个工作区')),
              ButtonSegment(value: true, label: Text('全局')),
            ],
            selected: {_global},
            onSelectionChanged: (v) => setState(() => _global = v.first),
          ),
        ],
        const SizedBox(height: Space.x4),
        FilledButton(key: const Key('skill-save'), onPressed: _save, child: const Text('创建')),
      ],
    ),
  );
}

class SkillViewScreen extends StatelessWidget {
  const SkillViewScreen({super.key, required this.skill});
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(
        background: context.colors.canvas,
        title: Text(skill.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) async {
              final ok = await confirmDialog(context, title: '删除技能“${skill.name}”？', message: '这个技能的文件夹会被整个删除，无法恢复。', confirmLabel: '删除', danger: true);
              if (!ok || !context.mounted) return;
              try {
                await app.skills.delete(skill);
                if (context.mounted) Navigator.pop(context);
              } on Exception catch (e) {
                if (context.mounted) showSnack(context, '$e');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除技能', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: app.skills.readFull(skill),
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [
            Text(skill.global ? '全局技能' : '工作区技能', style: t.bodySmall),
            const SizedBox(height: Space.x1),
            Text('要改内容，直接编辑这个技能文件夹里的 SKILL.md。', style: t.bodySmall),
            const SizedBox(height: Space.x3),
            Container(
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: c.codeBg,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.border),
              ),
              child: SelectableText(
                snap.hasError ? '读不出来：${snap.error}' : (snap.data ?? '读取中…'),
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.6, color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具的中文名（对话页的权限说明等处用）。
String toolLabel(String name) => kToolLabels[name] ?? name;

/// 权限档位的一句话（设置页用）。
String permissionLabel(String id) => PermissionLevel.byId(id).label;
