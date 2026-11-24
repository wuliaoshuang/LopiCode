// 设计约束（新建项目面板 · 390×844，从底部升起，最高占屏幕九成）
// - 这一面板只回答两个问题：“叫什么”和“从哪个模板开始”。主操作只有“创建”，固定在面板底部，列表再长也不用滚到底才点得到。
// - 从上到下：标题 → 项目名（一行）→ 模板列表（能滚动）→ 创建按钮。
// - 模板按“空白 / 前端 / 后端 · 积木 / 后端 · 代码 / 全栈”分组：组名是一行弱化的小字，组与组之间的空隙比组内大。
// - 一行一个模板：语言图标 + 名字（强）+ 一句说明（弱）；选中的那行换底色、加粗边、行尾打勾。整行可点，行高不小于 56。
// - 要选语言的模板，选中以后才在它下面多出一行“语言”：一排可换行的小胶囊（图标 + 名字），每个高 40。
//   没在本机实际运行过的语言，胶囊上带“未实测”三个小字；胶囊下面一行弱化的小字说明选中语言用什么写的、验证过没有。
// - 默认选中“前端网页”（和以前一样）；不填名字就用“我的 + 模板名”。
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:material_ui/material_ui.dart';

/// 面板的结果：名字、模板、语言（不用选语言的模板为 null）。
typedef NewProjectChoice = ({String name, ProjectTemplate template, String? language});

/// 弹出新建项目面板；取消返回 null。
Future<NewProjectChoice?> showNewProjectSheet(BuildContext context) => showModalBottomSheet<NewProjectChoice>(context: context, isScrollControlled: true, builder: (_) => const NewProjectSheet());

class NewProjectSheet extends StatefulWidget {
  const NewProjectSheet({super.key});

  @override
  State<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<NewProjectSheet> {
  final _name = TextEditingController();
  ProjectTemplate _template = ProjectTemplate.web;

  /// 每个模板各记各的语言：来回切模板不丢选择。
  final Map<ProjectTemplate, String> _language = {};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _languageOf(ProjectTemplate t) => resolveTemplateLanguage(t, _language[t]);

  void _submit() {
    final name = _name.text.trim();
    Navigator.pop<NewProjectChoice>(context, (name: name.isEmpty ? '我的${_template.label}' : name, template: _template, language: _languageOf(_template)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (media.size.height - media.viewInsets.bottom) * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('新建项目', style: t.titleLarge),
                    const SizedBox(height: Space.x4),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: '项目名', hintText: '不填会用模板名'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  key: const ValueKey('tpl-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                  children: [
                    for (final group in TemplateGroup.values) ...[
                      Padding(
                        padding: EdgeInsets.only(top: group == TemplateGroup.values.first ? Space.x1 : Space.x4, bottom: Space.x2),
                        child: Text(group.label, style: t.labelMedium),
                      ),
                      for (final tpl in ProjectTemplate.inGroup(group)) ...[
                        _TemplateRow(template: tpl, selected: _template == tpl, onTap: () => setState(() => _template = tpl)),
                        if (_template == tpl && tpl.needsLanguage) _LanguagePicker(options: templateLanguages(tpl), selected: _languageOf(tpl), onPick: (id) => setState(() => _language[tpl] = id)),
                      ],
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
                child: FilledButton(onPressed: _submit, child: const Text('创建')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.selected, required this.onTap});

  final ProjectTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('tpl-${template.id}'),
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            // 选中时边线粗 1：内边距少 1，行的大小不变，选来选去不会跳
            padding: EdgeInsets.all(selected ? Space.x3 - 1 : Space.x3),
            decoration: BoxDecoration(
              color: selected ? c.accentSoft : c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: selected ? c.accentFill : c.border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                FileIcon.language(template.icon, size: 28),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.label, style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text(template.description, style: t.bodySmall),
                    ],
                  ),
                ),
                if (selected) ...[const SizedBox(width: Space.x2), Icon(Icons.check_circle, size: 20, color: c.accent)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.options, required this.selected, required this.onPick});

  final List<TemplateLanguage> options;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final current = options.where((o) => o.id == selected).firstOrNull;
    return Padding(
      key: const ValueKey('tpl-languages'),
      padding: const EdgeInsets.fromLTRB(Space.x1, Space.x1, Space.x1, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('语言', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [for (final o in options) _LanguageChip(option: o, selected: o.id == selected, onTap: () => onPick(o.id))],
          ),
          if (current != null) ...[
            const SizedBox(height: Space.x2),
            Text(
              '${current.summary}。${current.verified ? '已在电脑上实际运行验证过。' : '这种语言的代码还没有实际运行过，只检查过结构。'}',
              key: const ValueKey('tpl-language-note'),
              style: t.bodySmall?.copyWith(color: current.verified ? c.textMuted : c.warning),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.option, required this.selected, required this.onTap});

  final TemplateLanguage option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('tpl-lang-${option.id}'),
        borderRadius: BorderRadius.circular(Radii.xl),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: selected ? Space.x3 - 1 : Space.x3),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : c.surface,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: selected ? c.accentFill : c.border, width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileIcon.language(option.id, size: 20),
              const SizedBox(width: Space.x2),
              Text(option.label, style: t.labelLarge),
              if (!option.verified) ...[const SizedBox(width: Space.x1), Text('未实测', style: t.labelSmall?.copyWith(color: c.textFaint))],
            ],
          ),
        ),
      ),
    );
  }
}
