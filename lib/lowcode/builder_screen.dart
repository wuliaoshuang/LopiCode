// 设计约束（低代码搭建 · 390×844）
// - 画布是主角，占满屏幕宽度，所见即所得（和导出的 Flutter 代码用同一套排版规则）。
// - 底部固定一条组件栏：长按拖到画布，或者点一下直接加进当前选中的容器。
// - 选中组件后，组件栏上方出现一行操作：名字在左，上移 / 下移 / 复制 / 删除 / 属性在右。
// - 属性、图层树都放进底部面板，不和画布抢地方。撤销 / 重做在顶栏。
// - 拖动时才显示插入位置（绿色横条 / 竖条），平时不干扰画面。
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 拖动中携带的东西：新组件的类型，或画布上已有组件的 id。
class _Drag {
  const _Drag.fresh(String this.type) : nodeId = null;
  const _Drag.move(String this.nodeId) : type = null;
  final String? type;
  final String? nodeId;
}

IconData lcIcon(String type) => switch (type) {
  'page' => Icons.phone_android,
  'container' => Icons.crop_square,
  'row' => Icons.view_column_outlined,
  'column' => Icons.table_rows_outlined,
  'card' => Icons.featured_play_list_outlined,
  'text' => Icons.title,
  'button' => Icons.smart_button_outlined,
  'image' => Icons.image_outlined,
  'input' => Icons.text_fields,
  'list' => Icons.format_list_bulleted,
  'divider' => Icons.horizontal_rule,
  'spacer' => Icons.expand,
  _ => Icons.widgets_outlined,
};

