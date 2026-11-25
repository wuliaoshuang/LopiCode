// 从工作区里挑文件（或只挑图片）附到消息上的底部面板。
// 列哪些文件和输入框里“打 @ 选文件”是同一套（session/file_mentions.dart）：不进版本库、依赖、构建产物这些目录，
// 不然装过依赖的项目一打开全是 node_modules，自己的文件反而排不上。挑图片时多列一处：以前附过的图片（附件目录）。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/attachments.dart';
import 'package:lopicode/session/file_mentions.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:material_ui/material_ui.dart';

class FilePickerSheet extends StatelessWidget {
  const FilePickerSheet({super.key, required this.session, this.imagesOnly = false});
  final ProjectSession session;

  /// 只列图片（当附件用）。
  final bool imagesOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: FutureBuilder<MentionScan>(
        future: scanMentionFiles(session.guard, skipDirs: imagesOnly ? kMentionSkipDirs.difference(const {kAttachmentsDir}) : kMentionSkipDirs),
        builder: (context, snap) {
          final scan = snap.data;
          final files = (scan?.files ?? const <String>[]).where((f) => !imagesOnly || ProjectSession.imageMimeOf(f) != null).toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text(imagesOnly ? '选工作区里的图片' : '引用项目文件', style: t.titleLarge),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(Space.x6),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.x6),
                  child: Text(
                    scan?.error ?? (imagesOnly ? '工作区里还没有图片。' : '项目里还没有文件。'),
                    style: t.bodyMedium?.copyWith(color: c.textMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      leading: FileIcon(files[i]),
                      title: Text(files[i], style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, files[i]),
                    ),
                  ),
                ),
              if (scan != null && scan.truncated)
                Padding(
                  key: const ValueKey('picker-truncated'),
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                  child: Text('工作区文件太多，只找了前 ${scan.files.length} 个。没列出来的可以在输入框里直接打 @ 加路径。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                ),
            ],
          );
        },
      ),
    );
  }
}
