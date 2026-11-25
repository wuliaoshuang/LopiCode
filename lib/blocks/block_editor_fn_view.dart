// 设计约束（参数小块与“我的积木”的操作，390 宽，浅色 + 深色）— 2026-11-25
// - 参数小块：点一下＝贴着它弹小卡（改名 / 默认值 / 剩下的全收 / 删除）；长按＝拿出一份副本当值用（只能放进它自己这一串）；
//   长按拿起来没挪就松手＝放回去、弹小卡（和点一下一样，不让人白按）。小块后面的“＋”＝加一个参数并马上弹小卡让人起名字。
// - 删参数：别处有调用在用就先问“有 N 处在用，槽里的东西会丢掉”，危险色确认；没有在用的直接删。
// - 语句积木长按拿起来没挪就松手，而且宿主能“包成积木”：放回原处，贴着它弹菜单（只有一项也用菜单——以后这里还会加别的）。
// - 菜单沿用编辑器里别的菜单的样子：一项 44 高、圆角 14、图标 18 中性色 + 一行字。
// - 新建 / 编辑走同一张全屏页（block_look_screen.dart）；页面只管填，数据怎么变全交给宿主，这里保证一次改动一条撤销记录。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_drag_view.dart';
import 'package:lopicode/blocks/block_editor_edit_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_look_screen.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/blocks/block_param_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

