// 设计约束（后端积木·一个类型的面板 + 一个方法的面板，390 宽，浅色 + 深色）— 2026-11-26
// - 内容排序：主＝这个类型里的东西（字段 / 情况 / 方法，一样一行）；次＝名字、父类、能不能被继承、实现的接口；
//   三＝删除（文字按钮，危险色，放最底下，不抢眼）。类只有一个主操作：“打开它的画布”（实心按钮）。
// - 一行只做一件事：点行＝改名（字段、情况）或进下一层（方法）；右边的类型是一个单独能点的小按钮；其余的收进 ⋯。
// - 分组：每一组上面一个小标题；组和组之间的空比组里行和行之间大。
// - 改不了的时候（重名、名字不合规矩）面板顶上出一行说明，不弹出去。
// - 颜色全取主题值；间距只用 Space 里的档。
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_core_edit.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_types_sheet.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 默认值 / 初值怎么给人看。
String beLiteralShow(Object? v) => switch (v) {
  null => '没有',
  true => '是',
  false => '否',
  final String s => '“$s”',
  final num n => '$n',
  {'e': 'text', 'v': final String s} => '“$s”',
  {'e': 'num', 'v': final num n} => '$n',
  {'e': 'bool', 'v': final bool b} => b ? '是' : '否',
  _ => '（搭出来的值）',
};

/// 人敲的一行字 → 默认值：空＝没有；是 / 否；数字；别的当文字。
Object? beLiteralParse(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s == '是' || s == 'true') return true;
  if (s == '否' || s == 'false') return false;
  final n = num.tryParse(s);
  if (n != null && n.isFinite) return n;
  return s.length >= 2 && ((s.startsWith('“') && s.endsWith('”')) || (s.startsWith('"') && s.endsWith('"'))) ? s.substring(1, s.length - 1) : s;
}

String _sig(BeMethod m) => '（${m.params.map((p) => p.name).join('、')}）${m.returns == null ? '' : ' → ${m.returns!.show()}'}';

/// 一个类型的面板。点了“打开它的画布”返回 true（已经进了那个类的画布）。
Future<bool> showBeCoreType(BuildContext context, BeBlockHost host, String typeId) async {
  final went = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => _TypeSheet(host: host, typeId: typeId),
  );
  return went == true;
}

class _TypeSheet extends StatefulWidget {
  const _TypeSheet({required this.host, required this.typeId});
  final BeBlockHost host;
  final String typeId;

  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  String? _problem;

  BeBlockHost get host => widget.host;
  String get id => widget.typeId;

  /// 做一件改动（一条撤销记录）；改不了把原因显示在面板顶上。
  void _do(String? Function(BeDocument doc) change) {
    String? bad;
    host.edit(() => bad = change(host.doc));
    setState(() => _problem = bad == null ? null : '$bad，没有改。');
  }

  Future<void> _rename(String title, String now, String? Function(BeDocument doc, String name) apply) async {
    final name = await promptDialog(context, title: title, initial: now);
    if (name == null || !mounted || name.trim() == now) return;
    _do((d) => apply(d, name));
  }

  List<String> get _named => [for (final t in host.core.types) t.name];

  Future<void> _fieldType(BeField f) async {
    await showBeTypePicker(
      context,
      title: '「${f.name}」放什么',
      allowNone: false,
      named: _named,
      read: () => f.type,
      write: (v) => _do((d) {
        final t = d.core.type(id);
        for (final x in [...?t?.fields, for (final c in t?.cases ?? const <BeCase>[]) ...c.fields]) {
          if (x.name == f.name && x.type == f.type) {
            x.type = v ?? LType.any;
            f = x;
            break;
          }
        }
        return null;
      }),
    );
    if (mounted) setState(() {});
  }

