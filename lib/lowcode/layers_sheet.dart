// 设计约束（低代码 · 图层面板 · 390×844）
// - 底部面板，一行一个组件（行高 44）：▾ 折叠（有内容的容器才有）＋图标＋名字＋一句内容提示；按层级缩进；带逻辑的行尾有 ⚡。
// - 内容主次：名字是主（titleSmall；她起了名字显示名字，没起显示类型名），内容提示是次（bodySmall、灰）；选中的那一行整行浅强调色。
// - 没有主操作。点一行＝选中它，画布滚过去，**面板不关**（想连着点几个不用反复开）；关面板靠下滑 / 点外面 / 返回键。
// - 第 3 期加的（都要页面给了 onEdit 才有）：
//     标题行：左边“图层 · N 个组件”，右边 [多选]（只有字；多选时变成实心的“完成”）。下面一行搜索框（搜名字、类型名、上面的字）。
//     搜索时只列对得上的行（不缩进、不能拖动排序）；清空搜索回到整棵树。
//     改名：点**已经选中**那一行的名字，原地变输入框；键盘“完成”/ 点别处＝改好，清空＝不要名字（回到类型名）。
//     眼睛、锁：选中的那一行行尾两个小按钮；别的行只有“已经隐藏 / 已经锁定”时才显示（点它＝恢复），平时不占地方。
//       隐藏＝只在编辑器的画布上不画，**导出的页面里还在**（要让页面上真的没有它，去“样式”里设不显示）。
//       锁定＝画布上点不中、拖不动（防手滑）；在这里照样能选中、能解锁。
//       设计稿写的是“行上左滑出锁定”，这里改成行尾按钮：面板本身能下滑关闭、行还能长按拖动，再加左滑容易误触，也不好发现。
//     多选：行首多一个勾；点一行＝加进来 / 移出去（只能选同一层的，选不了时标题下面说一句为什么）。
// - 排序：按住一行 280 毫秒拿起，上下拖；一条强调色的线表示“放在这两行之间”；拖到某个容器那一行的右半边＝放进它里面
//   （整行描边）。不能放进自己里面；最顶上那一行不能动。松手才真的挪，一次一条撤销。
// - 折叠状态由页面记在编辑器自己的状态文件里（.lopicode/lowcode-editor.json），不进页面文件。
// - 取用的 tokens：Space.x1/x2/x4/x6、accentSoft / accent（选中、落点）、textFaint（图标、提示）、warning（⚡）。
import 'package:flutter/gestures.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/layers_tree.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 图层面板一行多高。
const double kLayerRowHeight = 44;

class LayerSheet extends StatefulWidget {
  const LayerSheet({
    super.key,
    required this.doc,
    required this.selected,
    required this.onSelect,
    this.onMove,
    this.root,
    this.collapsed,
    this.onCollapsed,
    this.showLogic = true,
    this.onEdit,
    this.multi,
  });

  /// 改文档（改名、隐藏、锁定）。不给＝这三样都没有。
  final LcEdit? onEdit;

  /// 多选的对接口。不给＝标题行没有“多选”。
  final LayerMulti? multi;

  /// 取现在的文档（面板开着的时候文档会被改：拖动排序之后要重新读）。
  final LcDocument Function() doc;

  /// 从哪个组件起列（不给＝整个页面）。
  final LcNode Function()? root;
  final String? selected;
  final void Function(String id) onSelect;

  /// 把一个组件挪到 [parentId] 的第 [index] 个（按挪走之前的顺序数）。不给＝不能拖动排序。
  final void Function(String id, String parentId, int index)? onMove;

  /// 一开始折着哪些；变了通过 [onCollapsed] 告诉页面去记。
  final Set<String>? collapsed;
  final void Function(Set<String> ids)? onCollapsed;

  /// 带逻辑的行要不要标 ⚡（自定义组件里的控件不支持逻辑）。
  final bool showLogic;

  @override
  State<LayerSheet> createState() => _LayerSheetState();
}

