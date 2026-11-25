// 设计约束（本地打包 · 权限面板 · 底部面板）
// 一行一项权限：左边勾选框，名称，下面一句“什么时候要开”。默认只勾联网；别的想要才勾。
// 没有“确定”按钮：勾了就生效（和设置页的勾选行一样），关掉面板即可。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showApkPermissionsSheet(BuildContext context, ProjectSession session) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ApkPermissionsSheet(session: session),
);

class ApkPermissionsSheet extends ConsumerWidget {
  const ApkPermissionsSheet({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(localPackProvider(session));
    final options = currentLocalPackBackend().permissionOptions;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('权限', style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('应用装到手机上以后能用哪些东西。只勾网页真的要用的：勾得多，装的时候别人会不放心。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.x4),
                children: [
                  for (final o in options)
                    SettingsCheckRow(
                      key: Key('pack-perm-${o.id.split('.').last}'),
                      title: o.label,
                      subtitle: o.hint,
                      checked: s.form.permissions.contains(o.id),
                      onChanged: s.busy ? null : (v) => ref.read(localPackProvider(session).notifier).setPermission(o.id, v),
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