  Widget _field(BeTypeDef t, BeField f, {String? inCase}) {
    final key = inCase == null ? f.name : '$inCase.${f.name}';
    final klass = t.kind == BeTypeKind.klass;
    return BeSheetRow(
      key: ValueKey('be-core-field-$key'),
      label: '${f.name}${f.isStatic ? '（类本身的）' : ''}${f.isPrivate ? '（内部）' : ''}',
      indent: inCase != null,
      onTap: () => _rename('字段叫什么', f.name, (d, n) => beRenameField(d, id, f.name, n, inCase: inCase)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(key: ValueKey('be-core-field-type-$key'), onPressed: () => _fieldType(f), child: Text(f.type.show())),
          PopupMenuButton<String>(
            key: ValueKey('be-core-field-more-$key'),
            tooltip: '更多',
            icon: Icon(Icons.more_horiz_rounded, color: context.colors.textMuted),
            onSelected: (v) => _do((d) {
              final x = [...?d.core.type(id)?.fields].where((x) => x.name == f.name).firstOrNull;
              switch (v) {
                case 'private':
                  x?.isPrivate = !x.isPrivate;
                case 'static':
                  x?.isStatic = !x.isStatic;
                case 'remove':
                  return beRemoveField(d, id, f.name, inCase: inCase);
              }
              return null;
            }),
            itemBuilder: (_) => [
              if (klass) PopupMenuItem(key: ValueKey('be-core-field-private-$key'), value: 'private', child: Text(f.isPrivate ? '改成外面也能用' : '设成“内部”（只有类里面能用）')),
              if (klass) PopupMenuItem(key: ValueKey('be-core-field-static-$key'), value: 'static', child: Text(f.isStatic ? '改成每个对象各有一份' : '设成“类本身的”（大家共用一份）')),
              PopupMenuItem(key: ValueKey('be-core-field-remove-$key'), value: 'remove', child: const Text('删掉')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _case(BeTypeDef t, BeCase cs) => BeSheetRow(
    key: ValueKey('be-core-case-${cs.name}'),
    label: cs.name,
    onTap: () => _rename('这种情况叫什么', cs.name, (d, n) => beRenameCase(d, id, cs.name, n)),
    trailing: IconButton(
      key: ValueKey('be-core-case-remove-${cs.name}'),
      tooltip: '删掉这种情况',
      onPressed: () => _do((d) => beRemoveCase(d, id, cs.name)),
      icon: Icon(Icons.close_rounded, size: 20, color: context.colors.textMuted),
    ),
  );

  Future<void> _pickParent(BeTypeDef t) async {
    final options = t.kind == BeTypeKind.error
        ? [
            for (final k in host.core.errorKinds)
              if (k != t.name) k,
          ]
        : [
            for (final o in host.core.types)
              if (o.kind == BeTypeKind.klass && o.id != t.id) o.name,
            ...kErrBuiltinNames,
          ];
    final picked = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        key: const ValueKey('be-core-parents'),
        title: const Text('父类是谁'),
        children: [
          if (t.kind == BeTypeKind.klass) SimpleDialogOption(key: const ValueKey('be-core-parent-none'), onPressed: () => Navigator.pop(dialog, ''), child: const Text('不继承')),
          for (final o in options) SimpleDialogOption(key: ValueKey('be-core-parent-$o'), onPressed: () => Navigator.pop(dialog, o), child: Text(o)),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _do((d) => beSetParent(d, id, picked.isEmpty ? null : picked));
  }

  Future<void> _method(BeMethod m) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MethodSheet(host: host, typeId: id, methodId: m.id),
    );
    if (mounted) setState(() {});
  }

  void _addMethod({BeMethod? like}) {
    BeMethod? made;
    host.edit(() => made = beAddMethod(host.doc, id, like: like));
    setState(() => _problem = made == null ? '方法最多 $kBeMaxMembers 个，没有加。' : null);
  }

  @override
  Widget build(BuildContext context) {
    final t = host.core.type(id);
    if (t == null) return const SizedBox.shrink();
    final c = context.colors;
    final klass = t.kind == BeTypeKind.klass;
    final interfaces = [
      for (final o in host.core.types)
        if (o.kind == BeTypeKind.interface) o,
    ];
    final copy = klass ? beInheritable(host.core, t) : const <(BeMethod, String)>[];
    return BeSheetFrame(
      key: const ValueKey('be-core-type-sheet'),
      title: '${t.kind.label}「${t.name}」',
      problem: _problem,
      footer: klass
          ? FilledButton(
              key: const ValueKey('be-core-open-canvas'),
              onPressed: () {
                host.openCanvas(id);
                Navigator.pop(context, true);
              },
              child: const Text('打开它的画布'),
            )
          : null,
      children: [
        BeSheetRow(key: const ValueKey('be-core-name'), label: '名字', value: t.name, onTap: () => _rename('${t.kind.label}叫什么', t.name, (d, n) => beRenameType(d, id, n))),
        if (t.isClassLike) BeSheetRow(key: const ValueKey('be-core-parent'), label: '父类', value: t.parent ?? '不继承', onTap: () => _pickParent(t)),
        if (klass)
          SwitchListTile(
            key: const ValueKey('be-core-open'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
            title: const Text('可以被继承'),
            value: t.isOpen,
            onChanged: (v) => _do((d) {
              d.core.type(id)?.isOpen = v;
              return null;
            }),
          ),
        if (klass && interfaces.isNotEmpty) ...[
          const BeSheetSection('实现的接口'),
          for (final i in interfaces)
            CheckboxListTile(
              key: ValueKey('be-core-iface-${i.name}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(i.name),
              value: t.interfaces.contains(i.name),
              onChanged: (v) => _do((d) {
                final x = d.core.type(id);
                v == true ? x?.interfaces.add(i.name) : x?.interfaces.remove(i.name);
                return null;
              }),
            ),
        ],
        if (t.kind == BeTypeKind.record || t.isClassLike) ...[
          BeSheetSection(t.kind == BeTypeKind.error ? '多带的东西（消息和种类本来就有）' : '字段'),
          for (final f in t.fields) _field(t, f),
          BeSheetAdd(key: const ValueKey('be-core-add-field'), label: '加一个字段', onTap: () => _do((d) => beAddField(d, id))),
        ],
        if (t.kind == BeTypeKind.enumeration || t.kind == BeTypeKind.variant) ...[
          const BeSheetSection('情况'),
          for (final cs in t.cases) ...[
            _case(t, cs),
            if (t.kind == BeTypeKind.variant) ...[
              for (final f in cs.fields) _field(t, f, inCase: cs.name),
              BeSheetAdd(
                key: ValueKey('be-core-add-field-${cs.name}'),
                label: '给「${cs.name}」加一样带的东西',
                indent: true,
                onTap: () => _do((d) => beAddField(d, id, toCase: cs.name)),
              ),
            ],
          ],
          BeSheetAdd(key: const ValueKey('be-core-add-case'), label: '加一种情况', onTap: () => _do((d) => beAddCase(d, id))),
        ],
        if (klass || t.kind == BeTypeKind.interface) ...[
          BeSheetSection(klass ? '创建时和方法（积木在它的画布里搭）' : '要有哪些方法'),
          if (klass)
            if (t.ctor case final ctor?)
              BeSheetRow(key: const ValueKey('be-core-ctor'), label: '创建时', value: _sig(ctor), onTap: () => _method(ctor))
            else
              BeSheetAdd(key: const ValueKey('be-core-add-ctor'), label: '加上“创建时”', onTap: () => _do((d) => beAddCtor(d, id) == null ? '加不了' : null)),
          for (final m in t.methods) BeSheetRow(key: ValueKey('be-core-method-${m.name}'), label: '${m.name}${m.isStatic ? '（类本身的）' : ''}', value: _sig(m), onTap: () => _method(m)),
          BeSheetAdd(key: const ValueKey('be-core-add-method'), label: '加一个方法', onTap: _addMethod),
        ],
        if (copy.isNotEmpty) ...[
          const BeSheetSection('照抄上面的签名（重写 / 实现时名字、参数、默认值都要一样）'),
          for (final (m, from) in copy)
            BeSheetRow(
              key: ValueKey('be-core-copy-${m.name}'),
              label: '${m.name}${_sig(m)}',
              value: from,
              onTap: () => _addMethod(like: m),
              trailing: Padding(
                padding: const EdgeInsets.only(right: Space.x3),
                child: Icon(Icons.content_copy_rounded, size: 18, color: c.accent),
              ),
            ),
        ],
        const SizedBox(height: Space.x4),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: TextButton(
              key: const ValueKey('be-core-delete'),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              onPressed: () {
                if (host.canvasType?.id == id) host.openCanvas(null);
                host.edit(() => beRemoveType(host.doc, id));
                Navigator.pop(context, false);
              },
              child: Text('删掉这个${t.kind.label}'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 一个方法（或“创建时”、接口里的一行签名）：名字、参数、交回什么。
class _MethodSheet extends StatefulWidget {
  const _MethodSheet({required this.host, required this.typeId, required this.methodId});
  final BeBlockHost host;
  final String typeId;
  final String methodId;

  @override
  State<_MethodSheet> createState() => _MethodSheetState();
}

class _MethodSheetState extends State<_MethodSheet> {
  String? _problem;
  BeBlockHost get host => widget.host;
  String get id => widget.methodId;

  void _do(String? Function(BeDocument doc) change) {
    String? bad;
    host.edit(() => bad = change(host.doc));
    setState(() => _problem = bad == null ? null : '$bad，没有改。');
  }

  BeParam? _param(BeDocument d, String name) => beMethodById(d, id)?.params.where((p) => p.name == name).firstOrNull;

  Future<void> _paramMenu(String v, BeParam p) async {
    switch (v) {
      case 'default':
        final raw = await promptDialog(context, title: '「${p.name}」的默认值', initial: p.defaultValue == null ? '' : '${p.defaultValue}', hint: '留空＝没有默认值（调用时必须给）');
        if (raw == null || !mounted) return;
        _do((d) {
          _param(d, p.name)?.defaultValue = beLiteralParse(raw);
          return null;
        });
      case 'remove':
        _do((d) {
          beMethodById(d, id)?.params.removeWhere((x) => x.name == p.name);
          return null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = host.core.type(widget.typeId);
    final m = beMethodById(host.doc, id);
    if (t == null || m == null) return const SizedBox.shrink();
    final c = context.colors;
    final ctor = identical(t.ctor, m);
    final named = [for (final x in host.core.types) x.name];
    return BeSheetFrame(
      key: const ValueKey('be-core-method-sheet'),
      title: ctor ? '「${t.name}」的创建时' : '方法「${m.name}」',
      hint: ctor ? '“新建 ${t.name}”的时候跑这一段；参数就是新建时要给的东西。' : null,
      problem: _problem,
      children: [
        if (!ctor)
          BeSheetRow(
            key: const ValueKey('be-core-method-name'),
            label: '名字',
            value: m.name,
            onTap: () async {
              final name = await promptDialog(context, title: '方法叫什么', initial: m.name);
              if (name == null || !mounted) return;
              _do((d) => beRenameMethod(d, id, name));
            },
          ),
        const BeSheetSection('参数'),
        for (final p in m.params)
          BeSheetRow(
            key: ValueKey('be-core-param-${p.name}'),
            label: p.defaultValue == null ? p.name : '${p.name}（默认 ${beLiteralShow(p.defaultValue)}）',
            onTap: () async {
              final name = await promptDialog(context, title: '参数叫什么', initial: p.name);
              if (name == null || !mounted) return;
              _do((d) => beRenameParam(d, id, p.name, name));
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: ValueKey('be-core-param-type-${p.name}'),
                  onPressed: () async {
                    await showBeTypePicker(
                      context,
                      title: '参数「${p.name}」放什么',
                      named: named,
                      read: () => _param(host.doc, p.name)?.type,
                      write: (v) => _do((d) {
                        _param(d, p.name)?.type = v;
                        return null;
                      }),
                    );
                    if (mounted) setState(() {});
                  },
                  child: Text(p.type?.show() ?? '没标'),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('be-core-param-more-${p.name}'),
                  tooltip: '更多',
                  icon: Icon(Icons.more_horiz_rounded, color: c.textMuted),
                  onSelected: (v) => _paramMenu(v, p),
                  itemBuilder: (_) => [
                    PopupMenuItem(key: ValueKey('be-core-param-default-${p.name}'), value: 'default', child: const Text('默认值…')),
                    PopupMenuItem(key: ValueKey('be-core-param-remove-${p.name}'), value: 'remove', child: const Text('删掉')),
                  ],
                ),
              ],
            ),
          ),
        BeSheetAdd(key: const ValueKey('be-core-add-param'), label: '加一个参数', onTap: () => _do((d) => beAddParam(d, id))),
        if (!ctor) ...[
          const BeSheetSection('结果'),
          BeSheetRow(
            key: const ValueKey('be-core-returns'),
            label: '交回什么',
            value: m.returns?.show() ?? '没标',
            onTap: () async {
              await showBeTypePicker(
                context,
                title: '「${m.name}」交回什么',
                named: named,
                read: () => beMethodById(host.doc, id)?.returns,
                write: (v) => _do((d) {
                  beMethodById(d, id)?.returns = v;
                  return null;
                }),
              );
              if (mounted) setState(() {});
            },
          ),
          if (t.kind == BeTypeKind.klass)
            SwitchListTile(
              key: const ValueKey('be-core-static'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
              title: const Text('类本身的'),
              subtitle: Text('不用先新建对象，直接“${t.name} 的 ${m.name}”', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted)),
              value: m.isStatic,
              onChanged: (v) => _do((d) {
                beMethodById(d, id)?.isStatic = v;
                return null;
              }),
            ),
        ],
        const SizedBox(height: Space.x4),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: TextButton(
              key: const ValueKey('be-core-method-delete'),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              onPressed: () {
                host.edit(() => beRemoveCoreTree(host.doc, id));
                Navigator.pop(context);
              },
              child: Text(ctor ? '删掉“创建时”' : '删掉这个方法'),
            ),
          ),
        ),
      ],
    );
  }
}
