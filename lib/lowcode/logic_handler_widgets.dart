// 设计约束（一个事件处理的卡片 · 390×844）— 2026-11-24
// - 一张白卡片＝一个“什么时候 → 做什么”：最上面是金棕色的“帽子”（事件 + 目标的人话，左上右上是大圆角，像一顶帽子），
//   紧贴着往下是它的积木栈，最后一行虚线“加积木”。从上往下读就是执行的顺序。
// - 帽子上只有一个“更多”按钮（改目标控件 / 删除这个事件）；有问题时多一个红 / 黄的标记。
// - 目标控件已经不在页面里：帽子下面一行说明，带“改目标”“删除”两个按钮（这种处理不会被触发，要人来决定）。
// - 拖动只在同一张卡片里生效；插入位的横条由卡片自己记（拖到别的卡片上不接）。
import 'package:lopicode/lowcode/logic_block_widgets.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 卡片向页面要做的事。路径为空＝说的是处理本身（帽子）。
class LcHandlerActions {
  const LcHandlerActions({
    required this.select,
    required this.editArg,
    required this.addAt,
    required this.act,
    required this.showIssues,
    required this.drop,
    required this.dragging,
    required this.retarget,
    required this.delete,
  });
  final void Function(String handlerId, LcBlockPath path) select;
  final void Function(String handlerId, LcBlockPath path, LcArgSpec arg) editArg;
  final void Function(String handlerId, LcDropSpot spot) addAt;
  final void Function(String handlerId, LcBlockPath path, LcBlockAction action) act;
  final void Function(String handlerId, LcBlockPath path) showIssues;
  final void Function(String handlerId, LcBlockPath from, LcDropSpot spot) drop;
  final void Function(bool active) dragging;
  final void Function(String handlerId) retarget;
  final void Function(String handlerId) delete;
}

class LcHandlerCard extends StatefulWidget {
  const LcHandlerCard({super.key, required this.doc, required this.handler, required this.issues, required this.actions, this.selected, this.headSelected = false, this.anchor});
  final LcDocument doc;
  final LcHandler handler;

  /// 这个处理的全部校验问题（含处理本身的）。
  final List<LcLogicIssue> issues;
  final LcHandlerActions actions;

  /// 选中的积木在这张卡片里时是它的路径。
  final LcBlockPath? selected;

  /// 被“跳到这里”点名的是处理本身（帽子描边）。
  final bool headSelected;

  /// 给被选中的积木 / 帽子用的 key（页面靠它滚过去）。
  final Key? anchor;

  @override
  State<LcHandlerCard> createState() => _LcHandlerCardState();
}

class _LcHandlerCardState extends State<LcHandlerCard> implements LcStackHost {
  LcDropSpot? _hint;

  String get _id => widget.handler.id;

  @override
  LcDocument get doc => widget.doc;
  @override
  LcHandler get handler => widget.handler;
  @override
  bool isSelected(LcBlockPath path) => widget.selected != null && lcSamePath(widget.selected!, path);
  @override
  Key? anchorFor(LcBlockPath path) => isSelected(path) ? widget.anchor : null;
  @override
  List<LcLogicIssue> issuesAt(LcBlockPath path) => [
    for (final i in widget.issues)
      if (i.path.isNotEmpty && lcSamePath(i.path, path)) i,
  ];
  @override
  void select(LcBlockPath path) => widget.actions.select(_id, path);
  @override
  void editArg(LcBlockPath path, LcArgSpec arg) => widget.actions.editArg(_id, path, arg);
  @override
  void addAt(LcDropSpot spot) => widget.actions.addAt(_id, spot);
  @override
  void act(LcBlockPath path, LcBlockAction action) => widget.actions.act(_id, path, action);
  @override
  void showIssues(LcBlockPath path) => widget.actions.showIssues(_id, path);
  @override
  LcDropSpot? get dropHint => _hint;

  @override
  void hover(LcDropSpot? spot) {
    final old = _hint;
    final same = spot == null ? old == null : (old != null && lcSamePath(old.parent, spot.parent) && old.inElse == spot.inElse && old.index == spot.index);
    if (same || !mounted) return;
    setState(() => _hint = spot);
  }

  @override
  void drop(LcDragData data, LcDropSpot spot) => widget.actions.drop(_id, data.path, spot);

  @override
  void dragging(bool active) => widget.actions.dragging(active);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = widget.handler;
    final tone = lcToneOf(context, kLcEventCategory);
    final headIssues = [
      for (final i in widget.issues)
        if (i.path.isEmpty) i,
    ];
    final target = h.target;
    final lost = h.event != 'load' && (target == null || target.isEmpty || widget.doc.find(target) == null);
    final icon = switch (h.event) {
      'click' => Icons.touch_app_rounded,
      'input' => Icons.keyboard_alt_rounded,
      'load' => Icons.play_arrow_rounded,
      _ => Icons.help_outline_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(Space.x2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            key: widget.headSelected ? widget.anchor : null,
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18), bottom: Radius.circular(8)),
              border: widget.headSelected ? Border.all(color: c.text, width: 2) : null,
            ),
            child: Container(
              key: ValueKey('lc-hat-$_id'),
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(Space.x3, 2, 0, 2),
              decoration: BoxDecoration(
                color: tone.fill,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18), bottom: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: kLcBlockInk),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x2),
                      child: Text(
                        describeHandler(h, widget.doc),
                        style: const TextStyle(color: kLcBlockInk, fontSize: FontSize.sm, fontWeight: FontWeight.w600, height: 1.3),
                      ),
                    ),
                  ),
                  if (headIssues.isNotEmpty)
                    IconButton(
                      key: ValueKey('lc-hat-issue-$_id'),
                      tooltip: '这个事件有问题',
                      onPressed: () => widget.actions.showIssues(_id, const []),
                      icon: Icon(headIssues.any((i) => i.isError) ? Icons.error_rounded : Icons.warning_rounded, size: 20, color: kLcBlockInk),
                    ),
                  PopupMenuButton<String>(
                    key: ValueKey('lc-hat-menu-$_id'),
                    tooltip: '更多',
                    icon: const Icon(Icons.more_horiz_rounded, size: 22, color: kLcBlockInk),
                    onSelected: (v) => v == 'delete' ? widget.actions.delete(_id) : widget.actions.retarget(_id),
                    itemBuilder: (_) => [
                      if (h.event != 'load') const PopupMenuItem(value: 'retarget', child: Text('改目标控件')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('删除这个事件', style: TextStyle(color: c.danger)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (lost)
            Container(
              key: ValueKey('lc-lost-$_id'),
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x1),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target == null || target.isEmpty ? '还没选是哪个控件触发的，这个事件不会被触发。' : '目标控件已不存在，这个事件不会被触发。',
                    style: TextStyle(color: c.danger, fontSize: FontSize.sm, height: 1.4),
                  ),
                  Row(
                    children: [
                      TextButton(key: ValueKey('lc-lost-retarget-$_id'), onPressed: () => widget.actions.retarget(_id), child: const Text('改目标')),
                      TextButton(
                        key: ValueKey('lc-lost-delete-$_id'),
                        onPressed: () => widget.actions.delete(_id),
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          LcBlockStack(host: this, blocks: h.body, parent: const []),
          if (h.body.isNotEmpty) ...[
            const SizedBox(height: Space.x1),
            LcAddSlot(key: ValueKey('lc-append-$_id'), host: this, spot: (parent: const [], inElse: false, index: h.body.length), label: '加积木'),
          ],
        ],
      ),
    );
  }
}
