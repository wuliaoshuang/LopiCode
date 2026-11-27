// 设计约束（低代码 · 组件库面板 · 390×844）
// - 入口：搭建页 ⋮ ›“组件库”；选中一个自定义组件 › 更多 ›“存进库…”直接开“存进库”那一张表。
// - 底部面板，从上到下：标题 → 一句说明 → 主操作“把组件存成一个库”→ 次操作“从文件导入”→ 库的清单。
// - 清单一行一个库：名字在上，下面一行弱化的“标识 · 版本 · 几个组件 · 从哪来的”；动作都收进行尾“⋮”
//   （导出成文件、再存一版、看里面的组件、从项目里拿掉）。坏的库用警示色写一句原因。
// - “存进库”是一张表，一行一项：名字、标识、版本、作者、要放进去的组件（勾选）。标识写错当场说怎么写。
// - 导入一定先看预览（comp_lib_import_sheet.dart），点了头才落盘；导入以后把“重查”的结果说出来。
// - 库里的组件不能直接改：看定义里给“复制一份来改”。颜色全取主题值。
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_import_sheet.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/image_pick_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 文档里记“这个项目自己做了哪些库”的字段：`compLibs: {<标识>: {name, version, author, components: [组件 id]}}`。
const String kCompLibsAuthored = 'compLibs';

Map<String, Map<String, dynamic>> compLibsAuthored(LcDocument doc) {
  final raw = doc.more[kCompLibsAuthored];
  return {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String && kCompLibId.hasMatch(e.key as String) && e.value is Map) e.key as String: (e.value as Map).cast<String, dynamic>(),
  };
}

/// 组件库面板。[pickComponent]：一进来就开“存进库”，并且勾上这个组件。
Future<void> showCompLibSheet(BuildContext context, {required LcDocument Function() doc, required LcEdit onEdit, required LcImages images, String? pickComponent}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _LibSheet(doc: doc, onEdit: onEdit, images: images, pickComponent: pickComponent),
);

/// 预览要看的东西（和线 A 的公用预览页一个形状）。
CompLibImportView compLibImportView(CompLib lib) => CompLibImportView(
  name: lib.name,
  id: lib.id,
  version: lib.version,
  author: lib.author,
  side: '给前端用',
  hasSource: true,
  needs: [
    if (lib.images.isNotEmpty) '带着 ${lib.images.length} 张图片：${lib.images.keys.join('、')}',
    if (lib.missingImages.isNotEmpty) '有 ${lib.missingImages.length} 张图片没带上（导出时太大或找不到），用到的地方会是空的：${lib.missingImages.join('、')}',
    if (lib.themeVars.isNotEmpty) '用到 ${lib.themeVars.length} 个主题变量：项目里没有的会补上，已经有的用项目自己的',
    if (lib.hasLogic) '组件里带着事件、状态或绑定（只是设置，不是手写代码）',
    '没有手写代码',
  ],
  items: [
    for (final d in lib.defs)
      '${d.name}　${[if (d.props.isNotEmpty) '${d.props.length} 个属性', if (d.slots.isNotEmpty) '${d.slots.length} 个插槽', if (lcCompEvents(d).isNotEmpty) '${lcCompEvents(d).length} 个事件', if (lcVariants(d).isNotEmpty) '${lcVariants(d).length} 个变体'].join(' · ')}',
  ],
  problems: lib.problems,
);

class _LibSheet extends StatefulWidget {
  const _LibSheet({required this.doc, required this.onEdit, required this.images, this.pickComponent});
  final LcDocument Function() doc;
  final LcEdit onEdit;
  final LcImages images;
  final String? pickComponent;

  @override
  State<_LibSheet> createState() => _LibSheetState();
}

class _LibSheetState extends State<_LibSheet> {
  List<CompStoredLib>? _libs;

