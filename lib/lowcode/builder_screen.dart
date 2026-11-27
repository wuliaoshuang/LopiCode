// 设计约束（低代码搭建 · 390×844）
// - 画布是主角：可缩放 / 平移，按组件的最终样式渲染（画布本身在 canvas_view.dart）。
// - 顶栏是全应用统一的悬浮顶栏（lib/ui/top_bar.dart）：没有底色，画布从屏幕最顶铺起。上面只有：左按钮、页面名
//   （下面一行小字“屏宽档 · 保存状态”）、“⋮”（不常点的：屏宽与缩放、积木逻辑、自定义组件、导出、改标题）。
// - 顶栏以下是共用的搭建台（editor_workbench_widgets.dart）：画布 → 选中条 → 最底下的工具条（添加 / 图层 / 撤销 / 重做 / 预览）。
//   常点的都在拇指够得着的底部。
// - 选中条：“选上一层”和名字在左；常用 / 样式 / 逻辑 在右（有逻辑的组件“逻辑”带小圆点），打开的是同一张合一面板的三页
//   （inspector_sheet.dart：贴在底部、不挡画布，点另一个组件面板跟着换）；其余收进“更多操作”，和长按组件出来的菜单是同一份。
// - 图层、自定义组件放进底部面板，积木逻辑是单独一页，不和画布抢地方。
// - 存盘：改完停手 0.4 秒才存一次（连着改不反复写）；去预览、离开、退到后台前先把没存的存掉。没存上要写出原因。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_bars_widgets.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/canvas_view_sheet.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_sheet.dart';
import 'package:lopicode/lowcode/component_sheet.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/editor_recents.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_sheet.dart';
import 'package:lopicode/lowcode/front_store.dart';
import 'package:lopicode/lowcode/image_pick_sheet.dart';
import 'package:lopicode/lowcode/inspector_sheet.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select_widgets.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/node_actions.dart';
import 'package:lopicode/lowcode/pages_sheet.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/save_queue.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/state_screen.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/theme_vars_screen.dart';
import 'package:lopicode/lowcode/top_shared.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/logic_front_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// 这两样原来就定义在这个文件里，别处（打包页等）还从这里引用。
export 'package:lopicode/lowcode/code_sheet.dart' show CodeSheetBody;
export 'package:lopicode/lowcode/palette_widgets.dart' show lcIcon;

