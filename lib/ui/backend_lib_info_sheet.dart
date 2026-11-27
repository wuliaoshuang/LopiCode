// 设计约束（后端积木·“这个库”面板 + 一块库积木的面板，390 宽，浅色 + 深色）— 2026-11-27
// - 只有库文档才有这个面板。它回答：这个库叫什么、公开了哪些积木、有哪些设置项。
// - “这个库”：主＝“公开成积木”的列表（库里每个函数、每个类的方法各一行，右边小字说公开了没有、用的哪种办法）；
//   次＝设置项（一项一行）、库的信息（版本、作者、介绍，各一行，点开改）。没有唯一的主操作，新增用强调色文字行。
// - 一块库积木的面板：最上面一行开关“公开成积木”（主操作）；打开以后才出现下面的：办法、形状、积木上的字、
//   每个参数从哪来（一个参数一行）、“放进变量”的槽、口、递给口里的东西。一行只做一件事，选项多的收进弹出的小菜单。
// - 出不了库文件的原因（重名、递归展开、同一个槽写两次…）在面板顶上用一块提示说出来，和问题列表里的是同一句。
// - 颜色全取主题值；间距只用 Space 里的档。
import 'dart:async';

import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// “这个库”面板（库文档的“更多”里）。
Future<void> showBeLibInfo(BuildContext context, BeBlockHost host) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _InfoSheet(host: host),
);

String _howWord(LibHow how) => switch (how) {
  LibHow.call => '调用它',
  LibHow.expand => '原地展开',
  LibHow.method => '对象的方法',
  LibHow.static => '类自己的方法',
};

Future<T?> _pick<T>(BuildContext context, String title, List<(T, String, String)> options) => showDialog<T>(
  context: context,
  builder: (dialog) => SimpleDialog(
    title: Text(title),
    children: [
      for (final (value, label, hint) in options)
        SimpleDialogOption(
          key: ValueKey('be-pick-$label'),
          onPressed: () => Navigator.pop(dialog, value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (hint.isNotEmpty) Text(hint, style: Theme.of(dialog).textTheme.bodySmall?.copyWith(color: dialog.colors.textMuted)),
            ],
          ),
        ),
    ],
  ),
);

class _InfoSheet extends StatefulWidget {
  const _InfoSheet({required this.host});
  final BeBlockHost host;

  @override
  State<_InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<_InfoSheet> {
  String? _problem;
  BeBlockHost get host => widget.host;
  BeLibInfo get info => host.doc.library!;

  void _do(void Function() change) {
    host.edit(change);
    setState(() => _problem = null);
  }

  Future<void> _text(String title, String now, void Function(String v) write, {String? hint}) async {
    final v = await promptDialog(context, title: title, initial: now, hint: hint);
    if (v == null || !mounted) return;
    _do(() => write(v.trim()));
  }

  Future<void> _open(BeLibDef? def, {BeFunction? fn, BeTypeDef? type, BeMethod? method}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DefSheet(host: host, fn: fn, type: type, method: method),
    );
    if (mounted) setState(() {});
  }

  Future<void> _addSetting() async {
    final name = await promptDialog(context, title: '设置项叫什么', hint: '给用这个库的人看的名字，比如 每页几条');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final kind = await _pick<String>(context, '它是什么', const [('整数', '数', '比如 10'), ('文字', '文字', '比如 你好'), ('是否', '是 / 否', '')]);
    if (kind == null || !mounted) return;
    final raw = await promptDialog(context, title: '没人改的时候是多少', hint: kind == '是否' ? '是 或 否' : (kind == '整数' ? '一个数' : '一段文字'));
    if (raw == null || !mounted) return;
    final text = raw.trim();
    final Object? value = kind == '整数' ? int.tryParse(text) : (kind == '是否' ? text == '是' : text);
    if (value == null) return setState(() => _problem = '要填一个整数。');
    if (info.settings.length >= kLibMaxSettings) return setState(() => _problem = '设置项最多 $kLibMaxSettings 个。');
    var n = 1;
    while (info.settings.any((s) => s.id == 's$n')) {
      n++;
    }
    _do(() => info.settings.add(LibSetting(id: 's$n', name: name.trim(), type: kind == '整数' ? LType.integer : (kind == '是否' ? LType.boolean : LType.text), defaultValue: value)));
  }

