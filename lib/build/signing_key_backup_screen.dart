// 设计约束（签名钥匙 · 导出备份 / 导入备份 两页 · 390×844）
// 导出：口令 → 再输一遍 → 主按钮“导出备份”。导出后这一页换成结果：存在哪（一行一个位置、行尾复制）+ 一行“复制备份内容”。
// 导入：备份内容（粘贴，或一行“从工作区选文件”）→ 口令 → 主按钮“导入”。已经有钥匙时点了先二次确认（会换掉现在这把）。
// 每页只有一个主按钮；输入各占一行；报错写在对应输入框下面。
// 口令不存、不进日志、不进普通设置文件；备份文件放在工作区的 build/ 下（远程打包推送文件时会跳过它）。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/local_pack_form.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

/// 一次读进来的备份文件最多这么大（备份只有几 KB；再大的肯定选错了）。
const int kKeyBackupMaxBytes = 256 * 1024;

String _two(int n) => n.toString().padLeft(2, '0');

class KeyExportScreen extends ConsumerStatefulWidget {
  const KeyExportScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<KeyExportScreen> createState() => _KeyExportScreenState();
}

class _KeyExportScreenState extends ConsumerState<KeyExportScreen> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  String? _passError;
  String? _againError;
  bool _busy = false;
  String? _text;
  String? _workspacePath;
  String? _publicPath;
  String? _note;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final pass = _pass.text;
    setState(() {
      _passError = pass.length < kKeyPassphraseMin ? '口令至少 $kKeyPassphraseMin 位' : null;
      _againError = _again.text != pass ? '两次输的不一样' : null;
    });
    if (_passError != null || _againError != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final text = await ref.read(signingKeyProvider.notifier).exportBackup(pass);
      final now = DateTime.now();
      final name = '$kKeyBackupPrefix${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}.txt';
      final file = File(widget.session.guard.resolve('build/$name'));
      await writeStringAtomic(file, text);
      String? public;
      String? note;
      try {
        public = await copyApkToPublic(file.path, widget.session.project.id);
      } on FileSystemException catch (e) {
        note = '没能再抄一份到手机存储（${e.osError?.message ?? e.message}）。';
      }
      widget.session.filesChanged();
      if (!mounted) return;
      _pass.clear();
      _again.clear();
      setState(() {
        _text = text;
        _workspacePath = file.path;
        _publicPath = public;
        _note = note;
      });
    } on SigningKeyException catch (e) {
      if (mounted) setState(() => _passError = e.message);
    } on FileSystemException catch (e) {
      if (mounted) setState(() => _passError = '备份文件写不进去：${e.osError?.message ?? e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text != null) {
      return SettingsPage(
        title: '导出备份',
        children: [
          SettingsGroup(
            title: '备份好了',
            padded: true,
            footer: '把这个文件（或下面复制出来的内容）存到手机以外的地方：网盘、电脑、发给自己都行。光留在这台手机上，手机丢了它也没了。${_note ?? ''}',
            children: [
              if (_publicPath != null) ...[CopyLine(key: const Key('key-backup-public'), label: '手机存储里的位置', value: _publicPath!), const SizedBox(height: Space.x4)],
              CopyLine(key: const Key('key-backup-path'), label: '工作区里的位置', value: _workspacePath!),
            ],
          ),
          SettingsGroup(
            children: [
              SettingsRow(
                key: const Key('key-backup-copy'),
                icon: Icons.copy_rounded,
                title: '复制备份内容',
                subtitle: '是加密过的文字，没有口令打不开',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) showSnack(context, '已复制备份内容');
                },
              ),
            ],
          ),
        ],
      );
    }
    return SettingsPage(
      title: '导出备份',
      children: [
        SettingsGroup(
          title: '给备份设一个口令',
          padded: true,
          footer: '以后导入这份备份要输这个口令。LopiCode 不存它：忘了就打不开这份备份，只能重新导出一份。',
          children: [
            PackField(fieldKey: const Key('key-pass'), label: '口令', controller: _pass, obscure: true, enabled: !_busy, error: _passError, helper: '至少 $kKeyPassphraseMin 位'),
            PackField(fieldKey: const Key('key-pass-again'), label: '再输一遍', controller: _again, obscure: true, enabled: !_busy, error: _againError, last: true),
          ],
        ),
        PrimaryBuildButton(buttonKey: const Key('key-export-go'), label: _busy ? '正在导出…' : '导出备份', onPressed: _busy ? null : _export),
      ],
    );
  }
}

