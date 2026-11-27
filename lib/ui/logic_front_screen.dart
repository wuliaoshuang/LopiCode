// 设计约束（新的页面逻辑页 · 390×844，浅色 + 深色）— 积木第 5 版·前端 1·下半
// - 和后端积木页是同一个积木编辑器（BlockEditorView）、同一个宿主（BeBlockHost，文档标了“前端”），不是抄的一份：
//   函数（新建积木）、类型与类、模块、积木库、类型检查、看代码，都是后端那边的同一套部件。
// - 顶栏右边只放三样：状态（带数量）、（在类的画布里）回主画布、更多。“更多”里一行一件事：类型与类、模块、积木库。
// - 积木盒最前面是“页面”库的四页：事件、状态、控件、页面；后面是语言核心（变量、运算、流程、函数、文字、列表、字典、错误、类型、要等的事）；再后面是用上的库。
// - 控件、状态、属性、页面都是下拉，从这一页里挑；没有的东西不让手填。
// - 改动：每次改完把整份新逻辑写回页面文档（搭建页落盘、记一条撤销）；这一页自己也有撤销 / 重做。
import 'dart:async';
import 'dart:convert';

import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/backend/front_upgrade.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/blocks/block_panels_sheet.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/backend_core_sheet.dart';
import 'package:lopicode/ui/backend_libs_sheet.dart';
import 'package:lopicode/ui/backend_modules_sheet.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/backend_types_sheet.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 页面上有什么：给积木上的下拉用。
class _PageCx implements BePageCx {
  _PageCx(this.doc);
  final LcDocument Function() doc;

  String _name(String id) {
    final s = describeNode(doc(), id);
    return s.length >= 2 && s.startsWith('「') && s.endsWith('」') ? s.substring(1, s.length - 1) : s;
  }

  @override
  List<BlockOption> get nodes {
    final out = <BlockOption>[];
    void walk(LcNode n) {
      out.add(BlockOption(n.id, _name(n.id)));
      n.children.forEach(walk);
    }

    walk(doc().root);
    return out;
  }

  @override
  List<BlockOption> get states => [for (final v in doc().logic.variables) BlockOption(v.name, v.name, hint: describeVarType(v.type))];

  static const Map<String, String> _propNames = {'text': '文字', 'value': '输入内容', 'visible': '是否显示', 'bg': '背景色', 'color': '文字颜色', 'src': '图片地址', 'placeholder': '提示文字'};

  @override
  List<BlockOption> props(String? node) {
    final n = node == null ? null : doc().find(node);
    final allowed = n == null ? _propNames.keys.toList() : {...readablePropsFor(n.type), ...writablePropsFor(n.type)}.toList();
    return [
      for (final p in _propNames.keys)
        if (allowed.contains(p)) BlockOption(p, _propNames[p]!),
    ];
  }

  @override
  List<BlockOption> get pages => [for (final p in doc().pages) BlockOption(p.id, p.title, hint: identical(p, doc().pages.first) ? '首页' : '')];

  @override
  String? label(String pick, String value) => switch (pick) {
    'node' => doc().find(value) == null ? null : _name(value),
    'page' => doc().pageTitle(value),
    'prop' => _propNames[value],
    _ => value,
  };
}

/// 整页的新页面逻辑编辑器。[doc] 是搭建页手里那份活的文档；[initialNodeId] 不为空时先看这个控件的事件。
class LogicFrontScreen extends StatefulWidget {
  const LogicFrontScreen({super.key, required this.doc, required this.onEdit, required this.session, this.initialNodeId});
  final LcDocument doc;
  final LcEdit onEdit;
  final ProjectSession session;
  final String? initialNodeId;

  @override
  State<LogicFrontScreen> createState() => _LogicFrontScreenState();
}

class _LogicFrontScreenState extends State<LogicFrontScreen> {
  late final BlockStars? _stars = blockStarsOf(context, 'logic-front');
  final GlobalKey<BlockEditorViewState> _editor = GlobalKey();
  late LcDocument _page = widget.doc;

  late final BeBlockHost _host =
      BeBlockHost(doc: (lcFrontOf(widget.doc.logic) ?? lcFrontNew()).clone()..loaded = widget.doc.logic.loaded, onEdited: _commit, onNotice: (m) => mounted ? showSnack(context, m) : null)
        ..pageCx = _PageCx(() => _page)
        ..extraIssues = () => lcFrontPageIssues(_page, _page.page, _host.doc);

  String get _stored => jsonEncode(_page.logic.front);

  /// 这一页自己改了：整份新逻辑写回页面文档（搭建页落盘）。
  void _commit() {
    final doc = _host.doc;
    widget.onEdit((d) {
      d.logic.loaded = [
        for (final l in doc.loaded)
          if (l.id != kLcPageLibId) l,
      ];
      lcFrontStore(d.logic, doc);
    });
  }