  LcDocument get _doc => widget.doc();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted && widget.pickComponent != null) _save(pick: widget.pickComponent);
    });
  }

  Future<void> _load() async {
    final libs = await compLibsRead(widget.images.guard);
    if (mounted) setState(() => _libs = libs);
  }

  void _filesChanged() => widget.images.onImported?.call();

  /// 存成一个库 / 再存一版。
  Future<void> _save({String? pick, String? again}) async {
    final authored = compLibsAuthored(_doc);
    final old = again == null ? null : authored[again];
    final own = [
      for (final d in _doc.components)
        if (compLibOf(d) == null) d,
    ];
    if (own.isEmpty) {
      await tellComponentProblem(context, '项目里还没有自己做的组件。先在画布上选中一个控件 → 更多 → 存成组件。');
      return;
    }
    final oldIds = old?['components'];
    final form = await showDialog<_LibFormResult>(
      context: context,
      builder: (_) => _LibForm(
        own: own,
        picked: {?pick, if (oldIds is List) ...oldIds.whereType<String>(), if (pick == null && oldIds is! List) ...own.map((d) => d.id)},
        id: again ?? '',
        lockId: again != null,
        name: old?['name'] is String ? old!['name'] as String : '',
        version: _nextVersion(old?['version']),
        author: old?['author'] is String ? old!['author'] as String : '',
        taken: {
          for (final s in _libs ?? const <CompStoredLib>[])
            if (s.id != again) s.id,
        },
      ),
    );
    if (form == null || !mounted) return;
    final guard = widget.images.guard;
    final lib = compLibFromDoc(_doc, form.components, id: form.id, name: form.name, version: form.version, author: form.author, readImage: (rel) => compLibReadImage(guard, rel));
    final problem = await compLibStore(guard, lib);
    if (!mounted) return;
    if (problem != null) {
      await tellComponentProblem(context, problem);
      return;
    }
    widget.onEdit((d) {
      d.more[kCompLibsAuthored] = {
        ...compLibsAuthored(d),
        form.id: {'name': form.name, 'version': form.version, 'author': form.author, 'components': form.components.toList()},
      };
    });
    _filesChanged();
    await _load();
    if (!mounted) return;
    showSnack(context, '已存成库「${form.name}」${form.version}（${lib.defs.length} 个组件${lib.missingImages.isEmpty ? '' : '，有 ${lib.missingImages.length} 张图片没带上'}）');
  }

  String _nextVersion(Object? v) {
    final m = v is String ? RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v) : null;
    return m == null ? '1.0.0' : '${m[1]}.${m[2]}.${int.parse(m[3]!) + 1}';
  }

  Future<void> _export(CompStoredLib lib) async {
    final r = await compLibExport(widget.images.guard, lib);
    if (!mounted) return;
    _filesChanged();
    if (r.problem != null) {
      await tellComponentProblem(context, r.problem!);
    } else {
      await tellComponentProblem(context, '已导出到项目的 ${r.rel}。\n\n把这个文件发给别人，或者拷进另一个项目，在那边的“组件库 › 从文件导入”里选它。');
    }
  }

  Future<void> _import() async {
    final guard = widget.images.guard;
    final files = await compLibPackFiles(guard);
    if (!mounted) return;
    if (files.isEmpty) {
      await tellComponentProblem(context, '项目里没有能导入的文件。\n\n把别人给的 .lopilib 文件放进项目的根目录或 exports 文件夹（文件页里可以粘贴、移动），再回来点这里。');
      return;
    }
    final rel = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选一个文件'),
        children: [for (final f in files) SimpleDialogOption(key: ValueKey('complib-file-$f'), onPressed: () => Navigator.pop(context, f), child: Text(f))],
      ),
    );
    if (rel == null || !mounted) return;
    final opened = await compLibOpenPack(guard, rel, installed: _libs ?? const []);
    if (!mounted) return;
    final lib = opened.lib;
    final had = (_libs ?? const <CompStoredLib>[]).any((s) => s.id == lib.id);
    final go = await showCompLibImport(
      context,
      compLibImportView(lib),
      title: had ? '更新组件库' : '导入组件库',
      action: had ? '更新' : '导入',
      hint: had ? '项目里已经有这个库了。更新以后，用着它的页面会重查一遍，对不上的地方会告诉你。' : '导入以后，库里的组件会出现在组件盒“我的”里它自己那一组。库里的东西只是设置，不会运行任何代码。',
    );
    if (!go || !mounted) return;
    final problem = await compLibStore(guard, lib, from: 'file');
    if (!mounted) return;
    if (problem != null) {
      await tellComponentProblem(context, problem);
      return;
    }
    final wrote = await compLibWriteImages(guard, lib);
    var notes = const <String>[];
    widget.onEdit((d) => notes = compLibInstall(d, lib));
    _filesChanged();
    await _load();
    if (!mounted) return;
    if (notes.isEmpty) {
      showSnack(context, '已${had ? '更新' : '导入'}「${lib.name}」${lib.version}${wrote == 0 ? '' : '，带进来 $wrote 张图片'}');
    } else {
      await tellComponentProblem(context, '已更新「${lib.name}」${lib.version}。重查发现 ${notes.length} 处对不上：\n\n${notes.take(8).map((n) => '· $n').join('\n')}${notes.length > 8 ? '\n……' : ''}');
    }
  }

  Future<void> _use(CompStoredLib lib) async {
    var notes = const <String>[];
    widget.onEdit((d) => notes = compLibInstall(d, lib.lib));
    await compLibWriteImages(widget.images.guard, lib.lib);
    if (!mounted) return;
    setState(() {});
    showSnack(context, notes.isEmpty ? '「${lib.name}」的组件已放进组件盒“我的”' : '已放进组件盒；有 ${notes.length} 处对不上');
  }

  Future<void> _remove(CompStoredLib lib) async {
    final ok = await confirmDialog(context, title: '从项目里拿掉「${lib.name}」', message: '库的文件夹会删掉。页面上还在用的组件会留下来，变成项目自己的组件；没人用的一起删。导出过的文件不动。', confirmLabel: '拿掉', danger: true);
    if (!ok || !mounted) return;
    await compLibDelete(widget.images.guard, lib.id);
    widget.onEdit((d) {
      compLibRemoveFromDoc(d, lib.id);
      d.more[kCompLibsAuthored] = compLibsAuthored(d)..remove(lib.id);
      if ((d.more[kCompLibsAuthored] as Map).isEmpty) d.more.remove(kCompLibsAuthored);
    });
    _filesChanged();
    await _load();
  }

  Future<void> _peek(CompStoredLib lib) async {
    final installed = compLibsInDoc(_doc).containsKey(lib.id);
    final forked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LibPeek(lib: lib, installed: installed),
    );
    if (forked == null || !mounted) return;
    String? made;
    widget.onEdit((d) {
      if (!compLibsInDoc(d).containsKey(lib.id)) compLibInstall(d, lib.lib);
      made = compLibFork(d, compLibDefId(lib.id, forked));
    });
    setState(() {});
    showSnack(context, made == null ? '没复制成' : '已复制成项目自己的组件，在“自定义组件”里能改');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final libs = _libs;
    final authored = compLibsAuthored(_doc), inDoc = compLibsInDoc(_doc);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        key: const ValueKey('complib-sheet'),
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
            child: Text('组件库', style: t.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: Text('把自己做的组件收成一个库，导出成一个文件，别的项目导入就能用。', style: t.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: FilledButton.icon(key: const ValueKey('complib-new'), onPressed: _save, icon: const Icon(Icons.inventory_2_outlined, size: 18), label: const Text('把组件存成一个库')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: OutlinedButton.icon(key: const ValueKey('complib-import-open'), onPressed: _import, icon: const Icon(Icons.file_open_outlined, size: 18), label: const Text('从文件导入')),
          ),
          if (libs == null)
            const Padding(
              padding: EdgeInsets.all(Space.x6),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (libs.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x6, Space.x4, Space.x4),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 36, color: c.textFaint),
                  const SizedBox(height: Space.x2),
                  Text('项目里还没有组件库', style: t.titleSmall),
                  const SizedBox(height: Space.x1),
                  Text('自己做的组件存成库，或者导入别人给的 .lopilib 文件', style: t.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          for (final lib in libs ?? const <CompStoredLib>[])
            ListTile(
              key: ValueKey('complib-item-${lib.id}'),
              contentPadding: const EdgeInsets.only(left: Space.x4, right: Space.x1),
              leading: Icon(Icons.inventory_2_outlined, color: lib.ok ? c.accent : c.warning),
              title: Text(lib.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                lib.ok
                    ? '${lib.id} · ${lib.lib.version} · ${lib.lib.defs.length} 个组件 · ${authored.containsKey(lib.id) ? '这个项目做的' : (inDoc.containsKey(lib.id) ? '导入的，在用' : '导入的，还没放进组件盒')}'
                    : (lib.problem ?? '这个库有问题'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: lib.ok ? null : t.bodySmall?.copyWith(color: c.warning),
              ),
              trailing: PopupMenuButton<String>(
                key: ValueKey('complib-menu-${lib.id}'),
                tooltip: '${lib.name} 的更多操作',
                onSelected: (v) => switch (v) {
                  'export' => _export(lib),
                  'again' => _save(again: lib.id),
                  'peek' => _peek(lib),
                  'use' => _use(lib),
                  _ => _remove(lib),
                },
                itemBuilder: (_) => [
                  if (lib.ok) const PopupMenuItem(value: 'export', child: Text('导出成文件')),
                  if (lib.ok && authored.containsKey(lib.id)) const PopupMenuItem(value: 'again', child: Text('再存一版')),
                  if (lib.ok) const PopupMenuItem(value: 'peek', child: Text('看里面的组件')),
                  if (lib.ok && !authored.containsKey(lib.id)) PopupMenuItem(value: 'use', child: Text(inDoc.containsKey(lib.id) ? '重新放进组件盒' : '放进组件盒')),
                  const PopupMenuItem(value: 'remove', child: Text('从项目里拿掉')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 看一个库里有什么；点“复制一份来改”返回那个组件在库里的 id。
class _LibPeek extends StatelessWidget {
  const _LibPeek({required this.lib, required this.installed});
  final CompStoredLib lib;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    String line(LcComponentDef d) => [
      '属性：${d.props.isEmpty ? '没有' : d.props.map((p) => p.name).join('、')}',
      '插槽：${d.slots.isEmpty ? '没有' : d.slots.map((s) => s.label).join('、')}',
      '事件：${lcCompEvents(d).isEmpty ? '没有' : lcCompEvents(d).map((e) => e.label).join('、')}',
      '变体：${lcVariants(d).isEmpty ? '没有' : lcVariants(d).map((v) => v.label).join('、')}',
    ].join('\n');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        key: const ValueKey('complib-peek'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x6),
        children: [
          Text(lib.name, style: t.titleLarge),
          Text('${lib.id} · ${lib.lib.version}${lib.lib.author.isEmpty ? '' : ' · ${lib.lib.author}'} · 给前端用', style: t.bodySmall?.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.x2),
          Text('库里的组件不能直接改。要改就“复制一份来改”：副本是项目自己的组件，和库不再有关系。', style: t.bodySmall),
          for (final d in lib.lib.defs) ...[
            const SizedBox(height: Space.x4),
            Text(d.name, style: t.titleSmall),
            const SizedBox(height: 2),
            Text(line(d), style: t.bodySmall?.copyWith(color: c.textMuted)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(key: ValueKey('complib-fork-${d.id}'), onPressed: () => Navigator.pop(context, d.id), child: const Text('复制一份来改')),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibFormResult {
  const _LibFormResult(this.id, this.name, this.version, this.author, this.components);
  final String id, name, version, author;
  final Set<String> components;
}

class _LibForm extends StatefulWidget {
  const _LibForm({required this.own, required this.picked, required this.id, required this.lockId, required this.name, required this.version, required this.author, required this.taken});
  final List<LcComponentDef> own;
  final Set<String> picked, taken;
  final String id, name, version, author;
  final bool lockId;

  @override
  State<_LibForm> createState() => _LibFormState();
}

class _LibFormState extends State<_LibForm> {
  late final _name = TextEditingController(text: widget.name);
  late final _id = TextEditingController(text: widget.id);
  late final _version = TextEditingController(text: widget.version);
  late final _author = TextEditingController(text: widget.author);
  late final Set<String> _picked = {...widget.picked};
  String? _error;

  @override
  void dispose() {
    for (final x in [_name, _id, _version, _author]) {
      x.dispose();
    }
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim(), id = _id.text.trim(), version = _version.text.trim();
    final error = name.isEmpty
        ? '给库起个名字'
        : name.length > 40
        ? '名字最多 40 个字'
        : !kCompLibId.hasMatch(id)
        ? '标识要写成“作者段/库名”：小写字母、数字、连字符，字母开头，比如 shuang/shop'
        : compLibAuthorReserved(id.split('/').first)
        ? '作者段 lopi、local 是应用自己留着用的，换一个'
        : widget.taken.contains(id)
        ? '项目里已经有一个标识是 $id 的库了'
        : !kCompLibVersion.hasMatch(version)
        ? '版本号要写成 1.0.0 这样'
        : _picked.isEmpty
        ? '至少勾一个组件'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _LibFormResult(id, name, version, _author.text.trim(), _picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget field(String key, String label, TextEditingController ctl, {String? hint, bool enabled = true}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: TextField(
        key: ValueKey('complib-form-$key'),
        controller: ctl,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      ),
    );
    return AlertDialog(
      title: Text(widget.lockId ? '再存一版' : '存成一个库'),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            field('name', '名字', _name, hint: '比如 商城组件'),
            field('id', '标识（作者段/库名）', _id, hint: 'shuang/shop', enabled: !widget.lockId),
            field('version', '版本', _version, hint: '1.0.0'),
            field('author', '作者（可不填）', _author),
            Text('放进去的组件', style: t.labelMedium?.copyWith(color: c.textMuted)),
            for (final d in widget.own)
              CheckboxListTile(
                key: ValueKey('complib-form-pick-${d.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picked.contains(d.id),
                title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onChanged: (v) => setState(() => v == true ? _picked.add(d.id) : _picked.remove(d.id)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: Text(
                  _error!,
                  key: const ValueKey('complib-form-error'),
                  style: t.bodySmall?.copyWith(color: c.warning),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(key: const ValueKey('complib-form-done'), onPressed: _done, child: const Text('存')),
      ],
    );
  }
}
