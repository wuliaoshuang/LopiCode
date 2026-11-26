// 设计约束（文件信息面板 · 底部面板 · 390×844）
// 编辑器打不开的文件（安装包、别的二进制文件、超过 1MB 的大文件）点了不再只弹一句话，而是出这张面板。
// 内容排序（先定的这个）：
//   主要：这是什么（图标 + 名字；安装包是应用名 + 包名）→ 为什么打不开 / 安装包的版本和大小 → 能做的那一件主要的事（安装包＝“安装”）。
//   次要：它在哪（工作区里的位置、手机上的完整路径，各一行、行尾复制）；安装包的签名指纹（一行、可复制）。
//   再次：重命名 / 移动、删除（和长按菜单里是同一套，不是新功能）。
// 一行只做一件事；除“安装”外没有第二个主按钮。安装包读不懂（坏的 / 不是安装包）时：用大白话说原因，
//   仍然给大小、位置这些基本信息，“安装”降成次要按钮“仍然试着安装”。
// 解析安装包在后台做（不卡界面），读的时候先显示文件名和大小，读完再换成应用名。
import 'dart:io';

import 'package:lopicode/apkpack/apk_inspect.dart';
import 'package:lopicode/build/apk_install_view.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:material_ui/material_ui.dart';

/// 编辑器能打开的文字文件最大这么大（原来就是 1MB，这里只是给它起了名字）。
const int kEditorMaxBytes = 1024 * 1024;

/// 为什么编辑器打不开。
enum FileBlock { apk, binary, tooLarge }

/// 测试用：换掉“解析安装包”（界面测试里不起后台 isolate）。
Future<ApkInfo> Function(String path)? apkInspectOverride;

bool isApkPath(String path) => path.toLowerCase().endsWith('.apk');

/// 按后缀说这是哪一类文件；不认识的后缀返回 null。
String? fileKindLabel(String path) {
  final name = path.split('/').last.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot <= 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'apk' => '安卓安装包',
    'aab' => '安卓应用包（AAB）',
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'ico' => '图片',
    'zip' || 'tar' || 'gz' || 'tgz' || 'bz2' || 'xz' || '7z' || 'rar' || 'jar' => '压缩包',
    'mp3' || 'wav' || 'ogg' || 'm4a' || 'flac' => '音频',
    'mp4' || 'webm' || 'mov' || 'mkv' || 'avi' => '视频',
    'ttf' || 'otf' || 'woff' || 'woff2' => '字体',
    'pdf' => 'PDF 文档',
    'db' || 'sqlite' || 'sqlite3' => '数据库文件',
    'so' || 'dll' || 'exe' || 'bin' || 'o' || 'a' || 'class' || 'dex' || 'wasm' => '程序 / 库文件',
    'keystore' || 'jks' || 'p12' => '签名钥匙库',
    _ => null,
  };
}

/// 打开面板。[path] 是工作区里的相对路径，[fullPath] 是手机上的完整路径。
/// [onRename] / [onDelete] 就是长按菜单里那两项；面板先收起再调。
Future<void> showFileInfoSheet(
  BuildContext context, {
  required String path,
  required String fullPath,
  required FileBlock block,
  required int sizeBytes,
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: FileInfoPanel(
          path: path,
          fullPath: fullPath,
          block: block,
          sizeBytes: sizeBytes,
          onRename: () {
            Navigator.pop(sheet);
            onRename();
          },
          onDelete: () {
            Navigator.pop(sheet);
            onDelete();
          },
        ),
      ),
    ),
  ),
);

class FileInfoPanel extends StatefulWidget {
  const FileInfoPanel({super.key, required this.path, required this.fullPath, required this.block, required this.sizeBytes, required this.onRename, required this.onDelete});
  final String path;
  final String fullPath;
  final FileBlock block;
  final int sizeBytes;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<FileInfoPanel> createState() => _FileInfoPanelState();
}

class _FileInfoPanelState extends State<FileInfoPanel> {
  ApkInfo? _apk;
  String? _apkError;
  bool _reading = false;
  DateTime? _modified;