mixin BkEditorFn on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas, BkEditorDrag, BkEditorEdit {
  // —— 参数小块 ——

  /// 这个小块所在的参数表：现在有哪些参数、能做什么，以及怎么把改好的表写回去（要在 host.edit 里调）。
  _ParamList? _paramsOf(String scriptId, BkBlock block, BkSlot slot) {
    final tree = host.script(scriptId);
    if (tree == null) return null;
    if (block.isHat) {
      final hp = host.hatParams(tree);
      if (hp == null) return null;
      return _ParamList(
        params: hp.params,
        canDefault: hp.defaults,
        canRest: hp.rest,
        max: hp.max,
        uses: (name) => host.hatParamUses(tree, name),
        write: (next, renamed) {
          final t = host.script(scriptId);
          return t != null && host.setHatParams(t, next, renamed: renamed);
        },
      );
    }
    final b = tree.blockAt(block.path);
    final expr = b == null ? null : asExpr(bkExprAt(b, slot.arg, slot.exprPath));
    final spec = expr == null ? null : host.exprSpec(exprKind(expr) ?? '');
    final field = spec?.paramsArg;
    if (expr == null || spec == null || field == null) return null;
    return _ParamList(
      params: [for (final n in bkExprParams(expr, spec)) BlockParam(n)],
      max: kExprParamMax,
      write: (next, renamed) {
        final t = host.script(scriptId), owner = t?.blockAt(block.path);
        final e = owner == null ? null : asExpr(bkExprAt(owner, slot.arg, slot.exprPath));
        if (t == null || owner == null || e == null) return false;
        e[field] = [for (final p in next) p.name];
        if (renamed != null) host.exprParamRenamed(t, e, renamed.from, renamed.to);
        host.argChanged(t, owner, slot.arg, slot.exprPath);
        return true;
      },
    );
  }

  bool _writeParams(String scriptId, _ParamList list, List<BlockParam> next, {({String from, String to})? renamed}) {
    final before = layout;
    var done = false;
    host.edit(() {
      done = list.write(next, renamed);
      if (done) bkPushDown(host, engine, before, scriptId);
    });
    if (done) unawaited(HapticFeedback.lightImpact());
    return done;
  }

  /// 现在的排布里把同一个位置的第 `index` 个参数小块找回来（在编辑区里的位置）。
  Rect? _chipRect(String scriptId, BkBlock block, BkSlot slot, int index) {
    final placed = layout.placed(scriptId);
    if (placed == null) return null;
    for (final (b, s) in placed.layout.allSlots) {
      if (s.look != BkSlotLook.param || s.param != index) continue;
      final same = block.isHat ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, block.path) && s.arg == slot.arg && bkSameExprPath(s.exprPath, slot.exprPath));
      if (same) return rectToView(s.rect.shift(placed.origin));
    }
    return null;
  }

  @override
  void onParamTap(BkPlaced script, BkBlock block, BkSlot slot) {
    final list = _paramsOf(script.id, block, slot);
    final index = slot.param;
    if (list == null || index == null) return;
    if (slot.look == BkSlotLook.add) {
      if (list.params.length >= list.max) return;
      // 加在最后；最后一个要是“剩下的全收”，新的插在它前面（全收的只能在最后）。
      final fresh = BlockParam(bkFreshParamName([for (final p in list.params) p.name]));
      final rest = list.params.isNotEmpty && list.params.last.rest;
      final at = rest ? list.params.length - 1 : list.params.length;
      if (!_writeParams(script.id, list, [...list.params]..insert(at, fresh))) return;
      unawaited(_editParam(script.id, block, slot, at, fresh: true));
      return;
    }
    unawaited(_editParam(script.id, block, slot, index));
  }

  Future<void> _editParam(String scriptId, BkBlock block, BkSlot slot, int index, {bool fresh = false}) async {
    final list = _paramsOf(scriptId, block, slot);
    final rect = _chipRect(scriptId, block, slot, index);
    if (list == null || rect == null || index >= list.params.length) return;
    final old = list.params[index];
    final anchor = Rect.fromPoints(globalOf(rect.topLeft), globalOf(rect.bottomRight));
    final choice = await showBlockParamCard(
      context,
      anchor: anchor,
      param: old,
      others: [
        for (final (i, p) in list.params.indexed)
          if (i != index) p.name,
      ],
      canDefault: list.canDefault,
      canRest: list.canRest && index == list.params.length - 1,
    );
    if (!mounted || choice == null) return;
    // 小卡开着的时候内容可能被换了（外面撤销）：照现在的再取一次。
    final now = _paramsOf(scriptId, block, slot);
    if (now == null || index >= now.params.length || now.params[index].name != old.name) return;
    final next = choice.param;
    if (next == null) {
      final uses = fresh ? 0 : now.uses(old.name);
      if (uses > 0) {
        final ok = await confirmDialog(context, title: '删掉参数“${old.name}”？', message: '有 $uses 处在用，槽里的东西会丢掉。', confirmLabel: '删除', danger: true);
        if (!ok || !mounted) return;
      }
      _writeParams(scriptId, now, [...now.params]..removeAt(index));
      return;
    }
    if (next.name == old.name && next.defaultValue == old.defaultValue && next.rest == old.rest) return;
    _writeParams(scriptId, now, [...now.params]..[index] = next, renamed: next.name == old.name ? null : (from: old.name, to: next.name));
  }

  @override
  bool liftParam(BkPlaced script, BkHit hit, Offset viewAt) {
    final slot = hit.slot;
    final list = slot == null ? null : _paramsOf(script.id, hit.block, slot);
    final index = slot?.param;
    if (slot == null || list == null || index == null || index >= list.params.length) return false;
    final expr = host.paramExpr(list.params[index].name);
    if (expr == null) return false;
    final piece = engine.layoutExpr(expr);
    final session = BkDragSession.fromPalette(host, engine, layout, BkPaletteSource(BkDragKind.expr, '', expr: expr, onlyScript: script.id), piece);
    // 手指按在小块的哪里，拿出来的那一块就从哪里被捏着。
    final grab = toCanvas(viewAt) - slot.rect.shift(script.origin).topLeft;
    dragStartWith(session, viewAt, Offset(grab.dx.clamp(4.0, piece.size.width - 4), grab.dy.clamp(4.0, piece.size.height - 4)));
    return drag != null;
  }

  @override
  bool onLiftRelease(BkPlaced script, BkHit hit) {
    final slot = hit.slot;
    if (slot != null && slot.look == BkSlotLook.param) {
      dragCancel();
      onParamTap(script, hit.block, slot);
      return true;
    }
    final custom = host.custom;
    if (custom == null || !custom.canWrap || hit.block.isHat || hit.expr != null) return false;
    dragCancel();
    unawaited(HapticFeedback.selectionClick());
    select(BlockSelection(script.id, hit.block.path));
    unawaited(_blockMenu(script.id, hit.block));
    return true;
  }

  // —— 语句积木的长按菜单 ——

  Future<void> _blockMenu(String scriptId, BkBlock block) async {
    final placed = layout.placed(scriptId);
    if (placed == null) return;
    final head = rectToView(block.head.shift(placed.origin));
    final at = Rect.fromPoints(globalOf(head.topLeft), globalOf(head.bottomRight));
    final what = await showBkMenu<String>(context, at: at, items: [const BkMenuEntry('wrap', Icons.widgets_outlined, '从这块往下包成积木', key: 'bk-block-menu-wrap')]);
    if (!mounted || what != 'wrap') return;
    await wrapFrom(scriptId, block.path);
  }

  /// “包成积木”：从这块往下相连的那一截 → 一个新定义 + 原处一次调用。
  Future<void> wrapFrom(String scriptId, LcBlockPath path) async {
    final custom = host.custom;
    final tree = host.script(scriptId);
    if (custom == null || tree == null || tree.blockAt(path) == null) return;
    final outer = custom.outerNames(tree, path);
    final rev = host.revision;
    final r = await showBlockLookPage(context, host: host, wrapParams: outer);
    if (!mounted || r == null) return;
    if (host.revision != rev) return toast('内容变了，没有包。再试一次');
    String? id;
    host.edit(() {
      final t = host.script(scriptId);
      if (t != null) id = custom.wrap(t, path, r.look, r.params);
    });
    final made = id;
    if (made == null) return toast('这一段包不了');
    unawaited(HapticFeedback.mediumImpact());
    toast('包成了“${r.look.name}”', actionLabel: '看定义', onAction: () => showDefinition(made));
  }

  // —— 我的积木 ——

  Future<void> customNew() async {
    final custom = host.custom;
    if (custom == null) return;
    commitEdit();
    final r = await showBlockLookPage(context, host: host);
    if (!mounted || r == null) return;
    String? id;
    host.edit(() => id = custom.create(r.look, r.params));
    final made = id;
    if (made == null) return toast('没建成');
    toast('“${r.look.name}”在积木盒里了', actionLabel: '看定义', onAction: () => showDefinition(made));
  }

  BlockCustom? _customOf(String id) => host.custom?.customs.where((c) => c.id == id).firstOrNull;

  Future<void> customEdit(String id) async {
    final custom = host.custom;
    final old = _customOf(id);
    if (custom == null || old == null) return;
    commitEdit();
    final rev = host.revision;
    final r = await showBlockLookPage(context, host: host, editing: old, uses: custom.usesOf(id));
    if (!mounted || r == null) return;
    if (host.revision != rev) return toast('内容变了，没有改。再试一次');
    var ok = false;
    // 各处调用的槽跟着增减：原来选中的那块可能已经不是原来的样子了，先放开。
    select(null);
    host.edit(() => ok = custom.update(id, r.look, r.params, r.origin));
    if (!ok) toast('没改成');
  }

  Future<void> customRemove(String id) async {
    final custom = host.custom;
    final old = _customOf(id);
    if (custom == null || old == null) return;
    final name = old.look.name;
    final uses = custom.usesOf(id);
    final ok = await confirmDialog(
      context,
      title: '删掉“$name”？',
      message: uses > 0 ? '有 $uses 处在用，删掉以后那些地方的这块积木也会一起拿掉。' : '没有地方在用它。它的定义那一串会一起删掉。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    var done = false;
    select(null);
    host.edit(() => done = custom.remove(id));
    if (done) toast('删掉了“$name”', actionLabel: '撤销', onAction: () => host.canUndo ? host.undo() : null);
  }

  /// “看它的定义”：画布滑到定义那一串并闪一下。
  void showDefinition(String id) {
    final at = host.custom?.definitionOf(id);
    if (at == null || layout.placed(at) == null) return toast('没找到它的定义');
    dockYield();
    jumpTo(at, const []);
  }
}