  @override
  Widget build(BuildContext context) {
    final doc = host.doc;
    final problems = beLibFiles(doc).problems;
    final classes = [
      for (final t in doc.core.types)
        if (t.kind == BeTypeKind.klass) t,
    ];
    return BeSheetFrame(
      key: const ValueKey('be-lib-info'),
      title: '这个库：${doc.name}',
      hint: '这份文档是一个库（${info.id}）。在画布上用“我的积木”写函数、在“类型与类”里写类，再到这里把它们公开成积木。别的文档在“积木库”里用上它，就能从积木盒里拖出来用。',
      problem: _problem ?? (problems.isEmpty ? null : '库文件现在出不来：${problems.first}${problems.length > 1 ? '（还有 ${problems.length - 1} 个问题，见问题列表）' : ''}'),
      children: [
        const BeSheetSection('公开成积木'),
        if (doc.functions.isEmpty && classes.every((t) => t.methods.isEmpty)) const BeSheetRow(label: '还没有函数。先在画布上从积木盒“我的积木”里新建一块。', muted: true),
        for (final f in doc.functions)
          BeSheetRow(
            key: ValueKey('be-lib-def-${f.id}'),
            label: f.name,
            value: switch (beLibDefOfFunction(info, f)) {
              null => '没公开',
              final d => '已公开 · ${_howWord(d.how)}',
            },
            onTap: () => unawaited(_open(beLibDefOfFunction(info, f), fn: f)),
          ),
        for (final t in classes)
          for (final m in t.methods)
            BeSheetRow(
              key: ValueKey('be-lib-def-${m.id}'),
              label: '${t.name}.${m.name}',
              value: info.blocks.any((b) => b.typeId == t.id && b.method == m.id) ? '已公开 · ${_howWord(m.isStatic ? LibHow.static : LibHow.method)}' : '没公开',
              onTap: () => unawaited(_open(null, type: t, method: m)),
            ),
        const BeSheetSection('设置项（用这个库的文档各填各的）'),
        for (final s in info.settings)
          BeSheetRow(
            key: ValueKey('be-lib-set-${s.id}'),
            label: s.name,
            value: '默认 ${s.defaultValue ?? '空'}',
            trailing: IconButton(
              key: ValueKey('be-lib-set-del-${s.id}'),
              tooltip: '删掉这个设置项',
              icon: Icon(Icons.close_rounded, size: 20, color: context.colors.textMuted),
              onPressed: () => _do(() => info.settings.removeWhere((x) => x.id == s.id)),
            ),
          ),
        BeSheetAdd(key: const ValueKey('be-lib-set-add'), label: '加一个设置项', onTap: () => unawaited(_addSetting())),
        const BeSheetSection('库的信息'),
        BeSheetRow(label: '标识', value: info.id, muted: true),
        BeSheetRow(
          key: const ValueKey('be-lib-version'),
          label: '版本',
          value: info.version,
          onTap: () async {
            final v = await promptDialog(context, title: '版本', initial: info.version, hint: '三段数字，比如 1.0.1');
            if (v == null || !mounted) return;
            if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v.trim())) return setState(() => _problem = '版本要写成三段数字，比如 1.0.1。');
            _do(() => info.version = v.trim());
          },
        ),
        BeSheetRow(key: const ValueKey('be-lib-author'), label: '作者', value: info.author.isEmpty ? '没写' : info.author, onTap: () => unawaited(_text('作者', info.author, (v) => info.author = v))),
        BeSheetRow(
          key: const ValueKey('be-lib-summary'),
          label: '一句话介绍',
          value: info.summary.isEmpty ? '没写' : info.summary,
          onTap: () => unawaited(_text('一句话介绍', info.summary, (v) => info.summary = v)),
        ),
        if (info.originId.isNotEmpty) BeSheetRow(label: '从哪复制来的', value: '${info.originId} ${info.originVersion}', muted: true),
      ],
    );
  }
}

/// 一块库积木：背后是一个函数（[fn]）或者一个类的方法（[type]＋[method]）。
class _DefSheet extends StatefulWidget {
  const _DefSheet({required this.host, this.fn, this.type, this.method});
  final BeBlockHost host;
  final BeFunction? fn;
  final BeTypeDef? type;
  final BeMethod? method;

  @override
  State<_DefSheet> createState() => _DefSheetState();
}

class _DefSheetState extends State<_DefSheet> {
  String? _problem;
  BeBlockHost get host => widget.host;
  BeLibInfo get info => host.doc.library!;
  BeFunction? get fn => widget.fn;

  BeLibDef? get def => fn != null ? beLibDefOfFunction(info, fn!) : info.blocks.where((b) => b.typeId == widget.type!.id && b.method == widget.method!.id).firstOrNull;
  String get _name => fn?.name ?? '${widget.type!.name}.${widget.method!.name}';
  List<String> get _params => fn != null ? fn!.paramNames : [for (final p in widget.method!.params) p.name];