Color _hex(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key, required this.session, this.initialSelection});
  final ProjectSession session;

  /// 测试 / 截图用。
  final String? initialSelection;

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  LcDocument? _doc;
  LcHistory? _history;
  String? _loadError;
  bool _missing = false;
  String? _selected;
  bool _dragging = false;
  Future<void> _saving = Future.value();

  File get _file => File(widget.session.guard.resolve(kLowcodePageFile));

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await _file.exists()) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final doc = LcDocument.parse(await _file.readAsString());
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _history = LcHistory(doc);
        _missing = false;
        _loadError = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } on FileSystemException {
      if (mounted) setState(() => _loadError = '读不了 $kLowcodePageFile');
    }
  }

  Future<void> _createFresh() async {
    final doc = LcDocument.starter(widget.session.project.name);
    await saveLowcodePage(widget.session.guard, doc);
    widget.session.filesChanged();
    await _load();
  }

  /// 所有修改都走这里：改模型 → 记历史 → 存盘并重新导出网页。
  void _apply(void Function(LcDocument doc) change) {
    final doc = _doc!;
    setState(() => change(doc));
    _history!.record(doc);
    _save();
  }

  void _save() {
    final snapshot = LcDocument.parse(_doc!.encode());
    _saving = _saving.then((_) async {
      try {
        await saveLowcodePage(widget.session.guard, snapshot);
        widget.session.filesChanged();
      } on FileSystemException {
        if (mounted) showSnack(context, '保存失败');
      }
    });
  }

  void _restore(LcDocument? doc) {
    if (doc == null) return;
    setState(() {
      _doc = doc;
      if (_selected != null && doc.find(_selected!) == null) _selected = null;
    });
    _save();
  }

  /// 点组件栏：加进选中的容器；选中的不是容器就加在它后面；没选中加到页面末尾。
  void _addByTap(String type) {
    final doc = _doc!;
    final sel = _selected == null ? null : doc.find(_selected!);
    final node = doc.newNode(type);
    _apply((d) {
      if (sel != null && sel.isContainer) {
        d.insert(sel.id, node);
      } else if (sel != null) {
        final parent = d.parentOf(sel.id)!;
        d.insert(parent.id, node, parent.children.indexOf(sel) + 1);
      } else {
        d.insert(d.root.id, node);
      }
    });
    setState(() => _selected = node.id);
  }

  void _drop(_Drag drag, String parentId, int index) {
    if (drag.type != null) {
      final node = _doc!.newNode(drag.type!);
      _apply((d) => d.insert(parentId, node, index));
      setState(() => _selected = node.id);
    } else {
      _apply((d) => d.move(drag.nodeId!, parentId, index));
    }
  }

  bool _canDrop(_Drag drag, String parentId) {
    if (drag.nodeId == null) return true;
    final node = _doc!.find(drag.nodeId!);
    if (node == null) return false;
    // 不能拖进自己或自己的后代里
    bool contains(LcNode n) => n.id == parentId || n.children.any(contains);
    return !contains(node);
  }

  void _setDragging(bool v) {
    if (mounted && _dragging != v) setState(() => _dragging = v);
  }

  void _openProps() {
    final node = _doc!.find(_selected!);
    if (node == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black26,
      builder: (_) => _PropertySheet(
        node: node,
        onChanged: (key, value) => _apply((d) {
          final n = d.find(node.id);
          if (n == null) return;
          if (value == null) {
            n.props.remove(key);
          } else {
            n.props[key] = value;
          }
        }),
      ),
    );
  }

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _LayerSheet(
        doc: _doc!,
        selected: _selected,
        onSelect: (id) {
          Navigator.pop(sheetContext);
          setState(() => _selected = id);
        },
      ),
    );
  }

  Future<void> _exportDart() async {
    final code = exportDart(_doc!);
    const path = 'export/page.dart';
    try {
      final file = File(widget.session.guard.resolve(path));
      await file.parent.create(recursive: true);
      await file.writeAsString(code);
      widget.session.filesChanged();
    } on FileSystemException {
      if (mounted) showSnack(context, '写入 $path 失败');
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CodeSheet(title: 'Flutter 代码', note: '已保存到项目的 $path', code: code),
    );
  }

  Future<void> _renamePage() async {
    final name = await promptDialog(context, title: '页面标题', initial: _doc!.title, confirmLabel: '保存');
    if (name == null || name.trim().isEmpty) return;
    _apply((d) => d.title = name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final history = _history;
    return Scaffold(
      appBar: ShellAppBar(
        title: '低代码搭建',
        subtitle: doc?.title,
        actions: doc == null
            ? null
            : [
                IconButton(tooltip: '撤销', icon: const Icon(Icons.undo), onPressed: history!.canUndo ? () => _restore(history.undo()) : null),
                IconButton(tooltip: '重做', icon: const Icon(Icons.redo), onPressed: history.canRedo ? () => _restore(history.redo()) : null),
                IconButton(tooltip: '图层', icon: const Icon(Icons.layers_outlined), onPressed: _openLayers),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'dart') _exportDart();
                    if (v == 'preview') {
                      final shell = ShellScope.maybeOf(context);
                      if (shell != null) {
                        shell.go(ShellDest.preview);
                      } else {
                        Navigator.pop(context, 'preview');
                      }
                    }
                    if (v == 'title') _renamePage();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'preview', child: Text('在预览里打开网页')),
                    PopupMenuItem(value: 'dart', child: Text('导出 Flutter 代码')),
                    PopupMenuItem(value: 'title', child: Text('修改页面标题')),
                  ],
                ),
              ],
      ),
      body: _loadError != null
          ? EmptyState(
              icon: Icons.error_outline,
              title: '页面文件打不开',
              message: '$kLowcodePageFile 的内容有问题：$_loadError',
              action: OutlinedButton(onPressed: _createFresh, child: const Text('用一个新页面覆盖')),
            )
          : _missing
          ? EmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: '这个项目还没有低代码页面',
              message: '新建后会在项目里生成 $kLowcodePageFile，\n并自动导出 index.html 和 style.css。',
              action: FilledButton(onPressed: _createFresh, child: const Text('新建页面')),
            )
          : doc == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = null),
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: _Canvas(
                          minHeight: box.maxHeight,
                          doc: doc,
                          selected: _selected,
                          dragging: _dragging,
                          onSelect: (id) => setState(() => _selected = id),
                          onDrop: _drop,
                          canDrop: _canDrop,
                          onDragging: _setDragging,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_selected != null && doc.find(_selected!) != null) _selectionBar(context, doc.find(_selected!)!),
                _Palette(onTap: _addByTap, onDragging: _setDragging),
              ],
            ),
    );
  }

  Widget _selectionBar(BuildContext context, LcNode node) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final isRoot = node.type == 'page';
    Widget action(IconData icon, String tip, VoidCallback? onTap) => IconButton(tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon, size: 20), onPressed: onTap);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: Space.x4, right: Space.x2),
      height: 48,
      child: Row(
        children: [
          Icon(lcIcon(node.type), size: 18, color: c.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(node.spec.label, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (!isRoot) ...[
            action(Icons.arrow_upward, '上移', () => _apply((d) => d.shift(node.id, -1))),
            action(Icons.arrow_downward, '下移', () => _apply((d) => d.shift(node.id, 1))),
            action(Icons.copy_outlined, '复制', () {
              String? copy;
              _apply((d) => copy = d.duplicate(node.id));
              if (copy != null) setState(() => _selected = copy);
            }),
            action(Icons.delete_outline, '删除', () {
              _apply((d) => d.remove(node.id));
              setState(() => _selected = null);
            }),
          ],
          const SizedBox(width: Space.x1),
          FilledButton(
            onPressed: _openProps,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
            child: const Text('属性'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── 组件栏 ─────────────────────────

class _Palette extends StatelessWidget {
  const _Palette({required this.onTap, required this.onDragging});
  final void Function(String type) onTap;
  final void Function(bool) onDragging;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
              child: Text('组件 · 点一下添加，长按拖到画布', style: t.labelSmall),
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                itemCount: lcPaletteTypes.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
                itemBuilder: (context, i) {
                  final type = lcPaletteTypes[i];
                  Widget chip({bool lifted = false}) => Container(
                    width: 60,
                    decoration: BoxDecoration(
                      color: lifted ? c.accentSoft : c.bg,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: lifted ? c.accentFill : c.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(lcIcon(type), size: 20, color: lifted ? c.accent : c.textMuted),
                        const SizedBox(height: 2),
                        Text(lcSpecs[type]!.label, style: t.labelSmall?.copyWith(color: lifted ? c.accent : c.text)),
                      ],
                    ),
                  );
                  return LongPressDraggable<_Drag>(
                    data: _Drag.fresh(type),
                    delay: const Duration(milliseconds: 250),
                    onDragStarted: () => onDragging(true),
                    onDragEnd: (_) => onDragging(false),
                    onDraggableCanceled: (_, _) => onDragging(false),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(height: 56, child: chip(lifted: true)),
                    ),
                    child: GestureDetector(onTap: () => onTap(type), child: chip()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 画布 ─────────────────────────

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.minHeight,
    required this.doc,
    required this.selected,
    required this.dragging,
    required this.onSelect,
    required this.onDrop,
    required this.canDrop,
    required this.onDragging,
  });

  /// 画布至少铺满可见区域，页面背景不会只盖到内容那么高。
  final double minHeight;

  final LcDocument doc;
  final String? selected;
  final bool dragging;
  final void Function(String id) onSelect;
  final void Function(_Drag drag, String parentId, int index) onDrop;
  final bool Function(_Drag drag, String parentId) canDrop;
  final void Function(bool) onDragging;

  @override
  Widget build(BuildContext context) {
    final root = doc.root;
    final bg = root.strProp('bg');
    // 画布里的内容用固定的浅色主题渲染：它是“用户页面”的样子，不跟随应用深色模式。
    return Theme(
      data: ThemeData(useMaterial3: true, colorSchemeSeed: Palette.primary700, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 16, color: Palette.neutral900, height: 1.5, fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: GestureDetector(
          onTap: () => onSelect(root.id),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: minHeight),
            color: bg != null ? _hex(bg) : Colors.white,
            foregroundDecoration: selected == root.id ? BoxDecoration(border: Border.all(color: Palette.primary500, width: 2)) : null,
            padding: EdgeInsets.all((root.numProp('padding') ?? 0).toDouble()),
            child: _flex(context, root, column: true),
          ),
        ),
      ),
    );
  }

  // 子组件之间夹着“插入位”。平时它就是间距；拖动时加宽并在悬停时变成绿色条。
  Widget _flex(BuildContext context, LcNode n, {required bool column}) {
    final gap = (n.numProp('gap') ?? 0).toDouble();
    final a = n.strProp('align') ?? (column ? 'start' : 'center');
    final cross = switch (a) {
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => CrossAxisAlignment.start,
    };
    final main = switch (n.strProp('justify')) {
      'center' => MainAxisAlignment.center,
      'end' => MainAxisAlignment.end,
      'between' => MainAxisAlignment.spaceBetween,
      _ => MainAxisAlignment.start,
    };
    if (n.children.isEmpty) {
      return _Slot(parentId: n.id, index: 0, vertical: !column, idle: 0, dragging: dragging, emptyHint: true, onDrop: onDrop, canDrop: canDrop);
    }
    final children = <Widget>[];
    for (var i = 0; i <= n.children.length; i++) {
      final edge = i == 0 || i == n.children.length;
      children.add(_Slot(parentId: n.id, index: i, vertical: !column, idle: edge ? 0 : gap, dragging: dragging, onDrop: onDrop, canDrop: canDrop));
      if (i < n.children.length) children.add(_node(context, n.children[i], n));
    }
    return Flex(
      direction: column ? Axis.vertical : Axis.horizontal,
      mainAxisSize: column ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: cross,
      mainAxisAlignment: main,
      children: children,
    );
  }

  Widget _node(BuildContext context, LcNode n, LcNode parent) {
    final inRow = parent.type == 'row';
    final w = n.props['width'];
    Widget inner;
    switch (n.type) {
      case 'container' || 'column' || 'card' || 'row':
        inner = _box(
          n,
          _flex(context, n, column: n.type != 'row'),
          inRow: inRow,
          shadow: n.type == 'card',
        );
      case 'text':
        final text = Text(
          n.strProp('text') ?? '',
          textAlign: switch (n.strProp('textAlign')) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            'left' => TextAlign.left,
            _ => null,
          },
          style: TextStyle(
            fontSize: n.numProp('fontSize')?.toDouble(),
            fontWeight: n.props['bold'] == true ? FontWeight.w600 : null,
            color: n.strProp('color') != null ? _hex(n.strProp('color')!) : null,
            height: 1.5,
          ),
        );
        inner = _needsBox(n) ? _box(n, text, inRow: inRow) : text;
      case 'button':
        final r = n.numProp('radius');
        inner = _sized(
          n,
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              backgroundColor: n.strProp('bg') != null ? _hex(n.strProp('bg')!) : null,
              foregroundColor: n.strProp('color') != null ? _hex(n.strProp('color')!) : null,
              padding: n.numProp('padding') != null ? EdgeInsets.all(n.numProp('padding')!.toDouble()) : null,
              shape: r != null ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.toDouble())) : null,
              // 只改字号：整个替换 textStyle 会丢掉主题里的字体和字重
              textStyle: n.numProp('fontSize') != null ? Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: n.numProp('fontSize')!.toDouble()) : null,
            ),
            child: Text(n.strProp('text') ?? ''),
          ),
          inRow: inRow,
        );
      case 'image':
        final h = n.numProp('height')?.toDouble();
        final width = w is num ? w.toDouble() : (n.fillWidth && !inRow ? double.infinity : null);
        final src = n.strProp('src');
        inner = _margin(
          n,
          ClipRRect(
            borderRadius: BorderRadius.circular((n.numProp('radius') ?? 0).toDouble()),
            child: src == null
                ? Container(
                    height: h,
                    width: width,
                    color: Palette.neutral200,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_outlined, color: Palette.neutral500),
                  )
                : Image.network(
                    src,
                    height: h,
                    width: width,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: h,
                      width: width,
                      color: Palette.neutral200,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, color: Palette.neutral500),
                    ),
                  ),
          ),
        );
      case 'input':
        final field = TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: n.strProp('placeholder') ?? '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular((n.numProp('radius') ?? 4).toDouble())),
          ),
        );
        inner = inRow && w == null ? _margin(n, SizedBox(width: 160, child: field)) : _sized(n, field, inRow: inRow);
      case 'list':
        final style = TextStyle(fontSize: n.numProp('fontSize')?.toDouble(), color: n.strProp('color') != null ? _hex(n.strProp('color')!) : null, height: 1.75);
        final col = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [for (final item in (n.props['items'] as List?) ?? const []) Text('• $item', style: style)],
        );
        inner = _needsBox(n) ? _box(n, col, inRow: inRow) : col;
      case 'divider':
        inner = _margin(n, inRow ? const SizedBox(height: 24, child: VerticalDivider(width: 1)) : const Divider(height: 1));
      case 'spacer':
        final size = (n.numProp('size') ?? 16).toDouble();
        inner = inRow ? SizedBox(width: size) : SizedBox(height: size);
      default:
        inner = const SizedBox.shrink();
    }

    final isSelected = selected == n.id;
    // 选中框画在最外层；组件本身不响应点击（按钮、输入框都只是样子）。
    Widget wrapped = GestureDetector(
      key: ValueKey('lowcode-node-${n.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(n.id),
      child: Container(
        foregroundDecoration: isSelected
            ? BoxDecoration(border: Border.all(color: Palette.primary500, width: 2))
            : (dragging && n.isContainer ? BoxDecoration(border: Border.all(color: Palette.neutral300)) : null),
        child: n.isContainer ? inner : IgnorePointer(child: inner),
      ),
    );
    wrapped = LongPressDraggable<_Drag>(
      data: _Drag.move(n.id),
      delay: const Duration(milliseconds: 350),
      onDragStarted: () {
        onSelect(n.id);
        onDragging(true);
      },
      onDragEnd: (_) => onDragging(false),
      onDraggableCanceled: (_, _) => onDragging(false),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Palette.primary700, borderRadius: BorderRadius.circular(Radii.md)),
          child: Text('移动 ${n.spec.label}', style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: wrapped),
      child: wrapped,
    );

    // 和导出规则一致：行里撑满的组件、没给固定宽度的容器用 Expanded；自适应的文本用 Flexible。
    if (inRow) {
      if (n.fillWidth || (n.isContainer && w is! num)) {
        return Expanded(child: wrapped);
      }
      if (n.type == 'text' && w == null) return Flexible(child: wrapped);
    }
    return wrapped;
  }

  static bool _needsBox(LcNode n) => n.props['width'] != null || n.numProp('padding') != null || n.numProp('margin') != null || n.strProp('bg') != null;

  Widget _box(LcNode n, Widget child, {required bool inRow, bool shadow = false}) {
    final w = n.props['width'];
    final m = n.numProp('margin');
    final p = n.numProp('padding');
    final hasDeco = n.strProp('bg') != null || n.numProp('radius') != null || shadow;
    return Container(
      width: w is num ? w.toDouble() : (w == 'fill' && !inRow ? double.infinity : null),
      height: n.numProp('height')?.toDouble(),
      margin: m != null ? EdgeInsets.all(m.toDouble()) : null,
      padding: p != null ? EdgeInsets.all(p.toDouble()) : null,
      decoration: hasDeco
          ? BoxDecoration(
              color: n.strProp('bg') != null ? _hex(n.strProp('bg')!) : null,
              borderRadius: n.numProp('radius') != null ? BorderRadius.circular(n.numProp('radius')!.toDouble()) : null,
              boxShadow: shadow ? const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))] : null,
            )
          : null,
      child: child,
    );
  }

  Widget _sized(LcNode n, Widget child, {required bool inRow}) {
    final w = n.props['width'];
    var out = child;
    if (w is num) {
      out = SizedBox(width: w.toDouble(), child: out);
    } else if (w == 'fill' && !inRow) {
      out = SizedBox(width: double.infinity, child: out);
    }
    return _margin(n, out);
  }

  Widget _margin(LcNode n, Widget child) {
    final m = n.numProp('margin');
    if (m == null || m == 0) return child;
    return Padding(padding: EdgeInsets.all(m.toDouble()), child: child);
  }
}