class KeyImportScreen extends ConsumerStatefulWidget {
  const KeyImportScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<KeyImportScreen> createState() => _KeyImportScreenState();
}

class _KeyImportScreenState extends ConsumerState<KeyImportScreen> {
  final _text = TextEditingController();
  final _pass = TextEditingController();
  String? _textError;
  String? _passError;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // 只列名字像备份的文件（不用通用的文件面板：它不列 build/ 这类产物目录，备份正好在那里）。
    List<String> found;
    try {
      found = [
        for (final f in await listProjectFiles(widget.session.guard, limit: 2000))
          if (p.posix.basename(f).startsWith(kKeyBackupPrefix)) f,
      ]..sort((a, b) => b.compareTo(a));
    } on Exception {
      found = const [];
    }
    if (!mounted) return;
    if (found.isEmpty) {
      setState(() => _textError = '工作区里没找到备份文件（名字以 $kKeyBackupPrefix 开头）。把它放进工作区，或者直接把内容贴进来。');
      return;
    }
    final rel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Space.x4),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('选一份备份', style: Theme.of(sheet).textTheme.titleLarge),
            ),
            for (final f in found) SettingsRow(icon: Icons.description_outlined, title: f, onTap: () => Navigator.pop(sheet, f)),
          ],
        ),
      ),
    );
    if (rel == null || !mounted) return;
    try {
      final file = File(widget.session.guard.resolve(rel));
      if (await file.length() > kKeyBackupMaxBytes) {
        if (mounted) setState(() => _textError = '$rel 太大了，不像是钥匙备份。');
        return;
      }
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _text.text = content.trim();
        _textError = null;
      });
    } on FileSystemException catch (e) {
      if (mounted) setState(() => _textError = '读不了 ${p.basename(rel)}：${e.osError?.message ?? e.message}');
    } on FormatException {
      if (mounted) setState(() => _textError = '${p.basename(rel)} 不是文字文件，不像是钥匙备份。');
    }
  }

  Future<void> _import() async {
    setState(() {
      _textError = _text.text.trim().isEmpty ? '先把备份内容贴进来，或者从工作区选备份文件' : null;
      _passError = _pass.text.isEmpty ? '输导出时设的口令' : null;
    });
    if (_textError != null || _passError != null) return;
    FocusScope.of(context).unfocus();
    if (ref.read(signingKeyProvider).hasKey) {
      final ok = await confirmDialog(context, title: '换掉现在的钥匙？', message: '导入以后，现在这把会被备份里的那把换掉，而且找不回来（除非它也有备份）。\n\n手机上用现在这把装的应用，之后要先卸载才能装新包。', confirmLabel: '换掉，导入', danger: true);
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(signingKeyProvider.notifier).importBackup(_text.text, _pass.text);
      if (!mounted) return;
      _pass.clear();
      showSnack(context, '钥匙已导入');
      Navigator.of(context).pop();
    } on SigningKeyException catch (e) {
      // 口令不对和内容不对分不清时都写在口令下面：那是她最可能要改的地方。
      if (mounted) setState(() => _passError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: '导入备份',
      children: [
        SettingsGroup(
          title: '备份内容',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
              child: PackField(fieldKey: const Key('key-import-text'), label: '把备份文件里的内容贴到这里', controller: _text, enabled: !_busy, mono: true, minLines: 3, maxLines: 6, error: _textError, last: true),
            ),
            SettingsRow(key: const Key('key-import-file'), icon: Icons.folder_open_outlined, title: '从工作区选备份文件', enabled: !_busy, onTap: _pickFile),
          ],
        ),
        SettingsGroup(
          title: '口令',
          padded: true,
          children: [PackField(fieldKey: const Key('key-import-pass'), label: '导出时设的口令', controller: _pass, obscure: true, enabled: !_busy, error: _passError, last: true)],
        ),
        PrimaryBuildButton(buttonKey: const Key('key-import-go'), label: _busy ? '正在导入…' : '导入', onPressed: _busy ? null : _import),
      ],
    );
  }
}
