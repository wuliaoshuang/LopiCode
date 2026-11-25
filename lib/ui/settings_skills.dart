// 设计约束（技能 / 新建技能 / 技能全文 · 390×844）— 2026-11-24 从 settings_agent.dart 拆出来并按设置的统一样式重排
// - 技能页分两组，组标题写明归属：〔这个工作区：X〕只对当前工作区生效；〔全局〕所有工作区都能用。
//   一行一个技能：名字 + 描述，右边是开关；点行看全文（删除在全文页右上角菜单里）。主操作只有右下角“新建技能”。
//   技能文件夹里带脚本的，描述下面多一行“带 N 个脚本”（2026-11-25；脚本怎么放、在哪跑写在全文页，见 skill_scripts_view.dart）。
// - 新建技能：〔内容〕技能名 → 一句话描述 → 正文（表单组）；〔放在哪〕两行单选（只给这个工作区 / 全局），从工作区进来才有；最底下一个实心“创建”。
// - 全文页：归属和怎么改写在上面一组，正文是等宽字的代码块。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/state/skills_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/skill_scripts_view.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class SkillsScreen extends ConsumerStatefulWidget {
  const SkillsScreen({super.key, this.workspace});
  final Project? workspace;

  @override
  ConsumerState<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends ConsumerState<SkillsScreen> {
  Future<void> _create() => pushSettingsPage<bool>(context, SkillEditScreen(workspace: widget.workspace));

  Future<void> _open(Skill skill) => pushSettingsPage<void>(context, SkillViewScreen(skill: skill));

  @override
  Widget build(BuildContext context) {
    // 技能清单：增删、开关之后它自己重新扫描，这里只管照着画
    final state = ref.watch(skillsProvider(widget.workspace?.dir));
    final edit = ref.read(skillsProvider(widget.workspace?.dir).notifier);
    final c = context.colors;
    final skills = state.skills;
    final ws = state.ofWorkspace;
    final global = state.global;
    Widget row(Skill s) => SettingsRow(
      key: Key('skill-${s.key}'),
      title: s.name,
      subtitle: '${s.description.isEmpty ? '（没有写描述）' : s.description}${skillScriptsBadge(s)}',
      trailing: SizedBox(
        height: 32,
        child: Switch(value: s.enabled, onChanged: (v) => edit.setEnabled(s, v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
      onTap: () => _open(s),
    );
    if (skills == null || skills.isEmpty) {
      return Scaffold(
        backgroundColor: c.canvas,
        extendBodyBehindAppBar: true,
        appBar: PageBar(background: c.canvas, titleText: '技能'),
        body: skills == null
            ? const Center(child: CircularProgressIndicator())
            : BelowBar(
                child: EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '还没有技能',
                  message: '技能是一份写给 Agent 的做事说明书（SKILL.md）。\nAgent 平时只看到名字和描述，用得上时再读全文。',
                  action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('新建技能')),
                ),
              ),
      );
    }
    return SettingsPage(
      title: '技能',
      bottom: 96,
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, elevation: 2, shape: const StadiumBorder(), icon: const Icon(Icons.add), label: const Text('新建技能')),
      children: [
        if (widget.workspace != null)
          SettingsGroup(
            title: '这个工作区：${widget.workspace!.name}',
            footer: '只对这个工作区生效，文件在它的 .lopicode/skills/ 里。和全局技能同名时，这里的优先。',
            children: [
              if (ws.isEmpty) const SettingsRow(title: '这个工作区还没有自己的技能', enabled: false),
              for (final s in ws) row(s),
            ],
          ),
        SettingsGroup(
          title: '全局（所有工作区都能用）',
          footer: '开着的技能，名字和描述会告诉 Agent；它用得上时自己读全文。点一行看全文。',
          children: [
            if (global.isEmpty) const SettingsRow(title: '还没有全局技能', enabled: false),
            for (final s in global) row(s),
          ],
        ),
      ],
    );
  }
}

class SkillEditScreen extends ConsumerStatefulWidget {
  const SkillEditScreen({super.key, this.workspace});
  final Project? workspace;

  @override
  ConsumerState<SkillEditScreen> createState() => _SkillEditScreenState();
}

class _SkillEditScreenState extends ConsumerState<SkillEditScreen> {
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
    try {
      await ref.read(skillsProvider(widget.workspace?.dir).notifier).create(name: _name.text, description: _desc.text, body: _body.text, global: _global);
      if (mounted) Navigator.pop(context, true);
    } on SkillException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Exception catch (e) {
      if (mounted) showSnack(context, '没建成：$e');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: '新建技能',
    children: [
      SettingsGroup(
        title: '内容',
        padded: true,
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
        ],
      ),
      if (widget.workspace != null)
        SettingsGroup(
          title: '放在哪',
          children: [
            SettingsChoiceRow(key: const Key('skill-scope-workspace'), title: '只给这个工作区', subtitle: widget.workspace!.name, selected: !_global, onTap: () => setState(() => _global = false)),
            SettingsChoiceRow(key: const Key('skill-scope-global'), title: '全局', subtitle: '所有工作区都能用', selected: _global, onTap: () => setState(() => _global = true)),
          ],
        ),
      FilledButton(key: const Key('skill-save'), onPressed: _save, child: const Text('创建')),
    ],
  );
}

class SkillViewScreen extends StatelessWidget {
  const SkillViewScreen({super.key, required this.skill});
  final Skill skill;

  @override
  Widget build(BuildContext context) {
    final app = appOf(context);
    final c = context.colors;
    return SettingsPage(
      title: skill.name,
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
      children: [
        SettingsGroup(
          title: skill.global ? '全局技能' : '工作区技能',
          footer: '要改内容，直接编辑这个技能文件夹里的 SKILL.md。',
          padded: true,
          children: [
            FutureBuilder<String>(
              future: app.skills.readFull(skill),
              builder: (context, snap) => Container(
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
            ),
          ],
        ),
        SkillScriptsGroup(skill: skill),
      ],
    );
  }
}
