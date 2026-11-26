// 设计约束（后端积木·“模块”面板 + 一个模块的面板，390 宽，浅色 + 深色）— 2026-11-26
// - 内容排序：主＝模块的列表（一个一行：名字在左，右边小字说里面有几样、是不是入口）；
//   次＝模块顶上的变量（一个一行：名字、初值）；三＝“新建模块”“加一个变量”（强调色文字行，不用实心按钮——这里没有唯一的主操作）。
// - 一个模块的面板：名字、“从这里开始”（入口）开关；“用到了谁”一个模块一行勾选；“里面的东西”一样一行，右边开关＝公开；
//   挪到别的模块收进那一行的 ⋯；删除在最底下（文字按钮，危险色）。
// - 一行只做一件事。空状态：还没有模块时一句话说明“不分也行”，不出现空列表。
// - 颜色全取主题值；间距只用 Space 里的档。
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_core_edit.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_core_type_sheet.dart';
import 'package:lopicode/ui/backend_types_sheet.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// “模块”面板：模块的列表、模块顶上的变量。
Future<void> showBeModules(BuildContext context, BeBlockHost host) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ModulesSheet(host: host),
);

class _ModulesSheet extends StatefulWidget {
  const _ModulesSheet({required this.host});
  final BeBlockHost host;

  @override
  State<_ModulesSheet> createState() => _ModulesSheetState();
}

class _ModulesSheetState extends State<_ModulesSheet> {
  String? _problem;
  BeBlockHost get host => widget.host;

  void _do(String? Function(BeDocument doc) change) {
    String? bad;
    host.edit(() => bad = change(host.doc));
    setState(() => _problem = bad == null ? null : '$bad，没有改。');
  }