/// 一张参数表现在的样子，和怎么写回去。
class _ParamList {
  _ParamList({required this.params, this.canDefault = false, this.canRest = false, this.max = 12, this.uses = _noUses, required this.write});
  final List<BlockParam> params;
  final bool canDefault;
  final bool canRest;
  final int max;
  final int Function(String name) uses;
  final bool Function(List<BlockParam> next, ({String from, String to})? renamed) write;
  static int _noUses(String _) => 0;
}

/// 编辑器里贴着某样东西弹出来的菜单的一项。
class BkMenuEntry<T> {
  const BkMenuEntry(this.value, this.icon, this.text, {required this.key, this.danger = false});
  final T value;
  final IconData icon;
  final String text;
  final String key;
  final bool danger;
}

/// 贴着 `at`（屏幕坐标）下面弹一个菜单。
Future<T?> showBkMenu<T>(BuildContext context, {required Rect at, required List<BkMenuEntry<T>> items}) {
  final c = context.colors;
  final t = Theme.of(context).textTheme;
  final screen = MediaQuery.sizeOf(context);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(at.left, at.bottom + 4, screen.width - at.right, 0),
    constraints: const BoxConstraints(minWidth: 148, maxWidth: 280),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      for (final e in items)
        PopupMenuItem<T>(
          key: ValueKey(e.key),
          value: e.value,
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(e.icon, size: 18, color: e.danger ? c.danger : c.textMuted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(e.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: e.danger ? c.danger : null)),
              ),
            ],
          ),
        ),
    ],
  );
}