/// 图层面板和页面的多选怎么对接（状态在页面那边，见 multi_select_widgets.dart）。
class LayerMulti {
  const LayerMulti({required this.ids, required this.setOn, required this.tap});

  /// 现在选中的几个；null＝没在多选。
  final Set<String>? Function() ids;

  /// 进入 / 退出多选。
  final void Function(bool on) setOn;

  /// 点了一行：加进来 / 移出去。返回 null＝照办了；返回一句话＝没办成的原因。
  final String? Function(String id) tap;
}

class _LayerSheetState extends State<LayerSheet> {
  late String? _selected = widget.selected;
  final TextEditingController _search = TextEditingController();
  String? _renaming;
  String? _multiWhy;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Set<String>? get _multi => widget.multi?.ids();

  void _tapRow(LcNode node) {
    if (_multi != null) {
      final why = widget.multi!.tap(node.id);
      setState(() => _multiWhy = why);
      return;
    }
    setState(() {
      _selected = node.id;
      _renaming = null;
    });
    widget.onSelect(node.id);
  }

  void _edit(String id, void Function(LcNode n) change) {
    widget.onEdit?.call((d) {
      final n = d.find(id);
      if (n != null) change(n);
    });
    if (mounted) setState(() {});
  }

  late final Set<String> _collapsed = {...?widget.collapsed};
  final GlobalKey _rowsKey = GlobalKey();
  String? _drag;
  LayerDrop? _drop;

  LcNode get _root => widget.root?.call() ?? widget.doc().root;