  void _do(void Function() change) {
    host.edit(change);
    setState(() => _problem = null);
  }

  void _toggle(bool on) {
    if (!on) return _do(() => info.blocks.remove(def));
    if (info.blocks.length >= kBeMaxLibDefs) return setState(() => _problem = '一个库最多公开 $kBeMaxLibDefs 块积木。');
    final m = widget.method;
    _do(
      () => info.blocks.add(
        fn != null
            ? BeLibDef(id: info.freeDefId(), how: LibHow.call, fn: fn!.id)
            : BeLibDef(id: info.freeDefId(), how: m!.isStatic ? LibHow.static : LibHow.method, typeId: widget.type!.id, method: m.id),
      ),
    );
  }

  String get _template {
    final d = def!;
    if (d.look != null && d.look!.template.trim().isNotEmpty) return d.look!.template;
    if (fn != null) return fn!.look.templateFor(_params);
    final self = d.how == LibHow.method;
    return '${self ? '{$kBeLibSelfSlot} ' : '${widget.type!.name} '}${widget.method!.name}${[for (final p in _params) ' {$p}'].join()}';
  }

  Future<void> _look() async {
    final d = def!;
    final v = await promptDialog(context, title: '积木上的字', initial: _template, hint: '槽写成 {参数名}。口、“放进变量”的槽不用写，会自动接在后面');
    if (v == null || !mounted) return;
    _do(() => d.look = (d.look ?? fn?.look ?? CustomBlockLook(_name)).copyWith(template: v.trim()));
  }

  Future<void> _how() async {
    final d = def!;
    final v = await _pick<LibHow>(context, '用的时候怎么办', const [(LibHow.call, '调用它', '最常见。用的地方调一次这个函数；可以是一个值'), (LibHow.expand, '原地展开', '把函数里的积木照样铺到用的地方。带口的、当帽子的积木要选这个；不能是一个值')]);
    if (v == null || !mounted) return;
    _do(() {
      d.how = v;
      if (v == LibHow.call) {
        d.mouths.clear();
        d.provides.clear();
        d.shape = null;
      }
    });
  }

  Future<void> _shape() async {
    final d = def!;
    final v = await _pick<CustomBlockShape>(context, '形状', const [
      (CustomBlockShape.statement, '语句', '上下都能接别的积木'),
      (CustomBlockShape.hat, '帽子', '当一串积木的开头；它的第一个口就是下面接的那一串'),
      (CustomBlockShape.cap, '收尾', '下面不能再接积木'),
    ]);
    if (v == null || !mounted) return;
    _do(() => d.shape = v);
  }

  String _fromWord(BeLibParam? p) => switch (p?.from) {
    null || BeLibFrom.slot => '积木上的槽',
    BeLibFrom.literal => '积木上直接填',
    BeLibFrom.context => '隐含的「${p!.key}」',
    BeLibFrom.setting => '设置项「${info.settings.where((s) => s.id == p!.key).firstOrNull?.name ?? p!.key}」',
    BeLibFrom.preset => '填死：${p!.value}',
  };

  Future<void> _from(String param) async {
    final d = def!;
    final v = await _pick<BeLibFrom>(context, '「$param」从哪来', const [
      (BeLibFrom.slot, '积木上的槽', '用的人往里放值'),
      (BeLibFrom.literal, '积木上直接填', '只许直接填字或数（帽子上的名字、路径这种）'),
      (BeLibFrom.context, '隐含的东西', '外面的帽子或带口的积木递进来的，积木上没有这一格'),
      (BeLibFrom.setting, '设置项', '用这个库的文档在“积木库”里填的值'),
      (BeLibFrom.preset, '填死', '总是同一个值'),
    ]);
    if (v == null || !mounted) return;
    var key = '';
    Object? value;
    if (v == BeLibFrom.context) {
      final k = await promptDialog(context, title: '是哪样隐含的东西', initial: d.params[param]?.key ?? '', hint: '和递它的那块积木写的名字一样，比如 请求');
      if (k == null || k.trim().isEmpty || !mounted) return;
      key = k.trim();
    } else if (v == BeLibFrom.setting) {
      if (info.settings.isEmpty) return setState(() => _problem = '这个库还没有设置项。先回上一页加一个。');
      final k = await _pick<String>(context, '哪个设置项', [for (final s in info.settings) (s.id, s.name, '默认 ${s.defaultValue ?? '空'}')]);
      if (k == null || !mounted) return;
      key = k;
    } else if (v == BeLibFrom.preset) {
      final raw = await promptDialog(context, title: '填死成什么', hint: '数字、文字，或者 是 / 否');
      if (raw == null || !mounted) return;
      final t = raw.trim();
      value = num.tryParse(t) ?? (t == '是' ? true : (t == '否' ? false : t));
    }
    _do(() => v == BeLibFrom.slot ? d.params.remove(param) : d.params[param] = BeLibParam(v, key: key, value: value));
  }