/// 一个插入位。
class _Slot extends StatelessWidget {
  const _Slot({required this.parentId, required this.index, required this.vertical, required this.idle, required this.dragging, required this.onDrop, required this.canDrop, this.emptyHint = false});

  final String parentId;
  final int index;

  /// true = 竖条（在行里）。
  final bool vertical;

  /// 不拖动时占的尺寸（＝容器的间距）。
  final double idle;
  final bool dragging;
  final bool emptyHint;
  final void Function(_Drag, String, int) onDrop;
  final bool Function(_Drag, String) canDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => canDrop(d.data, parentId),
      onAcceptWithDetails: (d) => onDrop(d.data, parentId, index),
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        if (emptyHint) {
          return Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hover ? Palette.primary200 : const Color(0x0F000000),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: hover ? Palette.primary500 : Palette.neutral300),
            ),
            child: Text(hover ? '松手放进来' : '空的 · 拖组件到这里', style: const TextStyle(fontSize: 12, color: Palette.neutral600)),
          );
        }
        final size = dragging ? (idle < 20 ? 20.0 : idle) : idle;
        final bar = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: vertical ? size : null,
          height: vertical ? null : size,
          constraints: vertical ? const BoxConstraints(minHeight: 24) : null,
          alignment: Alignment.center,
          child: dragging
              ? Container(
                  width: vertical ? (hover ? 6 : 2) : double.infinity,
                  height: vertical ? double.infinity : (hover ? 6 : 2),
                  constraints: vertical ? const BoxConstraints(minHeight: 24, maxHeight: 64) : null,
                  decoration: BoxDecoration(color: hover ? Palette.primary500 : Palette.primary200, borderRadius: BorderRadius.circular(3)),
                )
              : null,
        );
        return bar;
      },
    );
  }
}