  void _toggle(String id) {
    setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id));
    widget.onCollapsed?.call({..._collapsed});
  }

  void _dragTo(Offset global, List<LayerRow> rows) {
    final box = _rowsKey.currentContext?.findRenderObject();
    final id = _drag;
    if (id == null || box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final next = layerDropTarget(_root, rows, id, local.dy, local.dx, rowHeight: kLayerRowHeight, width: box.size.width);
    if (next != _drop) {
      if (next != null) LcHaptics.overTarget();
      setState(() => _drop = next);
    }
  }

  void _endDrag({required bool cancelled}) {
    final id = _drag, drop = _drop;
    setState(() {
      _drag = null;
      _drop = null;
    });
    if (cancelled || id == null || drop == null) return;
    LcHaptics.drop();
    widget.onMove?.call(id, drop.parentId, drop.index);
    setState(() => _collapsed.remove(drop.parentId)); // 放进折着的容器：展开让她看到放哪儿了
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final all = layerRows(_root, const {});
    final total = all.length;
    final query = _search.text.trim();
    final searching = query.isNotEmpty;
    final rows = searching ? layerSearch(all, query) : layerRows(_root, _collapsed);
    final multi = _multi;
    final drop = _drop;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x2, 0),
              child: Row(
                children: [
                  Expanded(child: Text(multi == null ? '图层 · $total 个组件' : '多选 · 已选 ${multi.length} 个', style: t.titleLarge)),
                  if (widget.multi != null && multi == null)
                    TextButton(key: const Key('lc-layer-multi'), onPressed: () => setState(() => widget.multi!.setOn(true)), child: const Text('多选'))
                  else if (widget.multi != null)
                    FilledButton(
                      key: const Key('lc-layer-multi-done'),
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                      child: const Text('完成'),
                    ),
                ],
              ),
            ),
            if (multi != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text(
                  _multiWhy ?? '点一行加进来，再点一下移出去；点“完成”回到画布接着一起操作。',
                  key: const Key('lc-layer-multi-note'),
                  style: t.bodySmall?.copyWith(color: _multiWhy == null ? c.textFaint : c.danger),
                ),
              ),
            if (widget.onEdit != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2),
                child: TextField(
                  key: const Key('lc-layer-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜名字、类型或上面的字',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: searching
                        ? IconButton(key: const Key('lc-layer-search-clear'), tooltip: '清空', icon: const Icon(Icons.close, size: 18), onPressed: () => setState(_search.clear))
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (searching && rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: Text(
                  '没有对得上“$query”的组件。',
                  key: const Key('lc-layer-search-empty'),
                  style: t.bodyMedium?.copyWith(color: c.textMuted),
                ),
              ),
            Stack(
              key: _rowsKey,
              children: [
                Column(children: [for (final r in rows) _row(context, r, rows)]),
                if (drop != null && !drop.into)
                  Positioned(
                    key: const Key('lc-layer-drop-line'),
                    left: Space.x4 + drop.depth * Space.x4,
                    right: Space.x4,
                    top: (drop.line * kLayerRowHeight - 1).clamp(0.0, rows.length * kLayerRowHeight - 2).toDouble(),
                    height: 2,
                    child: IgnorePointer(child: ColoredBox(color: c.accent)),
                  ),
              ],
            ),
            if (widget.onMove != null && !searching && multi == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
                child: Text('按住一行可以上下拖着排序；拖到容器那一行的右半边＝放进它里面。', style: t.bodySmall?.copyWith(color: c.textFaint)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, LayerRow r, List<LayerRow> rows) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final node = r.node;
    final into = _drop != null && _drop!.into && _drop!.parentId == node.id;
    final multi = _multi;
    final active = multi == null ? node.id == _selected : multi.contains(node.id);
    final searching = _search.text.trim().isNotEmpty;
    final depth = searching ? 0 : r.depth;
    final hint = layerHint(node);
    final canEdit = widget.onEdit != null && multi == null;
    final movable = widget.onMove != null && r.depth > 0 && !searching && multi == null && _renaming == null;
    final row = InkWell(
      key: Key('lc-layer-${node.id}'),
      onTap: () => _tapRow(node),
      child: Container(
        height: kLayerRowHeight,
        decoration: BoxDecoration(
          color: into || active ? c.accentSoft : null,
          border: into ? Border.all(color: c.accent, width: 2) : null,
        ),
        padding: EdgeInsets.only(left: Space.x1 + depth * Space.x4, right: Space.x2),
        child: Opacity(
          opacity: _drag == node.id ? 0.4 : 1,
          child: Row(
            children: [
              if (multi != null)
                SizedBox(
                  width: 32,
                  child: Icon(active ? Icons.check_box : Icons.check_box_outline_blank, key: Key('lc-layer-check-${node.id}'), size: 20, color: active ? c.accent : c.textFaint),
                )
              else if (r.hasChildren && !searching)
                InkWell(
                  key: Key('lc-layer-fold-${node.id}'),
                  onTap: () => _toggle(node.id),
                  customBorder: const CircleBorder(),
                  child: Tooltip(
                    message: r.collapsed ? '展开' : '折叠',
                    child: SizedBox(
                      width: 32,
                      height: kLayerRowHeight,
                      child: Icon(r.collapsed ? Icons.arrow_right : Icons.arrow_drop_down, size: 22, color: c.textMuted),
                    ),
                  ),
                )
              else
                const SizedBox(width: 32),
              Icon(lcIcon(node.type), size: 18, color: active ? c.accent : c.textFaint),
              const SizedBox(width: Space.x2),
              if (_renaming == node.id)
                Expanded(
                  child: _RenameField(
                    initial: node.name,
                    hint: node.spec.label,
                    onDone: (v) {
                      setState(() => _renaming = null);
                      if (v != null && LcNode.cleanName(v) != node.name) _edit(node.id, (n) => n.name = LcNode.cleanName(v));
                    },
                  ),
                )
              else ...[
                // 点已经选中那一行的名字＝改名（没选中的行，点哪儿都是选中）。
                GestureDetector(
                  key: Key('lc-layer-name-${node.id}'),
                  onTap: canEdit && node.id == _selected ? () => setState(() => _renaming = node.id) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140, minHeight: kLayerRowHeight),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: 1,
                      child: Text(
                        layerTitle(node),
                        style: t.titleSmall?.copyWith(color: active ? c.accent : (node.hidden ? c.textFaint : c.text)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(r.collapsed && !searching ? '${node.children.length} 个在里面' : hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
              if (widget.showLogic && widget.doc().logic.handlersFor(node.id).isNotEmpty)
                Tooltip(
                  message: '有逻辑',
                  child: Icon(Icons.bolt, key: Key('lc-layer-logic-${node.id}'), size: 18, color: c.warning),
                ),
              // 眼睛、锁：选中的那一行两个都有；别的行只有“已经隐藏 / 已经锁定”才显示。最顶上那一行（页面）没有。
              if (canEdit && r.depth > 0 && (node.id == _selected || node.hidden))
                _flag(
                  'eye',
                  node,
                  on: node.hidden,
                  tip: node.hidden ? '在编辑器里重新显示' : '在编辑器里先不显示（导出的页面里还在）',
                  icon: node.hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  onTap: () => _edit(node.id, (n) => n.hidden = !n.hidden),
                ),
              if (canEdit && r.depth > 0 && (node.id == _selected || node.locked))
                _flag(
                  'lock',
                  node,
                  on: node.locked,
                  tip: node.locked ? '解锁' : '锁定（画布上点不中、拖不动）',
                  icon: node.locked ? Icons.lock_outline : Icons.lock_open_outlined,
                  onTap: () => _edit(node.id, (n) => n.locked = !n.locked),
                ),
            ],
          ),
        ),
      ),
    );
    if (!movable) return row;
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: kLcLiftAfter, debugOwner: this),
          (g) => g
            ..onLongPressStart = (d) {
              LcHaptics.lift();
              setState(() => _drag = node.id);
              _dragTo(d.globalPosition, rows);
            }
            ..onLongPressMoveUpdate = ((d) => _dragTo(d.globalPosition, rows))
            ..onLongPressEnd = ((_) => _endDrag(cancelled: false))
            ..onLongPressCancel = (() => _endDrag(cancelled: true)),
        ),
      },
      child: row,
    );
  }
}

extension on _LayerSheetState {
  Widget _flag(String name, LcNode node, {required bool on, required String tip, required IconData icon, required VoidCallback onTap}) {
    final c = context.colors;
    return IconButton(
      key: Key('lc-layer-$name-${node.id}'),
      tooltip: tip,
      icon: Icon(icon, size: 18, color: on ? c.accent : c.textMuted),
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 36, height: kLayerRowHeight),
      padding: EdgeInsets.zero,
    );
  }
}

