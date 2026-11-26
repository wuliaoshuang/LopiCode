// 设计约束（低代码 · 图层面板 · 390×844）
// - 底部面板，一行一个组件（行高 44）：▾ 折叠（有内容的容器才有）＋图标＋类型名＋一句内容提示；按层级缩进；带逻辑的行尾有 ⚡。
// - 内容主次：类型名是主（titleSmall），内容提示是次（bodySmall、灰）；选中的那一行整行浅强调色。
// - 没有主操作。点一行＝选中它，画布滚过去，**面板不关**（想连着点几个不用反复开）；关面板靠下滑 / 点外面 / 返回键。
// - 排序：按住一行 280 毫秒拿起，上下拖；一条强调色的线表示“放在这两行之间”；拖到某个容器那一行的右半边＝放进它里面
//   （整行描边）。不能放进自己里面；最顶上那一行不能动。松手才真的挪，一次一条撤销。
// - 折叠状态由页面记在编辑器自己的状态文件里（.lopicode/lowcode-editor.json），不进页面文件。
// - 取用的 tokens：Space.x1/x2/x4/x6、accentSoft / accent（选中、落点）、textFaint（图标、提示）、warning（⚡）。
import 'package:flutter/gestures.dart';
import 'package:lopicode/lowcode/layers_tree.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 图层面板一行多高。
const double kLayerRowHeight = 44;

class LayerSheet extends StatefulWidget {
  const LayerSheet({super.key, required this.doc, required this.selected, required this.onSelect, this.onMove, this.root, this.collapsed, this.onCollapsed, this.showLogic = true});

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

class _LayerSheetState extends State<LayerSheet> {
  late String? _selected = widget.selected;
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
    final rows = layerRows(_root, _collapsed);
    final total = layerRows(_root, const {}).length;
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
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('图层 · $total 个组件', style: t.titleLarge),
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
            if (widget.onMove != null)
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
    final active = node.id == _selected;
    final into = _drop != null && _drop!.into && _drop!.parentId == node.id;
    final hint = node.strProp('text') ?? node.strProp('placeholder') ?? '';
    final movable = widget.onMove != null && r.depth > 0;
    final row = InkWell(
      key: Key('lc-layer-${node.id}'),
      onTap: () {
        setState(() => _selected = node.id);
        widget.onSelect(node.id);
      },
      child: Container(
        height: kLayerRowHeight,
        decoration: BoxDecoration(
          color: into || active ? c.accentSoft : null,
          border: into ? Border.all(color: c.accent, width: 2) : null,
        ),
        padding: EdgeInsets.only(left: Space.x1 + r.depth * Space.x4, right: Space.x4),
        child: Opacity(
          opacity: _drag == node.id ? 0.4 : 1,
          child: Row(
            children: [
              if (r.hasChildren)
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
              Text(node.spec.label, style: t.titleSmall?.copyWith(color: active ? c.accent : c.text)),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(r.collapsed ? '${node.children.length} 个在里面' : hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (widget.showLogic && widget.doc().logic.handlersFor(node.id).isNotEmpty)
                Tooltip(
                  message: '有逻辑',
                  child: Icon(Icons.bolt, key: Key('lc-layer-logic-${node.id}'), size: 18, color: c.warning),
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
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // 遮罩要淡：点一行以后她要看得见上面的画布滚到了哪儿。
  barrierColor: const Color(0x14000000),
  builder: (_) => LayerSheet(doc: doc, selected: selected, onSelect: onSelect, onMove: onMove, root: root, collapsed: collapsed, onCollapsed: onCollapsed, showLogic: showLogic),
);
