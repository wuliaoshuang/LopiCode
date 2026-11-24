// 从工作区里挑文件（或只挑图片）附到消息上的底部面板。
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
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
      child: FutureBuilder<List<String>>(
        future: listProjectFiles(session.guard),
        builder: (context, snap) {
          final files = (snap.data ?? const <String>[]).where((f) => !f.endsWith('/') && (!imagesOnly || ProjectSession.imageMimeOf(f) != null)).toList();
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
                    imagesOnly ? '工作区里还没有图片。' : '项目里还没有文件。',
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
            ],
          );
        },
      ),
    );
  }
}