  Future<void> _addMouth() async {
    final d = def!;
    final v = await promptDialog(context, title: '口叫什么', hint: '用的人看到的名字，比如 做 / 成了以后');
    if (v == null || v.trim().isEmpty || !mounted) return;
    if (d.mouths.contains(v.trim())) return setState(() => _problem = '两个口不能同名。');
    _do(() => d.mouths.add(v.trim()));
  }

  Future<void> _addProvide() async {
    final d = def!;
    final name = await promptDialog(context, title: '递给口里的东西叫什么', hint: '口里的积木靠这个名字来认它，比如 这一轮');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final from = await promptDialog(context, title: '它是函数里的哪个变量', hint: '函数里新建的变量 / 常量的名字，或者参数名');
    if (from == null || from.trim().isEmpty || !mounted) return;
    _do(() => d.provides[name.trim()] = from.trim());
  }

  @override
  Widget build(BuildContext context) {
    final d = def;
    final c = context.colors;
    final mine = d == null ? const <String>[] : beLibFiles(host.doc).problems;
    final expand = d?.how == LibHow.expand;
    return BeSheetFrame(
      key: const ValueKey('be-lib-def'),
      title: _name,
      hint: d == null ? '打开以后，用上这个库的文档就能从积木盒里把它拖出来。' : '积木编号 ${d.id}（用它的文档里记的就是这个，定了就不变）',
      problem: _problem ?? (mine.isEmpty ? null : '库文件现在出不来：${mine.first}'),
      children: [
        SwitchListTile(
          key: const ValueKey('be-lib-def-public'),
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
          title: const Text('公开成积木'),
          value: d != null,
          onChanged: _toggle,
        ),
        if (d != null) ...[
          BeSheetRow(key: const ValueKey('be-lib-def-look'), label: '积木上的字', value: _template, onTap: () => unawaited(_look())),
          if (fn != null) BeSheetRow(key: const ValueKey('be-lib-def-how'), label: '用的时候怎么办', value: _howWord(d.how), onTap: () => unawaited(_how())),
          if (expand)
            BeSheetRow(
              key: const ValueKey('be-lib-def-shape'),
              label: '形状',
              value: switch (d.shape) {
                CustomBlockShape.hat => '帽子',
                CustomBlockShape.cap => '收尾',
                _ => '语句',
              },
              onTap: () => unawaited(_shape()),
            ),
          if (_params.isNotEmpty) const BeSheetSection('每个参数从哪来'),
          for (final p in _params) BeSheetRow(key: ValueKey('be-lib-def-param-$p'), label: p, value: _fromWord(d.params[p]), onTap: () => unawaited(_from(p))),
          SwitchListTile(
            key: const ValueKey('be-lib-def-into'),
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4),
            title: const Text('多一个“放进变量”的槽'),
            subtitle: Text(expand ? '函数里用“交给用的人选的变量”那块积木写进去' : '把结果写进用的人选的变量'),
            value: d.into,
            onChanged: (v) => _do(() => d.into = v),
          ),
          if (expand) ...[
            const BeSheetSection('口（最多两个；函数里用“做口里的积木”指明在哪做）'),
            for (final m in d.mouths)
              BeSheetRow(
                key: ValueKey('be-lib-def-mouth-$m'),
                label: m,
                trailing: IconButton(
                  tooltip: '去掉这个口',
                  icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted),
                  onPressed: () => _do(() => d.mouths.remove(m)),
                ),
              ),
            if (d.mouths.length < 2) BeSheetAdd(key: const ValueKey('be-lib-def-mouth-add'), label: '加一个口', onTap: () => unawaited(_addMouth())),
            const BeSheetSection('递给口里的积木的东西'),
            for (final e in d.provides.entries)
              BeSheetRow(
                key: ValueKey('be-lib-def-provide-${e.key}'),
                label: e.key,
                value: '变量 ${e.value}',
                trailing: IconButton(
                  tooltip: '不递了',
                  icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted),
                  onPressed: () => _do(() => d.provides.remove(e.key)),
                ),
              ),
            BeSheetAdd(key: const ValueKey('be-lib-def-provide-add'), label: '递一样东西', onTap: () => unawaited(_addProvide())),
          ],
        ],
      ],
    );
  }
}