// ───────────────────────── 属性面板 ─────────────────────────

const Map<String, String> _fieldLabels = {
  'text': '文字',
  'src': '图片地址',
  'placeholder': '提示文字',
  'items': '列表项（一行一项）',
  'width': '宽度',
  'height': '高度',
  'padding': '内边距',
  'margin': '外边距',
  'radius': '圆角',
  'gap': '子项间距',
  'fontSize': '字号',
  'size': '间隔大小',
  'bg': '背景色',
  'color': '文字颜色',
  'align': '交叉方向对齐',
  'justify': '主方向分布',
  'textAlign': '文字对齐',
  'bold': '加粗',
};

const List<String> _swatches = ['#FFFFFF', '#F6FBFD', '#D3DEE4', '#707A8F', '#222435', '#058654', '#29D2B2', '#DC3545', '#D98A0B', '#3B6FE0'];

class _PropertySheet extends StatefulWidget {
  const _PropertySheet({required this.node, required this.onChanged});
  final LcNode node;
  final void Function(String key, Object? value) onChanged;

  @override
  State<_PropertySheet> createState() => _PropertySheetState();
}

class _PropertySheetState extends State<_PropertySheet> {
  final Map<String, TextEditingController> _text = {};

  LcNode get n => widget.node;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, Object? value) {
    widget.onChanged(key, value);
    setState(() {});
  }

  TextEditingController _controller(String key, String initial) => _text.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x6),
        children: [
          Text('${n.spec.label}属性', style: t.titleLarge),
          const SizedBox(height: Space.x2),
          for (final key in n.spec.fields) ...[const SizedBox(height: Space.x3), _field(context, key)],
        ],
      ),
    );
  }

  Widget _labeled(BuildContext context, String key, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_fieldLabels[key] ?? key, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      child,
    ],
  );

  Widget _field(BuildContext context, String key) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    switch (key) {
      case 'text' || 'src' || 'placeholder':
        return _labeled(
          context,
          key,
          TextField(
            controller: _controller(key, n.strProp(key) ?? ''),
            minLines: 1,
            maxLines: key == 'text' ? 4 : 1,
            keyboardType: key == 'src' ? TextInputType.url : null,
            decoration: InputDecoration(hintText: key == 'src' ? 'https://…（留空显示占位图）' : null),
            onChanged: (v) => _set(key, v),
          ),
        );
      case 'items':
        final items = ((n.props['items'] as List?) ?? const []).join('\n');
        return _labeled(context, key, TextField(controller: _controller(key, items), minLines: 3, maxLines: 8, onChanged: (v) => _set(key, v.split('\n').where((s) => s.trim().isNotEmpty).toList())));
      case 'width':
        final w = n.props['width'];
        final mode = w == 'fill' ? 'fill' : (w is num ? 'fixed' : 'auto');
        return _labeled(
          context,
          key,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('自适应')),
                  ButtonSegment(value: 'fill', label: Text('撑满')),
                  ButtonSegment(value: 'fixed', label: Text('固定')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => _set('width', switch (s.first) {
                  'fill' => 'fill',
                  'fixed' => 160,
                  _ => null,
                }),
              ),
              if (w is num) ...[const SizedBox(height: Space.x2), _Stepper(value: w, step: 8, onChanged: (v) => _set('width', v ?? 0))],
            ],
          ),
        );
      case 'height' || 'padding' || 'margin' || 'radius' || 'gap' || 'fontSize' || 'size':
        return Row(
          children: [
            Expanded(child: Text(_fieldLabels[key]!, style: t.bodyMedium)),
            _Stepper(value: n.numProp(key), step: key == 'fontSize' ? 2 : (key == 'height' ? 8 : 4), clearable: key != 'size', onChanged: (v) => _set(key, v)),
          ],
        );
      case 'bg' || 'color':
        final current = n.strProp(key);
        return _labeled(
          context,
          key,
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              if (key == 'bg') _Swatch(color: null, selected: current == null, onTap: () => _set(key, null)),
              for (final hex in _swatches) _Swatch(color: _hex(hex), selected: current == hex, onTap: () => _set(key, hex)),
            ],
          ),
        );
      case 'align' || 'justify' || 'textAlign':
        final options = switch (key) {
          'align' => const {'start': '起点', 'center': '居中', 'end': '终点', 'stretch': '拉伸'},
          'justify' => const {'start': '起点', 'center': '居中', 'end': '终点', 'between': '两端'},
          _ => const {'left': '靠左', 'center': '居中', 'right': '靠右'},
        };
        final fallback = switch (key) {
          'align' => n.type == 'row' ? 'center' : 'start',
          'justify' => 'start',
          _ => 'left',
        };
        return _labeled(
          context,
          key,
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {n.strProp(key) ?? fallback},
              onSelectionChanged: (s) => _set(key, s.first),
            ),
          ),
        );
      case 'bold':
        return Row(
          children: [
            Expanded(child: Text(_fieldLabels[key]!, style: t.bodyMedium)),
            Switch(value: n.props['bold'] == true, onChanged: (v) => _set('bold', v ? true : null)),
          ],
        );
    }
    return Text(key, style: TextStyle(color: c.textFaint));
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.step, required this.onChanged, this.clearable = true});
  final num? value;
  final num step;
  final bool clearable;
  final void Function(num? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final v = value;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 18, color: onTap == null ? c.border : c.text)),
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            Icons.remove,
            v == null
                ? null
                : () {
                    final next = v - step;
                    // 减到 0 以下：可清除的属性回到“不设置”，其余停在 0。
                    onChanged(next < 0 ? (clearable ? null : 0) : next);
                  },
          ),
          SizedBox(
            width: 56,
            child: Text(v == null ? '默认' : (v == v.roundToDouble() ? '${v.round()}' : '$v'), textAlign: TextAlign.center, style: v == null ? t.bodySmall : t.titleSmall),
          ),
          btn(Icons.add, () => onChanged((v ?? 0) + step)),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        // 选中 = 外圈一道环 + 留白，和色块本身的颜色无关（绿色块上的绿边框看不出来）
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? c.text : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
          child: color == null ? Icon(Icons.block, size: 16, color: c.textFaint) : null,
        ),
      ),
    );
  }
}