  String get _name => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isApk = widget.block == FileBlock.apk;
    if (isApk) _reading = true;
    try {
      final stat = await File(widget.fullPath).stat();
      if (mounted && stat.type != FileSystemEntityType.notFound) setState(() => _modified = stat.modified);
    } on FileSystemException {
      // 取不到修改时间就不显示这一行
    }
    if (!isApk) return;
    try {
      final info = await (apkInspectOverride ?? inspectApk)(widget.fullPath);
      if (mounted) setState(() => _apk = info);
    } on ApkInspectException catch (e) {
      if (mounted) setState(() => _apkError = e.message);
    } catch (e) {
      // 后台解析意外出错（不该发生）：当成读不懂，不让面板崩
      if (mounted) setState(() => _apkError = '读这个安装包的时候出了意外（${e.runtimeType}），它的内容这里看不了。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  String get _why => switch (widget.block) {
    FileBlock.apk => '',
    FileBlock.binary => '这是二进制文件（里面不是文字），编辑器打不开。',
    FileBlock.tooLarge => '这个文件超过 1MB，编辑器打不开这么大的文件。要看内容可以到终端里用 less、head 这类命令。',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final apk = _apk;
    final isApk = widget.block == FileBlock.apk;
    final size = ApkBuildController.formatBytes(widget.sizeBytes);
    final kind = fileKindLabel(widget.path) ?? (widget.block == FileBlock.tooLarge ? '文本文件' : '二进制文件');
    final m = _modified;
    String two(int v) => v.toString().padLeft(2, '0');
    Widget fact(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: t.bodyMedium?.copyWith(color: c.textFaint)),
          ),
          Expanded(
            child: Text(value, key: key, style: t.bodyMedium),
          ),
        ],
      ),
    );
    return Column(
      key: const Key('file-info'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (isApk) const ApkIconPreview(png: null, size: 48) else SizedBox.square(dimension: 48, child: Center(child: FileIcon(widget.path, size: 32))),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(apk?.appName ?? _name, key: const Key('file-info-title'), style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    apk != null ? apk.packageName : '$kind · $size',
                    key: const Key('file-info-subtitle'),
                    style: apk != null
                        ? TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.textMuted)
                        : t.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        if (!isApk)
          Text(
            _why,
            key: const Key('file-info-why'),
            style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.5),
          ),
        if (isApk && _reading)
          Row(
            children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Space.x3),
              Text('正在读安装包信息…', style: t.bodyMedium?.copyWith(color: c.textMuted)),
            ],
          ),
        if (_apkError != null)
          Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: c.warning),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    '看不了这个安装包的信息：$_apkError',
                    key: const Key('file-info-apk-error'),
                    style: t.bodySmall?.copyWith(color: c.text, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        if (apk != null) ...[
          if (apk.appName == null) fact('应用名', '写在安装包的资源表里，这里没读出来'),
          fact('版本', '${apk.versionName ?? '没写版本名'}${apk.versionCode == null ? '' : '（版本号 ${apk.versionCode}）'}', key: const Key('file-info-version')),
          fact('大小', size),
          fact('文件名', _name),
        ],
        if (m != null) fact('修改时间', '${m.year}-${two(m.month)}-${two(m.day)} ${two(m.hour)}:${two(m.minute)}'),
        if (isApk && !_reading) ...[const SizedBox(height: Space.x3), ApkInstallButton(path: widget.fullPath, primary: apk != null, idleLabel: apk != null ? '安装' : '仍然试着安装')],
        const SizedBox(height: Space.x4),
        Divider(height: 1, color: c.border),
        const SizedBox(height: Space.x3),
        CopyLine(key: const Key('file-info-path'), label: '工作区里的位置', value: widget.path),
        const SizedBox(height: Space.x3),
        CopyLine(key: const Key('file-info-full-path'), label: '手机上的完整路径', value: widget.fullPath),
        if (apk != null) ...[
          const SizedBox(height: Space.x3),
          if (apk.certSha256Hex != null)
            CopyLine(key: const Key('file-info-cert'), label: '签名证书指纹（SHA-256，${apk.signScheme} 签名里读到的）', value: apk.certSha256Hex!, note: '同一把钥匙签的包指纹相同，才能互相覆盖升级。这里只是读出包里带的证书，没有检查签名本身有没有效。')
          else
            Text(
              '没有读到签名证书：这个包可能没签名，或者用了这里不认识的签名方式。没签名的包系统不让装。',
              key: const Key('file-info-nocert'),
              style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5),
            ),
        ],
        const SizedBox(height: Space.x2),
        ListTile(key: const Key('file-info-rename'), contentPadding: EdgeInsets.zero, leading: const Icon(Icons.drive_file_rename_outline), title: const Text('重命名 / 移动'), onTap: widget.onRename),
        ListTile(
          key: const Key('file-info-delete'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline, color: c.danger),
          title: Text('删除', style: TextStyle(color: c.danger)),
          onTap: widget.onDelete,
        ),
      ],
    );
  }
}
