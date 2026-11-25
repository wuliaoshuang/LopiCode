// 设计约束（本地打包 · 图标面板 · 底部面板）
// 上面是现在这张图标的大预览和一句状态；下面两行操作：“选一张图”、“恢复默认图标”（没换过就不出现）。
// 图不能用（太小 / 打不开）时原因写在预览下面，原来的图标不动。
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lopicode/build/apk_icon.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 测试用：换掉系统相册。返回 null ＝ 用户没选。
Future<Uint8List?> Function()? pickIconImageOverride;

Future<Uint8List?> _pickIconImage() async {
  final override = pickIconImageOverride;
  if (override != null) return override();
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

Future<void> showApkIconSheet(BuildContext context, ProjectSession session) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ApkIconSheet(session: session),
);

class ApkIconSheet extends ConsumerStatefulWidget {
  const ApkIconSheet({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<ApkIconSheet> createState() => _ApkIconSheetState();
}

class _ApkIconSheetState extends ConsumerState<ApkIconSheet> {
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final bytes = await _pickIconImage();
      if (bytes == null || !mounted) return;
      await ref.read(localPackProvider(widget.session).notifier).setIcon(bytes);
    } on ApkIconException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // 相册打不开之类：说清是哪一类问题，不带别的。
      if (mounted) setState(() => _error = '没能打开相册（${e.runtimeType}）。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(localPackProvider(widget.session));
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
            child: Text('图标', style: t.titleLarge),
          ),
          Center(
            child: ApkIconPreview(png: s.icons[192], size: 96, busy: s.iconBusy),
          ),
          const SizedBox(height: Space.x3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x6),
            child: Text(
              _error ?? (s.form.customIcon ? '用的是你选的图' : '默认图标（上面是示意，实际是壳自带的那一张）'),
              key: const Key('pack-icon-status'),
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: _error != null ? c.danger : c.textFaint, height: 1.5),
            ),
          ),
          const SizedBox(height: Space.x3),
          SettingsRow(
            key: const Key('pack-icon-pick'),
            icon: Icons.image_outlined,
            title: '选一张图',
            subtitle: '会从正中间裁成正方形；至少 $kIconMinSide×$kIconMinSide',
            enabled: !s.busy && !s.iconBusy,
            onTap: _pick,
          ),
          if (s.form.customIcon)
            SettingsRow(
              key: const Key('pack-icon-reset'),
              icon: Icons.restart_alt_rounded,
              title: '恢复默认图标',
              enabled: !s.busy && !s.iconBusy,
              onTap: () {
                setState(() => _error = null);
                ref.read(localPackProvider(widget.session).notifier).clearIcon();
              },
            ),
          const SizedBox(height: Space.x4),
        ],
      ),
    );
  }
}