// ───────────────────────── 图层树 ─────────────────────────

class _LayerSheet extends StatelessWidget {
  const _LayerSheet({required this.doc, required this.selected, required this.onSelect});
  final LcDocument doc;
  final String? selected;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rows = <(LcNode, int)>[];
    void walk(LcNode n, int depth) {
      rows.add((n, depth));
      for (final child in n.children) {
        walk(child, depth + 1);
      }
    }

    walk(doc.root, 0);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('图层 · ${rows.length} 个组件', style: t.titleLarge),
            );
          }
          final (node, depth) = rows[i - 1];
          final active = node.id == selected;
          final hint = node.strProp('text') ?? node.strProp('placeholder') ?? '';
          return InkWell(
            onTap: () => onSelect(node.id),
            child: Container(
              color: active ? c.accentSoft : null,
              padding: EdgeInsets.fromLTRB(Space.x4 + depth * Space.x4, 10, Space.x4, 10),
              child: Row(
                children: [
                  Icon(lcIcon(node.type), size: 18, color: active ? c.accent : c.textFaint),
                  const SizedBox(width: Space.x2),
                  Text(node.spec.label, style: t.titleSmall?.copyWith(color: active ? c.accent : c.text)),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── 代码面板 ─────────────────────────

class _CodeSheet extends StatelessWidget {
  const _CodeSheet({required this.title, required this.note, required this.code});
  final String title;
  final String note;
  final String code;

  @override
  Widget build(BuildContext context) => CodeSheetBody(title: title, note: note, code: code);
}

/// 显示一段代码 + “复制”按钮的底部面板内容（APK 打包页的工作流模板也用它）。
class CodeSheetBody extends StatelessWidget {
  const CodeSheetBody({super.key, required this.title, required this.note, required this.code, this.extraAction});
  final String title;
  final String note;
  final String code;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleLarge),
                const SizedBox(height: 2),
                Text(note, style: t.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: c.codeBg,
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(Space.x3),
                child: SelectableText(
                  code,
                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.text),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Row(
                children: [
                  if (extraAction != null) ...[Expanded(child: extraAction!), const SizedBox(width: Space.x2)],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) showSnack(context, '已复制');
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制全部'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
