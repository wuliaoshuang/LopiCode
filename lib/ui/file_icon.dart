// 文件 / 文件夹 / 语言图标：来自 material-icon-theme（MIT），随安装包走，不联网取。
//
// 设计约束
// - 只是一张方形小图，默认 20，和它替换掉的 Material 图标一样大，放在一行的最前面。
// - 图标是彩色的，原样显示不着色；浅色主题下官方有浅色版的自动换浅色版。
// - 图标文件万一读不出来：退回原来的 Material 图标，不留一块空白、不报错。
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lopicode/core/file_icons.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class FileIcon extends StatelessWidget {
  /// 按文件名 / 文件夹名找图标。[name] 可以带路径。
  const FileIcon(this.name, {super.key, this.isDir = false, this.open = false, this.size = 20}) : _language = false;

  /// 按语言 / 技术栈找图标（node、python、go、java、php、csharp、rust、ruby、kotlin、html、vue、react…）。
  const FileIcon.language(String id, {super.key, this.size = 20}) : name = id, isDir = false, open = false, _language = true;

  final String name;
  final bool isDir;

  /// 文件夹是不是展开的（只对文件夹有用）。
  final bool open;
  final double size;
  final bool _language;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final asset = _language ? languageIconFor(name, light: light) : fileIconFor(name, isDir: isDir, open: open, light: light);
    final fallback = isDir
        ? Icon(open ? Icons.folder_open_outlined : Icons.folder_outlined, size: size, color: c.accent)
        : Icon(_language ? Icons.code : Icons.insert_drive_file_outlined, size: size, color: c.textFaint);
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        asset,
        key: ValueKey('file-icon-$asset'),
        width: size,
        height: size,
        excludeFromSemantics: true,
        placeholderBuilder: (_) => SizedBox(width: size, height: size),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
