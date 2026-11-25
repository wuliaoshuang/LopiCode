// 设计约束（设置 › 界面 › 外观 › 背景图片 · 390×844，浅色 + 深色）
// 层级（先定这个，再排版，最后上色）：
// - 最重要：图本身。没图时整页只有一个主操作“选择图片”（实心按钮，放在说明下面）；
//   有图时最上面是一块手机比例的效果预览（背景 + 示例文字 + 气泡），改什么立刻看得到。
// - 其次：对这张图能做的三件事，一行三个：重新裁剪 / 换一张 / 移除（移除是红字，点了先确认，确认后删文件）。
// - 再往下按“改得多不多”排组，一行只做一件事：
//   显示（总开关、适配方式、平铺时的格子大小）→ 效果（遮罩、遮罩颜色、模糊、亮度、表面不透明度、恢复默认）
//   → 范围（聊天页 / 其它页面）→ 透出（终端 / 代码区 / 积木画布 / 低代码画布，默认都关）→ 深色外观（单独设置）。
// - 数值都用“名称 + 数值 / 减 · 滑杆 · 加”的数值行（backdrop_controls.dart）：手机上滑杆拖不准，有步进按钮兜着。
// - 深色单独设置开着时，预览上面多一行“浅色 / 深色”分段：现在改的是哪一份。
// 颜色只用 context.colors；强调色只给主操作、开关和选中态；红色只给“移除”。
// 所有改动实时生效（预览和真页面一起变）；滑杆拖动过程中只改内存，松手才写盘。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_controls.dart';
import 'package:lopicode/ui/backdrop_crop_screen.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/backdrop_settings_groups.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 背景图片设置页：外观页“背景图”那一行直接 push 它；那一行的状态文字用 backdropStatusProvider（lib/state/backdrop_state.dart）。
class BackdropSettingsScreen extends ConsumerStatefulWidget {
  const BackdropSettingsScreen({super.key});

  @override
  ConsumerState<BackdropSettingsScreen> createState() => _BackdropSettingsScreenState();
}

class _BackdropSettingsScreenState extends ConsumerState<BackdropSettingsScreen> {
  /// 深色单独设置开着时，现在改的是不是深色那一份。null＝还没手动选过，跟着当前外观走。
  bool? _editDark;
  bool _busy = false;

  bool _dark(BackdropSettings s) => s.darkSeparate && (_editDark ?? Theme.of(context).brightness == Brightness.dark);

