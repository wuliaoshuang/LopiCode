// 设计约束（积木逻辑页 · 390×844，浅色 + 深色）— 2026-11-24
// - 顶栏：返回、标题“积木逻辑”，右边胶囊里是 变量（带数量）、看代码、有问题时一个带数字的警示。
// - 主体从上到下是一张张事件卡片（什么时候 → 做什么），一张卡片一件事；卡片怎么画见 logic_handler_widgets.dart。
// - 主操作只有一个：“添加事件”。有处理时钉在底部；一个处理都没有时它在空状态里（不重复出现两个）。
// - 从某个控件点进来时只看它的处理，顶上一个可关掉的标签“只看：…”。
// - 所有改动都走 onEdit（每次一条撤销记录）；提交后从最近见到的文档重新读，不留着旧对象。
import 'dart:async';

import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_block_widgets.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_code_sheet.dart';
import 'package:lopicode/lowcode/logic_event_sheet.dart';
import 'package:lopicode/lowcode/logic_expr_sheet.dart';
import 'package:lopicode/lowcode/logic_handler_widgets.dart';
import 'package:lopicode/lowcode/logic_issues_sheet.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_palette_sheet.dart';
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 整页的积木逻辑编辑器。[doc] 是搭建页手里那份活的文档；[initialNodeId] 不为空时先看这个组件的事件。
class LogicScreen extends StatefulWidget {
  const LogicScreen({super.key, required this.doc, required this.onEdit, this.initialNodeId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String? initialNodeId;

  @override
  State<LogicScreen> createState() => _LogicScreenState();
}

class _LogicScreenState extends State<LogicScreen> {
  /// 最近见到的文档：每次提交后换成回调里拿到的那份（搭建页撤销重做后会换对象）。
  late LcDocument _doc = widget.doc;
  late String? _filter = widget.initialNodeId;

  /// 选中的是哪个处理的哪一块；`_selPath` 为 null 而 `_selHandler` 不为 null＝点名的是处理本身。
  String? _selHandler;
  LcBlockPath? _selPath;
  final GlobalKey _anchor = GlobalKey();
  final ScrollController _scroll = ScrollController();

  late final LcHandlerActions _actions = LcHandlerActions(
    select: _select,
    editArg: _editArg,
    addAt: _addAt,
    act: _act,
    showIssues: _blockIssues,
    drop: _drop,
    dragging: _dragging,
    retarget: _retarget,
    delete: _deleteHandler,
  );

  @override
  void didUpdateWidget(LogicScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.doc, widget.doc)) _doc = widget.doc;
  }

  // 拖动积木时：手指靠近列表上下边缘就自动滚（不然长的处理没法拖到屏幕外的位置）。
  Timer? _edgeTimer;
  double? _pointerY;

  void _dragging(bool active) {
    _edgeTimer?.cancel();
    _edgeTimer = active ? Timer.periodic(const Duration(milliseconds: 16), (_) => _edgeScroll()) : null;
  }

  void _edgeScroll() {
    final y = _pointerY;
    final box = _listKey.currentContext?.findRenderObject();
    if (y == null || !mounted || !_scroll.hasClients || box is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero).dy, bottom = top + box.size.height;
    // 离列表上下边 60px 以内开始滚，越靠边越快（每 16 毫秒最多 16px）。
    final step = y < top + 60 ? -((top + 60 - y) / 60).clamp(0.2, 1.0) * 16 : (y > bottom - 60 ? ((y - (bottom - 60)) / 60).clamp(0.2, 1.0) * 16 : 0.0);
    if (step == 0) return;
    final next = (_scroll.offset + step).clamp(0.0, _scroll.position.maxScrollExtent);
    if (next != _scroll.offset) _scroll.jumpTo(next);
  }

  final _listKey = GlobalKey();

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 提交一次改动＝搭建页的一条撤销记录。只在回调给的 `d` 上改。
  void _commit(void Function(LcDocument d) change) {
    widget.onEdit((d) {
      change(d);
      _doc = d;
    });
    if (mounted) setState(() {});
  }

  List<LcHandler> get _visible => [
    for (final h in _doc.logic.handlers)
      if (_filter == null || h.target == _filter) h,
  ];

  LcBlock? _block(String hid, LcBlockPath path) => _doc.logic.handler(hid)?.blockAt(path);

