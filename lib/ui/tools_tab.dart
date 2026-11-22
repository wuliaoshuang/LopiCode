// 设计约束（工具 · 390×844）
// - 三张入口卡：低代码搭建、APK 打包、项目设置。每张卡一句话说明它做什么。
// - 项目设置里只有一件真正需要她决定的事：是否自动批准 Agent 的命令 / 删除。
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key, required this.session, required this.onOpenPreview});
  final ProjectSession session;
  final VoidCallback onOpenPreview;

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  ProjectSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _openBuilder() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => BuilderScreen(session: s)));
    if (result == 'preview') widget.onOpenPreview();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
      children: [
        _EntryCard(
          icon: Icons.dashboard_customize_outlined,
          title: '低代码搭建',
          message: '拖组件拼页面，调属性；自动导出网页，也能导出 Flutter 代码。',
          onTap: _openBuilder,
        ),
        const SizedBox(height: Space.x3),
        _EntryCard(
          icon: Icons.android,
          title: 'APK 打包',
          message: '把项目交给 GitHub Actions 打包，再把 APK 下载回手机。',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BuildScreen(session: s))),
        ),
        const SectionLabelInline('项目设置'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x3, Space.x3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('自动批准 Agent 的操作', style: t.titleSmall),
                      const SizedBox(height: 2),
                      Text('开启后，Agent 执行命令、删除文件不再逐次询问。只对这个项目生效。', style: t.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                Switch(value: s.autoApprove, onChanged: s.setAutoApprove),
              ],
            ),
          ),
        ),
        if (s.autoApprove)
          const InfoBanner(
            '自动批准已开启：Agent 可以不经确认在项目目录里执行命令和删除文件。',
            tone: BannerTone.warning,
            margin: EdgeInsets.only(top: Space.x2),
          ),
        const SizedBox(height: Space.x3),
        Text('项目目录：${s.project.dir}', style: t.bodySmall?.copyWith(color: c.textFaint)),
      ],
    );
  }
}

class SectionLabelInline extends StatelessWidget {
  const SectionLabelInline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.x6, bottom: Space.x2),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.icon, required this.title, required this.message, required this.onTap});
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(icon, color: c.accent),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium),
                    const SizedBox(height: 2),
                    Text(message, style: t.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