  /// 进来时要看的那一串：这个控件的第一顶帽子。
  late final String? _focus = () {
    final id = widget.initialNodeId;
    if (id == null) return null;
    for (final h in _host.doc.hats) {
      if (h.args['node'] == id) return h.id;
    }
    return null;
  }();

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
    final id = widget.initialNodeId;
    if (id == null || _focus != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSnack(context, '${describeNode(widget.doc, id)}还没有事件：从下面“事件”里拖一块出来。');
    });
  }

  /// 项目里的库交给这份逻辑（积木盒、标红跟着变）。读不了不拦着用。
  Future<void> _attach() async {
    try {
      await beLibsAttach(widget.session.guard, _host.doc);
      if (!mounted) return;
      _page.logic.loaded = [
        for (final l in _host.doc.loaded)
          if (l.id != kLcPageLibId) l,
      ];
      _host.canvasChanged();
    } on Object catch (e, st) {
      CrashLog.instance.record(e, st, source: '页面逻辑·读积木库', fatal: false);
    }
  }

  @override
  void didUpdateWidget(LogicFrontScreen old) {
    super.didUpdateWidget(old);
    if (identical(old.doc, widget.doc)) return;
    _page = widget.doc;
    // 文档在外面变了（搭建页的撤销、Agent 改了页面）：新逻辑和手上的不一样才换，免得自己刚提交的改动把撤销记录冲掉。
    final front = lcFrontOf(_page.logic);
    if (front != null && _stored != jsonEncode(_host.doc.toJson())) {
      _host.replaceDoc(front.clone()..loaded = _host.doc.loaded.where((l) => l.id != kLcPageLibId).toList());
    } else {
      _host.canvasChanged(); // 控件、状态可能变了：下拉重新问
    }
  }

  Future<void> _openVars() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LcVarsSheet(read: () => _page, edit: widget.onEdit),
    );
    if (!mounted) return;
    _host.canvasChanged();
    setState(() {});
  }

  void _onMenu(String value) {
    switch (value) {
      case 'types':
        unawaited(showBeCoreTypes(context, _host));
      case 'modules':
        unawaited(showBeModules(context, _host));
      case 'libs':
        unawaited(_openLibs());
      default:
        beLibOnMenu(context, widget.session, _host, value);
    }
  }

  /// 积木库面板（和后端积木页同一个）。关掉以后重新读一遍库：启用的、新建的、导入的马上进积木盒。
  Future<void> _openLibs() async {
    await showBeLibs(context, widget.session, _host, open: (rel) => unawaited(_openLibCanvas(rel)));
    if (mounted) await _attach();
  }

  /// “在画布上改”：进这个库自己的画布（积木页，盖在上面）；回来以后库可能改过了，重新读。
  Future<void> _openLibCanvas(String rel) async {
    final go = ShellScope.maybeOf(context)?.go;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackendScreen(session: widget.session, file: rel.replaceAll('\\', '/'), go: go ?? (_) {}),
      ),
    );
    if (mounted) await _attach();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final host = _host;
    final vars = _page.logic.variables.length;
    final errors = host.errorCount;
    Widget row(IconData icon, String text) => Row(
      children: [
        Icon(icon, size: 20, color: c.textMuted),
        const SizedBox(width: Space.x3),
        Flexible(child: Text(text)),
      ],
    );
    return BlockEditorView(
      key: _editor,
      host: host,
      title: host.canvasType == null ? '页面逻辑' : '类的画布',
      subtitle: errors > 0 ? blockErrorsBrief(errors) : (host.canvasType == null ? null : '「${host.canvasType!.name}」'),
      dockMemoryKey: 'logic-front',
      stars: _stars,
      focusScriptId: _focus,
      onEditTypes: (sel) => unawaited(showBeTypeEditor(context, host, sel)),
      onHostChanged: () => setState(() {}),
      extraActions: [
        if (host.canvasType != null) IconButton(key: const ValueKey('be-canvas-back'), tooltip: '回主画布', onPressed: () => host.openCanvas(null), icon: const Icon(Icons.keyboard_return_rounded)),
        IconButton(
          key: const ValueKey('lc-top-vars'),
          tooltip: '状态',
          onPressed: _openVars,
          icon: Badge(isLabelVisible: vars > 0, label: Text('$vars'), backgroundColor: c.accentFill, textColor: c.onAccent, child: const Icon(Icons.data_object_rounded)),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('lf-more'),
          tooltip: '更多',
          onSelected: _onMenu,
          icon: const Icon(Icons.more_horiz_rounded),
          itemBuilder: (context) => [
            PopupMenuItem(key: const ValueKey('be-menu-types'), value: 'types', child: row(Icons.category_outlined, '类型与类（${host.core.types.length}）…')),
            PopupMenuItem(key: const ValueKey('be-menu-modules'), value: 'modules', child: row(Icons.view_module_outlined, '模块（${host.core.modules.length}）…')),
            ...beLibMenuItems(host, row),
            PopupMenuItem(key: const ValueKey('lf-menu-strict-on'), enabled: false, child: row(Icons.verified_outlined, '新的页面逻辑 · 严格规矩')),
          ],
        ),
      ],
    );
  }
}

/// “升级到新的页面逻辑…”：先说会怎样，点了“升级”才改（一条撤销记录）。升了返回 true。
Future<bool> showLcFrontUpgrade(BuildContext context, LcDocument doc, LcEdit onEdit) async {
  final up = lcUpgradePreview(doc.logic);
  final after = up.errors > 0 ? '照现在的积木，升级后会有 ${up.errors} 处标红要改${up.fixable > 0 ? '（其中 ${up.fixable} 处能一键修）' : ''}，改好之前导出的网页里这一页的逻辑不更新。' : '照现在的积木，升级后没有要改的地方。';
  final ok = await confirmDialog(
    context,
    title: '升级到新的页面逻辑',
    message:
        '升级以后，这一页的逻辑里能用函数（新建积木）、类型与类、模块、错误、“要等的事”和积木库，照严格规矩检查。\n\n'
        '这一页的 ${doc.logic.handlers.length} 个处理会一块一块换成新积木，做的事不变；按旧规矩算的地方（加减乘除、比较、拼接）用“旧规矩”的积木原样留着。\n\n'
        '$after${up.notes.isEmpty ? '' : '\n\n要留意：${up.notes.join('；')}。'}\n\n'
        '存盘以后不能降回旧的页面逻辑（可以马上点撤销）。',
    confirmLabel: '升级',
  );
  if (!ok) return false;
  onEdit((d) => lcFrontStore(d.logic, lcUpgradeToFront(d.logic).doc));
  return true;
}