  Future<void> _global(String v, BeGlobal g) async {
    switch (v) {
      case 'init':
        final raw = await promptDialog(
          context,
          title: '「${g.name}」一开始是多少',
          initial: switch (g.init) {
            {'v': final Object v} => '$v',
            _ => '',
          },
          hint: '数字、文字，或者 是 / 否',
        );
        if (raw == null || !mounted) return;
        _do((d) {
          final x = beLiteralParse(raw);
          d.core.global(g.name)?.init = switch (x) {
            final bool b => exBool(b),
            final num n => exNum(n),
            final String s => exText(s),
            _ => exText(''),
          };
          return null;
        });
      case 'type':
        await showBeTypePicker(
          context,
          title: '「${g.name}」放什么',
          named: [for (final t in host.core.types) t.name],
          read: () => host.core.global(g.name)?.type,
          write: (t) => _do((d) {
            d.core.global(g.name)?.type = t;
            return null;
          }),
        );
        if (mounted) setState(() {});
      case 'const':
        _do((d) {
          final x = d.core.global(g.name);
          x?.isConst = !x.isConst;
          return null;
        });
      case 'remove':
        _do((d) {
          beRemoveGlobal(d, g.name);
          return null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = host.core;
    final c = context.colors;
    return BeSheetFrame(
      key: const ValueKey('be-modules'),
      title: '模块',
      hint: core.modules.isEmpty ? '东西多了可以分成几个模块：每个模块只让别人用它“公开”的东西，要用谁先勾上“用到了谁”。不分也行。' : null,
      problem: _problem,
      children: [
        if (core.modules.isNotEmpty) const BeSheetSection('模块'),
        for (final m in core.modules)
          BeSheetRow(
            key: ValueKey('be-module-${m.name}'),
            label: m.name,
            value: '${m.owns.length} 样东西${core.entryModule == m ? ' · 入口' : ''}',
            onTap: () async {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _ModuleSheet(host: host, name: m.name),
              );
              if (mounted) setState(() {});
            },
          ),
        BeSheetAdd(key: const ValueKey('be-module-add'), label: '新建模块', onTap: () => _do(beAddModule)),
        const BeSheetSection('模块顶上的变量（哪一串积木都看得见）'),
        for (final g in core.globals)
          BeSheetRow(
            key: ValueKey('be-global-${g.name}'),
            label: '${g.name}${g.isConst ? '（常量）' : ''}',
            value: '一开始 ${beLiteralShow(g.init)}',
            onTap: () async {
              final name = await promptDialog(context, title: '变量叫什么', initial: g.name);
              if (name == null || !mounted) return;
              _do((d) => beRenameGlobal(d, g.name, name));
            },
            trailing: PopupMenuButton<String>(
              key: ValueKey('be-global-more-${g.name}'),
              tooltip: '更多',
              icon: Icon(Icons.more_horiz_rounded, color: c.textMuted),
              onSelected: (v) => _global(v, g),
              itemBuilder: (_) => [
                PopupMenuItem(key: ValueKey('be-global-init-${g.name}'), value: 'init', child: const Text('一开始是多少…')),
                PopupMenuItem(key: ValueKey('be-global-type-${g.name}'), value: 'type', child: Text('放什么：${g.type?.show() ?? '没标'}')),
                PopupMenuItem(key: ValueKey('be-global-const-${g.name}'), value: 'const', child: Text(g.isConst ? '改成可以改的变量' : '设成常量（不能再改）')),
                PopupMenuItem(key: ValueKey('be-global-remove-${g.name}'), value: 'remove', child: const Text('删掉')),
              ],
            ),
          ),
        BeSheetAdd(key: const ValueKey('be-global-add'), label: '加一个变量', onTap: () => _do(beAddGlobal)),
        const SizedBox(height: Space.x3),
      ],
    );
  }
}

class _ModuleSheet extends StatefulWidget {
  const _ModuleSheet({required this.host, required this.name});
  final BeBlockHost host;
  final String name;

  @override
  State<_ModuleSheet> createState() => _ModuleSheetState();
}

class _ModuleSheetState extends State<_ModuleSheet> {
  String? _problem;
  late String _name = widget.name;
  BeBlockHost get host => widget.host;

  void _do(String? Function(BeDocument doc) change) {
    String? bad;
    host.edit(() => bad = change(host.doc));
    setState(() => _problem = bad == null ? null : '$bad，没有改。');
  }

  @override
  Widget build(BuildContext context) {
    final core = host.core;
    final m = core.module(_name);
    if (m == null) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final others = [
      for (final o in core.modules)
        if (o.name != m.name) o,
    ];
    final items = [
      for (final i in beModuleItems(host.doc))
        if (core.moduleOf(i.key) == m) i,
    ];
    return BeSheetFrame(
      key: const ValueKey('be-module-sheet'),
      title: '模块「${m.name}」',
      problem: _problem,
      children: [
        BeSheetRow(
          key: const ValueKey('be-module-name'),
          label: '名字',
          value: m.name,
          onTap: () async {
            final name = await promptDialog(context, title: '模块叫什么', initial: m.name);
            if (name == null || !mounted) return;
            final before = _name;
            _name = name.trim();
            _do((d) => beRenameModule(d, before, name));
            if (host.core.module(_name) == null) setState(() => _name = before);
          },
        ),
        SwitchListTile(
          key: const ValueKey('be-module-entry'),
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
          title: const Text('从这里开始'),
          subtitle: Text('“程序开始时”算在这个模块里；只能有一个', style: t.bodySmall?.copyWith(color: c.textMuted)),
          value: core.entryModule == m,
          onChanged: core.entryModule == m
              ? null
              : (_) => _do((d) {
                  d.core.entry = m.name;
                  return null;
                }),
        ),
        if (others.isNotEmpty) const BeSheetSection('用到了谁'),
        for (final o in others)
          CheckboxListTile(
            key: ValueKey('be-module-uses-${o.name}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
            controlAffinity: ListTileControlAffinity.trailing,
            title: Text(o.name),
            value: m.uses.contains(o.name),
            onChanged: (v) => _do((d) {
              final x = d.core.module(m.name);
              v == true ? x?.uses.add(o.name) : x?.uses.remove(o.name);
              return null;
            }),
          ),
        const BeSheetSection('里面的东西（开着＝公开，别的模块能用）'),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            child: Text('还没有东西。到别的模块里，点某样东西右边的 ⋯ 把它挪过来。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          ),
        for (final i in items)
          BeSheetRow(
            key: ValueKey('be-module-item-${i.name}'),
            label: i.name,
            value: i.what,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: ValueKey('be-module-public-${i.name}'),
                  value: core.publics.contains(i.key),
                  onChanged: (v) => _do((d) {
                    v ? d.core.publics.add(i.key) : d.core.publics.remove(i.key);
                    return null;
                  }),
                ),
                if (others.isNotEmpty)
                  PopupMenuButton<String>(
                    key: ValueKey('be-module-move-${i.name}'),
                    tooltip: '挪到别的模块',
                    icon: Icon(Icons.more_horiz_rounded, color: c.textMuted),
                    onSelected: (to) => _do((d) {
                      beMoveToModule(d, i.key, to);
                      return null;
                    }),
                    itemBuilder: (_) => [for (final o in others) PopupMenuItem(key: ValueKey('be-module-move-${i.name}-${o.name}'), value: o.name, child: Text('挪到「${o.name}」'))],
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.x4),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: TextButton(
              key: const ValueKey('be-module-delete'),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              onPressed: () {
                String? bad;
                host.edit(() => bad = beRemoveModule(host.doc, m.name));
                if (bad == null) {
                  Navigator.pop(context);
                } else {
                  setState(() => _problem = '$bad，没有删。');
                }
              },
              child: const Text('删掉这个模块（里面的东西归回入口模块）'),
            ),
          ),
        ),
      ],
    );
  }
}
