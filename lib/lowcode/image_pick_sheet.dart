// 设计约束（低代码 · 给图片组件选图 · 390×844）
// - 两个来源，入口在合一面板“常用”页的图片那一行：
//     从相册选：直接开系统自带的选图界面（不用任何权限），选一张 → 拷进项目的 images/ → 图片地址写相对路径。
//     项目文件：底部面板，三列缩略图（方块，底下一行文件名），点一张就用它、面板关掉。没有主操作。
// - 空状态：项目里一张图片都没有时说清楚“可以从相册选，或者把图片放进项目的 images/ 目录”。
// - 取用的 tokens：Space.x2/x4/x6、Radii.sm、surfaceMuted（缩略图底）、textMuted（文件名）。
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/image_assets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 一个项目的图片：画布靠它把相对地址认成文件，面板靠它选图。
class LcImages {
  LcImages(this.guard, {this.onImported});
  final PathGuard guard;

  /// 往项目里拷了新图片（文件树要刷新）。
  final VoidCallback? onImported;

  String? resolve(String src) => lcResolveImage(guard, src);

  /// [from]：gallery＝从相册选；project＝从项目文件里选。返回要写进图片地址的相对路径；没选返回 null。
  Future<String?> pick(BuildContext context, String from) async {
    if (from == 'project') return showProjectImageSheet(context, guard);
    try {
      final picked = await pickImages(camera: false, single: true);
      if (picked.isEmpty) return null;
      final rel = await lcImportImage(guard, picked.first.name, picked.first.bytes);
      onImported?.call();
      return rel;
    } on FileSystemException catch (e) {
      if (context.mounted) showSnack(context, '图片存不进项目：${e.osError?.message ?? e.message}');
    } on PathGuardException catch (e) {
      if (context.mounted) showSnack(context, '图片存不进项目：${e.message}');
    } on Exception catch (e) {
      // 系统的选图界面打不开（很少见）：说出原因，不装作没事。
      if (context.mounted) showSnack(context, '打不开相册：$e');
    }
    return null;
  }
}

/// 从项目里已有的图片中选一张；返回相对地址。
Future<String?> showProjectImageSheet(BuildContext context, PathGuard guard) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ProjectImageSheet(guard: guard),
);

class _ProjectImageSheet extends StatefulWidget {
  const _ProjectImageSheet({required this.guard});
  final PathGuard guard;

  @override
  State<_ProjectImageSheet> createState() => _ProjectImageSheetState();
}

class _ProjectImageSheetState extends State<_ProjectImageSheet> {
  late final Future<List<String>> _images = lcListProjectImages(widget.guard);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => FutureBuilder<List<String>>(
        future: _images,
        builder: (context, snap) {
          final list = snap.data;
          return CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
                  child: Text(list == null ? '项目里的图片' : '项目里的图片 · ${list.length} 张', style: t.titleLarge),
                ),
              ),
              if (list == null)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(Space.x6), child: Center(child: CircularProgressIndicator())),
                )
              else if (list.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(Space.x6),
                    child: EmptyState(icon: Icons.image_outlined, title: '项目里还没有图片', message: '可以回去点“从相册选”，\n或者把图片文件放进项目的 $kLcImageDir/ 目录。'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x6),
                  sliver: SliverGrid.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: Space.x3,
                    crossAxisSpacing: Space.x3,
                    childAspectRatio: 0.8,
                    children: [
                      for (final rel in list)
                        InkWell(
                          key: Key('lc-project-image-$rel'),
                          borderRadius: BorderRadius.circular(Radii.sm),
                          onTap: () => Navigator.pop(context, rel),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(Radii.sm),
                                  child: ColoredBox(
                                    color: c.surfaceMuted,
                                    child: rel.toLowerCase().endsWith('.svg')
                                        ? Icon(Icons.image_outlined, color: c.textFaint)
                                        : Image.file(
                                            File(widget.guard.resolve(rel)),
                                            fit: BoxFit.cover,
                                            cacheWidth: 240,
                                            errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textFaint),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Space.x1),
                              Text(rel.split('/').last, style: t.bodySmall?.copyWith(color: c.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
