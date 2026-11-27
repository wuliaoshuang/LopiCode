part of 'backend_screen.dart';

// 后端积木页顶栏的副标题和“更多”菜单：从 backend_screen.dart 原样挪出来的，那边放不下了。

/// 副标题：现在什么状态。平时是“语言 · 几个接口”，出了状况换成那句话。
String _beStatus(BeBlockHost host, BackendRegenResult? regen) {
  final errors = host.errorCount;
  if (errors > 0) return blockErrorsBrief(errors);
  if (host.canvasType case final inside?) return '「${inside.name}」';
  if (host.doc.library case final lib?) return regen != null && !regen.ok ? '库文件没有更新' : '库 · 公开了 ${lib.blocks.length} 块积木';
  if (regen != null && !regen.ok) return '代码没有重新生成';
  if (regen != null && regen.conflicts.isNotEmpty) return '${regen.conflicts.length} 个文件没覆盖';
  final target = host.target;
  if (host.doc.isFront) return '前端库 · 在浏览器里跑';
  final lang = target == null ? '${host.doc.language}（没有生成器）' : beLanguageName(target);
  return '$lang · ${host.doc.routes.length} 个接口';
}

bool _beAttention(BeBlockHost host, BackendRegenResult? regen) => host.errorCount > 0 || (regen != null && (!regen.ok || regen.conflicts.isNotEmpty));

List<PopupMenuEntry<String>> _beMenuItems(BuildContext context, BeBlockHost host, BackendRegenResult? regen, bool attention) {
  final c = context.colors;
  final target = host.target;
  Widget row(IconData icon, String text, {Color? color}) => _beMenuRow(context, icon, text, color: color);
  return [
    // 给前端用的库（在浏览器里跑）：没有语言、变量与集合、服务设置这三样。
    if (!host.doc.isFront) ...[
      PopupMenuItem(
        key: const ValueKey('be-menu-language'),
        value: 'language',
        child: Row(
          children: [
            FileIcon.language(host.doc.language, size: 20),
            const SizedBox(width: Space.x3),
            Flexible(child: Text('语言：${target == null ? host.doc.language : beLanguageName(target)}${target != null && !target.verified ? '（未实测）' : ''}')),
          ],
        ),
      ),
      PopupMenuItem(key: const ValueKey('be-menu-data'), value: 'data', child: row(Icons.data_object_rounded, '变量与集合（${host.doc.variables.length} + ${host.doc.collections.length}）')),
      PopupMenuItem(key: const ValueKey('be-menu-settings'), value: 'settings', child: row(Icons.tune_rounded, '服务设置（端口 ${host.doc.port}）')),
    ],
    // 规矩版本：已经是严格规矩的只说一声（不能点）；老规矩的文档给“升级”的入口（beStrictUpgradeEntry 管出不出现，现在默认出现）。
    // 类型与类、模块：只有严格规矩的文档才有（老规矩的文档这个菜单一项不多）。
    if (host.strictRules) PopupMenuItem(key: const ValueKey('be-menu-types'), value: 'types', child: row(Icons.category_outlined, '类型与类（${host.core.types.length}）…')),
    if (host.strictRules) PopupMenuItem(key: const ValueKey('be-menu-modules'), value: 'modules', child: row(Icons.view_module_outlined, '模块（${host.core.modules.length}）…')),
    ...beLibMenuItems(host, row),
    if (host.strictRules)
      PopupMenuItem(key: const ValueKey('be-menu-strict-on'), enabled: false, child: row(Icons.verified_outlined, '严格规矩：已开启'))
    else if (beStrictUpgradeEntry)
      PopupMenuItem(key: const ValueKey('be-menu-strict'), value: 'strict', child: row(Icons.upgrade_rounded, '升级到严格规矩…')),
    PopupMenuItem(
      key: const ValueKey('be-menu-regen'),
      value: 'regen',
      child: row(
        attention ? Icons.warning_amber_rounded : Icons.task_alt_rounded,
        regen != null && regen.conflicts.isNotEmpty ? '${regen.conflicts.length} 个文件没覆盖…' : '代码生成情况',
        color: attention ? c.warning : null,
      ),
    ),
  ];
}

Widget _beMenuRow(BuildContext context, IconData icon, String text, {Color? color}) => Row(
  children: [
    Icon(icon, size: 20, color: color ?? context.colors.textMuted),
    const SizedBox(width: Space.x3),
    Flexible(child: Text(text)),
  ],
);