  /// 选图 → 裁剪 → 用上。中途放弃就把刚入库的图删掉。
  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(backdropProvider.notifier);
    final result = await notifier.pickAndImport();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case BackdropImportCancelled():
        return;
      case BackdropImportFailed(:final message):
        showSnack(context, message);
        return;
      case BackdropImportOk(:final image):
        final s = ref.read(backdropProvider);
        final dark = _dark(s);
        final look = (dark ? s.dark : s.light).withImage(file: image.file, width: image.width, height: image.height, crop: CropRect.full);
        final cropped = await _openCrop(look, fresh: true);
        if (cropped == null) {
          await notifier.discard();
          return;
        }
        await notifier.setImage(dark: dark, image: image, crop: cropped.crop, turns: cropped.turns);
    }
  }

  Future<BackdropCropResult?> _openCrop(BackdropLook look, {required bool fresh}) {
    final store = ref.read(backdropStoreProvider);
    return Navigator.of(context).push<BackdropCropResult>(
      MaterialPageRoute(
        builder: (_) => BackdropCropScreen(path: store.imageFile(look.file!).path, look: look, settings: ref.read(backdropProvider), fresh: fresh),
      ),
    );
  }

  Future<void> _recrop() async {
    final s = ref.read(backdropProvider);
    final dark = _dark(s);
    final cropped = await _openCrop(dark ? s.dark : s.light, fresh: false);
    if (cropped == null) return;
    await ref.read(backdropProvider.notifier).setCrop(dark: dark, crop: cropped.crop, turns: cropped.turns);
  }

  Future<void> _remove() async {
    final s = ref.read(backdropProvider);
    final dark = _dark(s);
    final ok = await confirmDialog(context, title: '移除背景图片？', message: '图片会从应用里删掉（不影响相册里的原图）。遮罩、模糊这些效果设置会留着。', confirmLabel: '移除', danger: true);
    if (!ok || !mounted) return;
    final file = (dark ? s.dark : s.light).file;
    final store = ref.read(backdropStoreProvider);
    await ref.read(backdropProvider.notifier).removeImage(dark: dark);
    // 另一份（浅 / 深）还在用同一个文件时它不会被删，缓存也留着
    if (file != null && !ref.read(backdropProvider).files.contains(file)) BackdropImages.instance.forget(store.imageFile(file).path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = ref.watch(backdropProvider);
    final notifier = ref.read(backdropProvider.notifier);
    final dark = _dark(s);
    final look = dark ? s.dark : s.light;
    final store = ref.watch(backdropStoreProvider);
    if (!s.loaded) {
      return const SettingsPage(
        title: '背景图片',
        children: [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))],
      );
    }
    return SettingsPage(
      title: '背景图片',
      listKey: const Key('bg-settings-list'),
      children: [
        if (s.darkSeparate)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x4),
            child: SegmentedButton<bool>(
              key: const Key('bg-slot'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('浅色外观')),
                ButtonSegment(value: true, label: Text('深色外观')),
              ],
              selected: {dark},
              onSelectionChanged: (v) => setState(() => _editDark = v.first),
            ),
          ),
        if (!look.hasImage)
          SettingsGroup(
            padded: true,
            footer: '只收 JPG、PNG、WebP，文件不超过 ${kBackdropMaxFileBytes ~/ (1024 * 1024)}MB；太大的图会自动缩小。图片会复制一份存在应用里，不需要相册权限。',
            children: [
              Icon(Icons.wallpaper_outlined, size: 40, color: c.textFaint),
              const SizedBox(height: Space.x3),
              Text(s.darkSeparate ? '${dark ? '深色' : '浅色'}外观还没有背景图片' : '还没有背景图片', key: const Key('bg-empty'), textAlign: TextAlign.center, style: t.titleMedium),
              const SizedBox(height: Space.x1),
              Text(
                '选一张图，裁成手机屏幕的样子，铺在聊天页后面。',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: Space.x4),
              FilledButton.icon(key: const Key('bg-pick'), onPressed: _busy ? null : _pick, icon: const Icon(Icons.add_photo_alternate_outlined, size: 20), label: Text(_busy ? '正在读取…' : '选择图片')),
            ],
          )
        else ...[
          Center(
            child: SizedBox(
              height: 300,
              child: AspectRatio(
                aspectRatio: phoneAspectOf(context),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: c.border),
                  ),
                  child: BackdropPreview(key: const Key('bg-preview'), look: look, path: store.imageFile(look.file!).path, settings: s),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(
                child: TextButton(key: const Key('bg-recrop'), onPressed: _recrop, child: const Text('重新裁剪')),
              ),
              Expanded(
                child: TextButton(key: const Key('bg-replace'), onPressed: _busy ? null : _pick, child: Text(_busy ? '正在读取…' : '换一张')),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('bg-remove'),
                  onPressed: _remove,
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  child: const Text('移除'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          BackdropDisplayGroup(settings: s, look: look, dark: dark, notifier: notifier),
          BackdropEffectGroup(settings: s, look: look, dark: dark, notifier: notifier),
          BackdropScopeGroups(settings: s, notifier: notifier),
        ],
        SettingsGroup(
          title: '深色外观',
          footer: s.darkSeparate ? '浅色、深色各用各的图和效果。在页面最上面切换现在改的是哪一份。' : '关着时，浅色和深色外观用同一张图、同一套效果（遮罩跟随主题时会自己变深）。',
          children: [
            SettingsSwitchRow(
              title: '深色时单独设置',
              subtitle: '给深色外观另选一张图，或者只是调暗一点',
              switchKey: const Key('bg-dark-separate'),
              value: s.darkSeparate,
              onChanged: (v) async {
                await notifier.setDarkSeparate(v);
                if (mounted && !v) setState(() => _editDark = null);
              },
            ),
          ],
        ),
      ],
    );
  }
}