part 'builder_screen_actions.dart';

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key, required this.session, this.initialSelection});
  final ProjectSession session;

  /// 测试 / 截图用。
  final String? initialSelection;

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> with WidgetsBindingObserver, LcMultiSelectHost<BuilderScreen> {
  @override
  LcDocument get multiDoc => _doc!;
  @override
  LcEdit get multiEdit => _apply;
  @override
  void multiSelectSingle(String? id) => setState(() => _selected = id);

  /// 给拆出去的动作（builder_screen_actions.dart）用：它们不在这个类里面，不能直接调 setState。
  void _mut(VoidCallback fn) => setState(fn);

  LcDocument? _doc;
  LcHistory? _history;
  String? _loadError;
  bool _missing = false;
  String? _selected;
  int _presetWidth = 0;

  /// 画布现在按哪一档屏宽看（null＝手机）。不是手机时页面画成那一档的起算宽度，“样式”页改的只记成那一档的差别。
  String? _bp;
  bool _showBoxModel = true;
  // 每一页一个工作台（各有各的缩放、滚到哪儿、开着的面板）：换页时整个换掉，不把上一页的状态带过来。
  final Map<String, GlobalKey<EditorWorkbenchState>> _benches = {};
  GlobalKey<EditorWorkbenchState> get _bench => _benches.putIfAbsent(_doc?.page.id ?? '', GlobalKey.new);
  late final PaletteRecents _recents = PaletteRecents(onChanged: _saveRecents);
  late final SaveQueue<LcDocument> _saver = SaveQueue<LcDocument>(
    snapshot: () {
      final copy = LcDocument.parse(_doc!.encode());
      lcCopyLoaded(_doc!, copy);
      return copy;
    },
    write: (snapshot) async {
      await saveLowcodePage(widget.session.guard, snapshot);
      widget.session.filesChanged();
    },
    describeError: describeSaveError,
    onState: _onSaveState,
  );

  File get _file => File(widget.session.guard.resolve(kLowcodePageFile));

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    WidgetsBinding.instance.addObserver(this);
    _load();
    unawaited(_loadRecents()); // 读不到就当没用过，不用等
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saver.dispose()); // 没存的照样存完；页面已经关了，不等
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台：没存的马上存（应用可能被系统收走）。
    if (state != AppLifecycleState.resumed) unawaited(_saver.flush());
  }

  Future<void> _loadRecents() async {
    final keys = await loadPaletteRecent(widget.session.guard);
    // 读回来之前已经用过别的了：以刚用的为准。
    if (mounted && _recents.keys.isEmpty && keys.isNotEmpty) setState(() => _recents.keys = keys);
    final folded = await loadLayersCollapsed(widget.session.guard);
    if (mounted && _layersCollapsed.isEmpty) _layersCollapsed = folded;
  }

  void _saveRecents(List<String> keys) {
    if (mounted) setState(() {});
    // 不等：记不住只是下次打开“常用”回到起步的那几个，不影响搭建；原因记进错误日志。
    unawaited(savePaletteRecent(widget.session.guard, keys).catchError((Object e, StackTrace st) => CrashLog.instance.record(e, st, source: '低代码·常用组件', fatal: false)));
  }

  void _onSaveState(SaveState state) {
    if (!mounted) return;
    setState(() {});
    if (state == SaveState.failed) showSnack(context, '保存失败：${_saver.lastError}');
  }

  Future<void> _load() async {
    try {
      // 这个文件要是还有排着队没写完的（刚存的、Agent 刚改的），等它写完再读：读到的一定是最新那份。
      await pendingWriteOf(_file);
      if (!await _file.exists()) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final doc = LcDocument.parse(await _file.readAsString());
      await lcAttachLibs(widget.session.guard, doc); // 项目里的积木库：页面逻辑用上的库从这里找
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _history = LcHistory(doc);
        _missing = false;
        _loadError = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } on FileSystemException catch (e) {
      if (mounted) setState(() => _loadError = '读不了 $kLowcodePageFile：${e.osError?.message ?? e.message}');
    }
  }

  Future<void> _createFresh() async {
    final doc = LcDocument.starter(widget.session.project.name);
    try {
      await saveLowcodePage(widget.session.guard, doc);
    } on FileSystemException catch (e) {
      if (mounted) showSnack(context, '新建页面失败：${describeSaveError(e)}');
      return;
    }
    widget.session.filesChanged();
    await _load();
  }

  /// 所有修改都走这里：改模型 → 记历史 → 存盘并重新导出网页。
  void _apply(void Function(LcDocument doc) change) {
    final doc = _doc!;
    setState(() {
      change(doc);
      lcLinkInstances(doc); // 实例的插槽跟着定义走：定义可能刚被改过
    });
    _history!.record(doc);
    _save();
  }

  /// 记一笔“有改动”：停手以后才真的存（见 save_queue.dart）。
  void _save() => _saver.markDirty();

  void _restore(LcDocument? doc) {
    if (doc == null) return;
    // 退掉 / 重做的那一步在别的页上：跟过去，并说一声（不然人看着当前页会以为没反应）。
    final moved = doc.page.id != _doc!.page.id;
    if (moved) showEditorHint(context, '已换到「${doc.title}」：刚才那一步是在这一页上做的。');
    lcCopyLoaded(_doc!, doc);
    setState(() {
      _doc = doc;
      if (_selected != null && doc.find(_selected!) == null) _selected = null;
      multiSync();
    });
    _save();
  }

  /// 点组件栏：加进选中的容器；选中的不是容器就加在它后面；没选中加到页面末尾。
  String? _addByTap(String type, [String? ref]) {
    final doc = _doc!;
    final sel = _selected == null ? null : doc.find(_selected!);
    final node = doc.newNode(type);
    if (ref != null) node.props['ref'] = ref; // 自定义组件的实例
    _apply((d) {
      lcAdoptNewNav(d, node);
      lcAdoptNewTop(d, node);
      if (sel != null && sel.isContainer && type != 'dialog') {
        d.insert(sel.id, node);
      } else if (sel != null && sel.id != d.root.id && type != 'dialog') {
        // 弹窗是整页的东西：永远加在页面最后
        final parent = d.parentOf(sel.id)!;
        d.insert(parent.id, node, parent.children.indexOf(sel) + 1);
      } else {
        d.insert(d.root.id, node);
      }
    });
    setState(() => _selected = node.id);
    return node.id;
  }

  void _drop(LcDrag drag, String parentId, int index) {
    if (multiDrop(drag, parentId, index)) return;
    if (drag.type != null) {
      final node = _doc!.newNode(drag.type!);
      if (drag.ref != null) node.props['ref'] = drag.ref;
      _apply((d) {
        lcAdoptNewNav(d, node);
        lcAdoptNewTop(d, node);
        lcInsertAt(d, parentId, node, index);
      });
      setState(() => _selected = node.id);
    } else {
      _apply((d) => lcMoveTo(d, drag.nodeId!, parentId, index));
      setState(() => _selected = drag.nodeId);
    }
  }

  bool _canDrop(LcDrag drag, String parentId) {
    final many = multiCanDrop(drag, parentId);
    if (many != null) return many;
    if (drag.nodeId == null) return true;
    final node = _doc!.find(drag.nodeId!);
    if (node == null) return false;
    // 不能拖进自己或自己的后代里
    bool contains(LcNode n) => n.id == lcSplitSlotId(parentId).$1 || n.children.any(contains);
    return !contains(node);
  }

  late final LcImages _images = LcImages(widget.session.guard, onImported: widget.session.filesChanged);
  Set<String> _layersCollapsed = {};

  /// 图层面板：点一行选中（画布滚过去）、面板不关；拖动排序走统一的修改入口（一次一条撤销）。
  Future<void> _openLayers() async {
    _bench.currentState?.closeInspector();
    await showLayerSheet(
      context,
      doc: () => _doc!,
      selected: _selected,
      onEdit: _apply,
      multi: LayerMulti(ids: () => multiOn ? multiIds : null, setOn: (on) => on ? multiEnter() : multiExit(), tap: multiTap),
      collapsed: _layersCollapsed,
      onCollapsed: (ids) {
        _layersCollapsed = ids;
        // 记不住只是下次打开全展开着，不打扰她；原因记进错误日志。
        unawaited(saveLayersCollapsed(widget.session.guard, ids).catchError((Object e, StackTrace st) => CrashLog.instance.record(e, st, source: '低代码·图层折叠', fatal: false)));
      },
      onSelect: (id) {
        setState(() => _selected = id);
        WidgetsBinding.instance.addPostFrameCallback((_) => _bench.currentState?.canvas?.revealNode(id));
      },
      onMove: (id, parentId, index) {
        _apply((d) => d.move(id, parentId, index));
        setState(() => _selected = id);
      },
    );
    _refresh();
  }

  // 面板 / 页面开着的时候文档可能被改过（甚至被撤销换成另一个对象）：关掉以后重画一遍，选中的组件没了就取消选中。
  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (_selected != null && _doc?.find(_selected!) == null) _selected = null;
      if (_doc != null) multiSync();
    });
  }

  void _openInspector(InspectorPage page) => _bench.currentState?.openInspector(page);

  /// “事件”页的“＋ 加逻辑”：先把这个事件的帽子积木建好（一条撤销），再进积木页接着搭。
  void _addLogic(String nodeId, String event) {
    _apply((d) => d.logic.addHandler(event, target: nodeId));
    unawaited(_openLogic(nodeId));
  }

  /// 长按一个组件没挪就松手：选中它，在手指那儿出菜单。
  Future<void> _nodeMenu(String id, Offset at) async {
    final node = _doc?.find(id);
    if (node == null) return;
    if (multiOn) {
      multiTap(id); // 多选时长按没挪＝加进来 / 移出去
      return;
    }
    setState(() => _selected = id);
    final v = await showLcNodeMenu(context, at, node, fixed: node.type == 'page', avoid: _bench.currentState?.canvas?.nodeScreenRect(id));
    if (v != null && mounted) _nodeAction(v, id);
  }

  void _nodeAction(String v, String id) {
    final doc = _doc!, node = doc.find(id);
    if (node == null) return;
    if (v == 'multi') return multiEnter(id);
    final (done, select) = runLcNodeAction(v, doc, id, _apply);
    if (done) {
      setState(() => _selected = select);
      if (v == 'clip') showEditorHint(context, '已复制，长按别的组件可以“粘贴到它后面”');
    } else if (v == 'delete') {
      unawaited(_delete(node));
    } else {
      unawaited(_componentAction(v, node));
    }
  }

  String get _saveLabel => switch (_saver.state) {
    SaveState.saved => '已保存',
    SaveState.pending => '正在保存…',
    SaveState.failed => '没存上',
  };

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final history = _history;
    final node = doc == null || _selected == null ? null : doc.find(_selected!);
    return Scaffold(
      backgroundColor: BackdropScope.onOf(context) ? Colors.transparent : null, // 有背景图片时页面底色让开（画布自己还有底）
      extendBodyBehindAppBar: true,
      appBar: ShellAppBar(
        background: context.colors.surfaceMuted,
        title: doc?.title ?? '低代码搭建',
        subtitle: doc == null
            ? null
            : '${doc.isMultiPage ? '第 ${doc.pageIndex + 1}/${doc.pages.length} 页 · ' : ''}${_bp == null ? canvasWidthLabel(_presetWidth) : '${lcBpLabel(_bp)} ${kLcBpMinWidth[_bp]}'} · $_saveLabel',
        actions: doc == null
            ? null
            : [
                BuilderBpButton(bp: _bp, onChanged: (v) => setState(() => _bp = v)),
                BuilderPagesButton(count: doc.pages.length, onTap: () => unawaited(_openPages())),
                BuilderMoreMenu(onSelected: _onMenu),
              ],
      ),
      body: _loadError != null
          ? BelowBar(
              child: EmptyState(
                icon: Icons.error_outline,
                title: '页面文件打不开',
                message: '$kLowcodePageFile 的内容有问题：$_loadError',
                action: OutlinedButton(onPressed: _createFresh, child: const Text('用一个新页面覆盖')),
              ),
            )
          : _missing
          ? BelowBar(
              child: EmptyState(
                icon: Icons.dashboard_customize_outlined,
                title: '这个项目还没有低代码页面',
                message: '新建后会在项目里生成 $kLowcodePageFile，\n并自动导出 index.html 和 style.css。',
                action: FilledButton(onPressed: _createFresh, child: const Text('新建页面')),
              ),
            )
          : doc == null
          ? const Center(child: CircularProgressIndicator())
          : LcImageScope(
              resolve: _images.resolve,
              child: EditorWorkbench(
                key: _bench,
                onEdit: _apply,
                pickImage: (from) => _images.pick(context, from),
                onOpenLogic: (id) => unawaited(_openLogic(id)),
                onAddLogic: _addLogic,
                onNodeMenu: (id, at) => unawaited(_nodeMenu(id, at)),
                doc: doc,
                selected: multiOn ? null : _selected,
                marked: multiIds,
                onSelect: (id) => multiOn ? multiTap(id) : setState(() => _selected = id),
                onAdd: _addByTap,
                onDrop: _drop,
                canDrop: _canDrop,
                onDelete: (id) {
                  final n = doc.find(id);
                  if (n != null && !multiDeleteDragged(id)) unawaited(_delete(n));
                },
                onResize: _resize,
                recents: _recents,
                onLayers: () => unawaited(_openLayers()),
                onUndo: history!.canUndo ? () => _restore(history.undo()) : null,
                onRedo: history.canRedo ? () => _restore(history.redo()) : null,
                onPreview: () => unawaited(_preview()),
                presetWidth: _bp == null ? _presetWidth : kLcBpMinWidth[_bp]!,
                bp: _bp,
                showBoxModel: _showBoxModel,
                selectionBar: multiOn ? multiBar() : (node == null ? null : _selectionBar(node)),
              ),
            ),
    );
  }

  Widget _selectionBar(LcNode node) => BuilderSelectionBar(
    doc: _doc!,
    node: node,
    onParent: () {
      final parent = _doc!.parentOf(node.id);
      if (parent != null) setState(() => _selected = parent.id);
    },
    onCommon: () => _openInspector(InspectorPage.common),
    onStyle: () => _openInspector(InspectorPage.style),
    onLogic: () => _openInspector(InspectorPage.events),
    onAction: (v) => _nodeAction(v, node.id),
  );
}
