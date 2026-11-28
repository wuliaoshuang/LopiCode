// 设计约束（页面逻辑·一个自带前端库的面板：定时、请求、本地保存、状态仓库、事件总线；390 宽，浅色 + 深色）— 2026-11-28
// - 内容排序：主＝最上面一行开关“在这份文档里用它”（和项目里的库的面板同一个样子、同一个键）；
//   次＝“在画布上看（只读）”（强调色文字行）；最后是积木清单（一块一行，只看，灰字）。
// - 关不掉的时候（文档里还有它的积木）原因写在面板顶上的提示条里，不弹窗。
// - 颜色全取主题值；间距只用 Space 里的档。
import 'dart:async';

import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_table.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_front_builtin.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_lib_view_screen.dart';
import 'package:material_ui/material_ui.dart';

/// 一个要用才用的自带前端库的面板：开关、只读画布、积木清单。
Future<void> showFrontBuiltinLib(BuildContext context, BeBlockHost host, LibLibrary lib) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _FrontBuiltinSheet(host: host, lib: lib, from: context),
);

class _FrontBuiltinSheet extends StatefulWidget {
  const _FrontBuiltinSheet({required this.host, required this.lib, required this.from});
  final BeBlockHost host;
  final LibLibrary lib;
  final BuildContext from;

  @override
  State<_FrontBuiltinSheet> createState() => _FrontBuiltinSheetState();
}

class _FrontBuiltinSheetState extends State<_FrontBuiltinSheet> {
  String? _problem;
  BeBlockHost get host => widget.host;
  LibLibrary get lib => widget.lib;

  void _toggle(bool on) {
    final doc = host.doc;
    if (on) {
      if (doc.uses.length >= kBeMaxLibUses) return setState(() => _problem = '一份文档最多用 $kBeMaxLibUses 个库。');
      host.edit(() => doc.uses.add(BeLibUse(lib.id)));
      return setState(() => _problem = null);
    }
    final n = BeLibTable(doc).usesOfLib(lib.id);
    if (n > 0) return setState(() => _problem = '这份文档里还有 $n 处在用它的积木。先把那些积木删掉，再关。');
    final needs = [
      for (final u in doc.uses)
        if (doc.lib(u.id) case final l? when l.requires.contains(lib.id)) l.name,
    ];
    if (needs.isNotEmpty) return setState(() => _problem = '库「${needs.first}」要靠它。先把「${needs.first}」关掉，再关它。');
    host.edit(() => doc.uses.removeWhere((u) => u.id == lib.id));
    setState(() => _problem = null);
  }

  @override
  Widget build(BuildContext context) {
    final used = host.doc.use(lib.id) != null;
    final short = lib.id.split('/').last;
    return BeSheetFrame(
      key: ValueKey('be-lib-front-$short-sheet'),
      title: lib.name,
      hint: '应用自带的库，只读。${lib.summary}。',
      problem: _problem,
      children: [
        SwitchListTile(
          key: const ValueKey('be-lib-use'),
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
          title: const Text('在这份文档里用它'),
          subtitle: Text(used ? '它的积木在积木盒的「${lib.name}」那一页' : '打开以后，它的积木会出现在积木盒里'),
          value: used,
          onChanged: host.strictRules ? _toggle : null,
        ),
        BeSheetAdd(
          key: const ValueKey('be-lib-front-view'),
          label: '在画布上看（只读）',
          onTap: () {
            Navigator.pop(context);
            unawaited(showBeLibView(widget.from, title: lib.name, moduleText: lcFrontBuiltinModule(lib.id) ?? '', side: LibSide.frontend));
          },
        ),
        BeSheetSection('积木（${lib.blocks.length} 块）'),
        // 槽的名字是给程序看的英文短名，这里不念出来：只留一个空槽的样子，前后的字本身读得通。
        for (final b in lib.blocks) BeSheetRow(label: b.look.template.replaceAll(RegExp(r'\{[^{}]+\}'), '〔 〕'), muted: true),
      ],
    );
  }
}