  void _select(String hid, LcBlockPath path) => setState(() {
    final same = _selHandler == hid && _selPath != null && lcSamePath(_selPath!, path);
    _selHandler = same ? null : hid;
    _selPath = same ? null : path;
  });

  /// 选中并滚到某个处理（`path` 为 null＝处理本身）。卡片是懒加载的，没搭出来就先估个位置跳过去再找。
  void _reveal(String hid, LcBlockPath? path) {
    setState(() {
      if (_filter != null && _doc.logic.handler(hid)?.target != _filter) _filter = null;
      _selHandler = hid;
      _selPath = path;
    });
    _scrollToAnchor(hid, 6);
  }

  void _scrollToAnchor(String hid, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _anchor.currentContext;
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 200)));
        return;
      }
      final list = _visible;
      final i = list.indexWhere((h) => h.id == hid);
      if (tries <= 0 || i < 0 || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent * (list.length < 2 ? 0 : i / (list.length - 1)));
      _scrollToAnchor(hid, tries - 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// 这个参数想要什么类型的值（目录里没写死的，看变量 / 属性来定）。
  String _wantType(LcBlock b, LcArgSpec arg) {
    if (arg.valueType != LcType.any) return arg.valueType;
    final name = b.args['name'];
    if (b.op == 'setVar' && name is String) return _doc.logic.variable(name)?.type ?? LcType.any;
    if (b.op == 'setProp' && arg.name == 'value') return b.args['prop'] == 'visible' ? LcType.boolean : LcType.text;
    return LcType.any;
  }

  Future<void> _editArg(String hid, LcBlockPath path, LcArgSpec arg) async {
    final h = _doc.logic.handler(hid);
    final b = h?.blockAt(path);
    if (h == null || b == null) return;
    final current = b.args[arg.name];
    void put(void Function(LcDocument d, LcBlock block) change) => _commit((d) {
      final block = d.logic.handler(hid)?.blockAt(path);
      if (block != null) change(d, block);
    });
    switch (arg.kind) {
      case LcArgKind.expr:
        final next = await showLcExprSheet(context, read: () => _doc, edit: _commit, title: arg.label, initial: current, valueType: _wantType(b, arg), event: h.event);
        if (next != null && mounted) put((_, block) => block.args[arg.name] = next);
      case LcArgKind.variable:
        final pick = await showLcVariablePicker(
          context,
          _doc,
          title: arg.optional ? '结果放进哪个变量？' : '选一个变量',
          selected: current is String ? current : null,
          optional: arg.optional,
          suggestType: b.op == 'changeVar' ? 'number' : (b.op == 'fetch' ? 'text' : null),
        );
        if (pick == null || !mounted || (pick.create == null && pick.name == current)) return;
        put((d, block) {
          lcApplyVarDraft(d.logic, pick.create);
          block.args[arg.name] = pick.name;
        });
      case LcArgKind.node:
        final id = await showLcNodePicker(context, _doc, title: '选一个控件', selected: current is String ? current : null);
        if (id == null || !mounted || id == current) return;
        put((d, block) {
          block.args[arg.name] = id;
          // 换了控件，原来要改的属性它可能没有（比如从按钮换成输入框）：换成它有的第一个。
          final type = d.find(id)?.type;
          final prop = block.args['prop'];
          if (block.op == 'setProp' && type != null && prop is String && !propFitsNode(prop, type)) _setProp(block, writablePropsFor(type).first);
        });
      case LcArgKind.choice:
        var values = arg.choices;
        final node = b.args['node'];
        final type = b.op == 'setProp' && arg.name == 'prop' && node is String ? _doc.find(node)?.type : null;
        if (type != null) values = writablePropsFor(type);
        final v = await showLcChoicePicker(context, title: arg.label, values: values, labelOf: arg.choiceLabel, selected: current is String ? current : null);
        if (v == null || !mounted || v == current) return;
        put((_, block) => block.op == 'setProp' && arg.name == 'prop' ? _setProp(block, v) : block.args[arg.name] = v);
      default:
        break;
    }
  }

  /// 改“改什么”时顺手把值换成对得上的类型：显示 / 隐藏要“是否”，别的要文字。
  void _setProp(LcBlock block, String prop) {
    final wasBool = block.args['prop'] == 'visible';
    block.args['prop'] = prop;
    if (prop == 'visible' && !wasBool) block.args['value'] = exBool(true);
    if (prop != 'visible' && wasBool) block.args['value'] = exText('');
  }

  bool _tooDeep(LcBlockPath parent, int height) {
    if (parent.length + height - 1 <= LcBlock.maxDepth) return false;
    showSnack(context, '积木套得太深了（最多 ${LcBlock.maxDepth + 1} 层），放不进去。');
    return true;
  }

  Future<void> _addAt(String hid, LcDropSpot spot) async {
    final h = _doc.logic.handler(hid);
    if (h == null || _tooDeep(spot.parent, 1)) return;
    final parent = h.blockAt(spot.parent);
    final spec = parent == null ? null : lcBlockSpecs[parent.op];
    final where = parent == null ? '加到「${describeHandler(h, _doc)}」里' : '加到“${describeBlock(parent, _doc)}”的“${(spot.inElse ? spec?.elseLabel : spec?.bodyLabel) ?? '里面'}”里';
    final op = await showLcPalette(context, where: where);
    if (op == null || !mounted) return;
    _commit((d) => d.logic.handler(hid)?.insertBlock(spot.parent, newBlock(op, d), inElse: spot.inElse, index: spot.index));
    final list = _doc.logic.handler(hid)?.listAt(spot.parent, inElse: spot.inElse);
    if (list == null || list.isEmpty) return;
    setState(() {
      _selHandler = hid;
      _selPath = [...spot.parent, lcStep(spot.index.clamp(0, list.length - 1), inElse: spot.inElse)];
    });
  }

  Future<void> _act(String hid, LcBlockPath path, LcBlockAction action) async {
    final b = _block(hid, path);
    if (b == null) return;
    final parent = path.sublist(0, path.length - 1);
    final last = path.last;
    switch (action) {
      case LcBlockAction.up || LcBlockAction.down:
        final delta = action == LcBlockAction.up ? -1 : 1;
        _commit((d) => d.logic.handler(hid)?.shiftBlock(path, delta));
        setState(() => _selPath = [...parent, lcStep(last.index + delta, inElse: last.inElse)]);
      case LcBlockAction.copy:
        _commit((d) {
          final h = d.logic.handler(hid);
          final src = h?.blockAt(path);
          if (h != null && src != null) h.insertBlock(parent, src.clone(), inElse: last.inElse, index: last.index + 1);
        });
      case LcBlockAction.delete:
        final inside = b.body.length + b.orElse.length;
        if (inside > 0) {
          final ok = await confirmDialog(context, title: '删除这块积木？', message: '“${describeBlock(b, _doc)}”里面的积木也会一起删掉。', confirmLabel: '删除', danger: true);
          if (!ok || !mounted) return;
        }
        _commit((d) => d.logic.handler(hid)?.removeBlock(path));
        setState(() => _selHandler = _selPath = null);
      case LcBlockAction.addBelow:
        await _addAt(hid, (parent: parent, inElse: last.inElse, index: last.index + 1));
    }
  }

  void _drop(String hid, LcBlockPath from, LcDropSpot spot) {
    final b = _block(hid, from);
    if (b == null || !lcCanDrop(from, spot) || _tooDeep(spot.parent, b.height)) return;
    _commit((d) => d.logic.handler(hid)?.moveBlock(from, spot.parent, inElse: spot.inElse, index: spot.index));
    setState(() => _selHandler = _selPath = null);
  }

  void _blockIssues(String hid, LcBlockPath path) {
    final list = [
      for (final i in validateLogic(_doc))
        if (i.handlerId == hid && lcSamePath(i.path, path)) i,
    ];
    if (list.isNotEmpty) unawaited(showLcIssuesSheet(context, list, title: path.isEmpty ? '这个事件的问题' : '这块积木的问题', jump: false));
  }

  Future<void> _allIssues() async {
    final issue = await showLcIssuesSheet(context, validateLogic(_doc));
    if (issue == null || !mounted) return;
    final hid = issue.handlerId;
    if (hid == null) return _openVars(); // 变量本身的问题：去变量面板改
    _reveal(hid, issue.path.isEmpty ? null : issue.path);
  }

  Future<void> _openVars() async {
    await showLcSheet<void>(context, (_) => LcVarsSheet(read: () => _doc, edit: _commit));
    if (mounted) setState(() {});
  }

  Future<void> _addEvent() async {
    final pick = await showLcAddEvent(context, _doc, preferTarget: _filter);
    if (pick == null || !mounted) return;
    String? id;
    _commit((d) => id = d.logic.addHandler(pick.event, target: pick.target)?.id);
    if (id != null) _reveal(id!, null);
  }

  Future<void> _retarget(String hid) async {
    final h = _doc.logic.handler(hid);
    if (h == null) return;
    final id = await showLcNodePicker(context, _doc, title: h.event == 'input' ? '哪个输入框？' : '点击哪个控件？', selected: h.target, enabled: (n) => lcEventFitsNode(h.event, n));
    if (id == null || !mounted || id == h.target) return;
    _commit((d) => d.logic.handler(hid)?.target = id);
    _reveal(hid, null);
  }

  Future<void> _deleteHandler(String hid) async {
    final h = _doc.logic.handler(hid);
    if (h == null) return;
    final ok = await confirmDialog(context, title: '删除这个事件？', message: '「${describeHandler(h, _doc)}」和它里面的 ${h.body.length} 块积木都会删掉。', confirmLabel: '删除', danger: true);
    if (!ok || !mounted) return;
    _commit((d) => d.logic.removeHandler(hid));
    setState(() => _selHandler = _selPath = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final issues = validateLogic(_doc);
    final byHandler = <String, List<LcLogicIssue>>{};
    for (final i in issues) {
      if (i.handlerId != null) (byHandler[i.handlerId!] ??= []).add(i);
    }
    final handlers = _visible;
    final vars = _doc.logic.variables.length;
    final filter = _filter;
    final addButton = FilledButton.icon(key: const ValueKey('lc-add-event'), onPressed: _addEvent, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('添加事件'));
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: ShellAppBar(
        title: '积木逻辑',
        background: c.canvas,
        actions: [
          IconButton(
            key: const ValueKey('lc-top-vars'),
            tooltip: '变量',
            onPressed: _openVars,
            icon: Badge(isLabelVisible: vars > 0, label: Text('$vars'), backgroundColor: c.accentFill, textColor: c.onAccent, child: const Icon(Icons.data_object_rounded)),
          ),
          IconButton(key: const ValueKey('lc-top-code'), tooltip: '看代码', onPressed: () => showLcCodeSheet(context, _doc), icon: const Icon(Icons.code_rounded)),
          if (issues.isNotEmpty)
            IconButton(
              key: const ValueKey('lc-top-issues'),
              tooltip: '问题',
              onPressed: _allIssues,
              icon: Badge(
                label: Text('${issues.length}'),
                backgroundColor: c.danger,
                textColor: c.surface,
                child: Icon(Icons.warning_amber_rounded, color: c.danger),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: const ValueKey('lc-filter'),
                  label: Text('只看：${describeNode(_doc, filter).replaceAll(RegExp('[「」]'), '')}'),
                  deleteButtonTooltipMessage: '看全部事件',
                  onDeleted: () => setState(() => _filter = null),
                ),
              ),
            ),
          Expanded(
            child: handlers.isEmpty
                ? EmptyState(icon: Icons.extension_outlined, title: filter == null ? '还没有任何逻辑' : '这个控件还没有事件', message: '先加一个事件（什么时候），再往里拼积木（做什么）。\n比如：点击按钮时 → 把 count 加上 1。', action: addButton)
                : Listener(
                    key: _listKey,
                    onPointerDown: (e) => _pointerY = e.position.dy,
                    onPointerMove: (e) => _pointerY = e.position.dy,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x3, Space.x6),
                      itemCount: handlers.length,
                      itemBuilder: (context, i) {
                        final h = handlers[i];
                        final mine = _selHandler == h.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: Space.x3),
                          child: LcHandlerCard(
                            key: ValueKey('lc-card-${h.id}'),
                            doc: _doc,
                            handler: h,
                            issues: byHandler[h.id] ?? const [],
                            actions: _actions,
                            selected: mine ? _selPath : null,
                            headSelected: mine && _selPath == null,
                            anchor: mine ? _anchor : null,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: handlers.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3), child: addButton),
            ),
    );
  }
}