/// 改名用的那个原地输入框：键盘“完成”/ 失去焦点＝交回去；[onDone] 收到 null＝没动。
class _RenameField extends StatefulWidget {
  const _RenameField({required this.initial, required this.hint, required this.onDone});
  final String initial;
  final String hint;
  final void Function(String? name) onDone;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _text = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone(_text.text == widget.initial ? null : _text.text);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('lc-layer-rename'),
    controller: _text,
    focusNode: _focus,
    autofocus: true,
    maxLength: LcNode.maxNameLength,
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(isDense: true, hintText: '起个名字（留空＝${widget.hint}）', counterText: ''),
    onSubmitted: (_) => _finish(),
  );
}

/// 打开图层面板。点一行＝[onSelect]（面板不关）；拖动排序＝[onMove]。面板关掉时这个 Future 完成。
Future<void> showLayerSheet(
  BuildContext context, {
  required LcDocument Function() doc,
  required String? selected,
  required void Function(String id) onSelect,
  void Function(String id, String parentId, int index)? onMove,
  LcNode Function()? root,
  Set<String>? collapsed,
  void Function(Set<String> ids)? onCollapsed,
  bool showLogic = true,
  LcEdit? onEdit,
  LayerMulti? multi,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // 遮罩要淡：点一行以后她要看得见上面的画布滚到了哪儿。
  barrierColor: context.colors.scrimOf(0x14 / 255),
  builder: (_) =>
      LayerSheet(doc: doc, selected: selected, onSelect: onSelect, onMove: onMove, root: root, collapsed: collapsed, onCollapsed: onCollapsed, showLogic: showLogic, onEdit: onEdit, multi: multi),
);
