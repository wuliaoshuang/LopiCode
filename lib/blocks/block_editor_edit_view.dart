// 设计约束（就地改参数这一层，390 宽，浅色 + 深色）— 2026-11-24
// - 改参数不离开画布：点哪个槽，东西就出现在哪个槽旁边。没有整页面板、没有一层层往里进。
// - 数字 / 文字槽：那个槽自己变成输入框（数字用数字键盘），正好盖在槽上、不压旁边的槽；边打字积木边跟着变宽，右边的东西被推开而不是被盖住。
//   回车或点别处就算填好；键盘弹出时画布自动把这个槽挪到看得见的地方。
// - 下拉类的槽（变量、控件、固定选项…）：贴着槽弹出小菜单，点一项就选好。
// - 空的值槽、长按一个直接填的槽、或长按拿起一个值积木后没挪就松手：弹出紧凑的“换成…”小卡片（见 block_replace_view.dart）。
// - “是 / 否”点一下就翻；一串值末尾的小“＋”点一下加一项。
// - 选中一块积木后，画布上方出现一条小工具条：这块的问题（如果有）＋ 复制 ＋ 删除。主操作是长按拿起来拖，这条只是备用。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_fx_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_replace_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 正在改的那个槽：哪一串、哪块积木（帽子为空路径）、哪个参数的哪个位置；帽子上的槽用 `hatSlotId`。
typedef BkSlotRef = ({String scriptId, LcBlockPath path, String arg, BkExprPath exprPath, String? hatSlotId});

mixin BkEditorEdit on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas {
  BkSlotRef? editing;
  bool _editNumber = false;
  bool editInvalid = false;
  final TextEditingController editText = TextEditingController();
  final FocusNode editFocus = FocusNode(debugLabel: 'bk-inline-edit');

  void toast(String text, {String? actionLabel, VoidCallback? onAction});

  /// 点到了多口积木上的小按钮（加一段 / 删一段 / 收起收尾口）。实现在 block_editor_arms_view.dart。
  void onControlTap(BkPlaced script, BkHit hit);

  /// 输入框最窄多宽（画布尺寸）：空着的时候也点得中、看得见光标。
  static const double editMinWidth = 44;

  BkCanvasLayout? _preview;
  String? _previewText;
  int _previewRev = -1;

  /// 正在输入时画布照这个排：那个输入框按现在打的字算宽度，所在积木跟着变宽；别的串原样不动。
  @override
  BkCanvasLayout? get previewLayout {
    final ref = editing;
    if (ref == null) return null;
    final text = editText.text;
    if (_preview != null && _previewText == text && _previewRev == host.revision) return _preview;
    final base = layout;
    final live = kit.engine(host)..fieldOverride = (scriptId: ref.scriptId, path: ref.path, arg: ref.arg, exprPath: ref.exprPath, hatSlotId: ref.hatSlotId, text: text, minWidth: editMinWidth);
    _previewText = text;
    _previewRev = host.revision;
    return _preview = layoutBlockCanvas(
      host,
      live,
      origins: {for (final p in base.scripts) p.id: p.origin},
      layouts: {
        for (final p in base.scripts)
          if (p.id != ref.scriptId) p.id: p.layout,
      },
    );
  }

  void disposeEdit() {
    editText.dispose();
    editFocus.dispose();
  }

  /// 点了参数小块 / 它后面的“＋”（见 block_editor_fn_view.dart）。
  void onParamTap(BkPlaced script, BkBlock block, BkSlot slot) {}

  // —— 找槽 ——

  BkSlotRef _ref(BkPlaced script, BkBlock block, BkSlot slot) => (scriptId: script.id, path: block.isHat ? const [] : block.path, arg: slot.arg, exprPath: slot.exprPath, hatSlotId: slot.hatSlotId);

  /// 按引用在现在的排布里把槽找回来（连同它在编辑区里的位置）。
  ({BkPlaced script, BkBlock block, BkSlot slot, Rect view})? findSlot(BkSlotRef ref) {
    final placed = (editing == null ? layout : previewLayout ?? layout).placed(ref.scriptId);
    if (placed == null) return null;
    for (final (b, s) in placed.layout.allSlots) {
      final samePlace = ref.hatSlotId != null
          ? (b.isHat && s.hatSlotId == ref.hatSlotId)
          : (!b.isHat && s.hatSlotId == null && bkSameBlockPath(b.path, ref.path) && s.arg == ref.arg && bkSameExprPath(s.exprPath, ref.exprPath));
      if (samePlace && s.look != BkSlotLook.add && s.param == null) return (script: placed, block: b, slot: s, view: rectToView(s.rect.shift(placed.origin)));
    }
    return null;
  }

  LcBlock? _blockOf(BkSlotRef ref) => host.script(ref.scriptId)?.blockAt(ref.path);

  /// 改一个槽的值（一次改动）。
  void _write(BkSlotRef ref, Object? value, {void Function()? before}) {
    host.edit(() {
      before?.call();
      final tree = host.script(ref.scriptId);
      if (tree == null) return;
      final hat = ref.hatSlotId;
      if (hat != null) {
        host.setHatSlot(tree, hat, '$value');
        return;
      }
      final block = tree.blockAt(ref.path);
      if (block == null) return;
      if (bkSetExprAt(block, ref.arg, ref.exprPath, value)) host.argChanged(tree, block, ref.arg, ref.exprPath);
    });
  }

  // —— 点 / 长按 ——

  @override
  void onTapHit(BkPlaced script, BkHit hit) {
    commitEdit();
    if (hit.control != null) return onControlTap(script, hit);
    final slot = hit.slot;
    final sel = BlockSelection(script.id, hit.block.isHat ? const [] : hit.block.path);
    if (slot == null) {
      select(sel.same(selection) ? null : sel);
      return;
    }
    // 参数小块、它后面的“＋”：不选中所在的积木（选中会弹出删除条，挡着小块）。
    if (slot.param != null) return onParamTap(script, hit.block, slot);
    select(sel);
    final ref = _ref(script, hit.block, slot);
    switch (slot.look) {
      case BkSlotLook.field:
        _openInput(ref, slot);
      case BkSlotLook.dropdown:
        unawaited(_openMenu(ref, slot));
      case BkSlotLook.toggle:
        unawaited(HapticFeedback.selectionClick());
        _write(ref, slot.text != '是');
      case BkSlotLook.param:
        break;
      case BkSlotLook.add:
        final list = slot.exprPath.sublist(0, slot.exprPath.length - 1);
        host.edit(() {
          final tree = host.script(script.id);
          final block = tree?.blockAt(ref.path);
          if (tree != null && block != null && bkAddListItem(host, block, slot.arg, list)) host.argChanged(tree, block, slot.arg, list);
        });
      case BkSlotLook.empty:
        unawaited(openReplace(ref));
      case BkSlotLook.expr:
        break;
    }
  }

  @override
  bool onLongPressHit(BkPlaced script, BkHit hit, {bool open = true}) {
    final block = hit.block;
    if (block.isHat) return false;
    // 最里面那个“能放值”的槽：点在表达式上＝它所在的槽；点在直接填的框上＝装着这个框的槽。
    BkSlot? target;
    for (final (b, s) in script.layout.allSlots) {
      if (identical(b, block) && s.acceptsExpr && s.rect.contains(downCanvas - script.origin)) target = s;
    }
    if (target == null) return false;
    if (!open) return true;
    unawaited(HapticFeedback.selectionClick());
    select(BlockSelection(script.id, block.path));
    unawaited(openReplace(_ref(script, block, target)));
    return true;
  }

  // —— 输入框 ——

  void _openInput(BkSlotRef ref, BkSlot slot) {
    final hatKind = slot.hatSlotId == null ? null : _hatPartKind(ref);
    setState(() {
      editing = ref;
      _editNumber = (slot.spec?.kind ?? hatKind) == LcArgKind.literalNumber;
      editInvalid = false;
      editText.text = slot.placeholder ? '' : _rawText(ref, slot);
      editText.selection = TextSelection(baseOffset: 0, extentOffset: editText.text.length);
    });
    editFocus.requestFocus();
  }

  LcArgKind? _hatPartKind(BkSlotRef ref) {
    final tree = host.script(ref.scriptId);
    if (tree == null) return null;
    for (final p in host.hatOf(tree).parts) {
      if (p.slotId == ref.hatSlotId) return p.kind;
    }
    return null;
  }

  /// 输入框里放模型里的原值（槽上画的可能是截短、去掉换行的）。
  String _rawText(BkSlotRef ref, BkSlot slot) {
    final tree = host.script(ref.scriptId);
    if (tree == null) return slot.text;
    if (ref.hatSlotId != null) return host.hatSlotValue(tree, ref.hatSlotId!);
    final block = tree.blockAt(ref.path);
    final v = block == null ? null : bkExprAt(block, ref.arg, ref.exprPath);
    return v is String ? v : slot.text;
  }

  /// 把输入框里的字填回去。`strict`＝回车（填错了就留着不关）；否则是点了别处（填错了就不改、关掉）。返回关没关。
  bool commitEdit({bool strict = false}) {
    final ref = editing;
    if (ref == null) return true;
    final text = editText.text;
    Object? value = text;
    if (_editNumber) {
      final n = num.tryParse(text.trim());
      if (n == null || !n.isFinite) {
        if (strict) {
          setState(() => editInvalid = true);
          return false;
        }
        _closeEdit();
        toast('“$text”不是数字，没有改。');
        return true;
      }
      value = n;
    }
    _closeEdit();
    final tree = host.script(ref.scriptId);
    if (tree == null) return true;
    final hat = ref.hatSlotId;
    final block = tree.blockAt(ref.path);
    if (hat == null && block == null) return true;
    final old = hat != null ? host.hatSlotValue(tree, hat) : bkExprAt(block!, ref.arg, ref.exprPath);
    if (old == value || (hat != null && old == '$value')) return true;
    _write(ref, value);
    return true;
  }

  void _closeEdit() {
    if (editing == null) return;
    editFocus.unfocus();
    setState(() {
      editing = null;
      editInvalid = false;
      _preview = null;
    });
  }

  /// 输入框浮层（贴在槽的位置上）。没在改就什么都没有。
  List<Widget> buildInlineEdit(BuildContext context) {
    final ref = editing;
    final found = ref == null ? null : findSlot(ref);
    if (ref == null || found == null) return const [];
    final c = context.colors;
    final r = found.view;
    // 输入框正好盖住这个槽（槽在预览排布里已经按现在的字变宽了），不伸到旁边的槽上；缩得很小时也保证点得中。
    final width = r.width.clamp(40.0, viewSize.width - 16);
    final height = r.height.clamp(30.0, 56.0);
    final left = (r.center.dx - width / 2).clamp(8.0, (viewSize.width - width - 8).clamp(8.0, double.infinity));
    // 不放到悬浮顶栏后面去。
    final top = (r.center.dy - height / 2).clamp(coveredTop + 4.0, (viewSize.height - height - 4).clamp(coveredTop + 4.0, double.infinity));
    // 键盘弹出后槽被挡住了：把画布往上挪。
    final limit = viewSize.height - 52;
    if (r.bottom > limit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && editing != null) setState(() => setPan(pan - Offset(0, r.bottom - limit + 12)));
      });
    }
    return [
      Positioned.fill(
        child: GestureDetector(key: const ValueKey('bk-inline-barrier'), behavior: HitTestBehavior.opaque, onTap: commitEdit),
      ),
      Positioned(
        key: const ValueKey('bk-inline-box'),
        left: left.toDouble(),
        top: top.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        child: BkInlineField(
          kit: kit,
          tone: kit.palette.tone(found.block.colorKey),
          controller: editText,
          focusNode: editFocus,
          number: _editNumber,
          invalid: editInvalid,
          zoom: zoom,
          // 每打一个字都重排一下这一串：框跟着字变宽。
          onChanged: (_) => setState(() => editInvalid = false),
          onSubmitted: (_) {
            if (!commitEdit(strict: true)) editFocus.requestFocus();
          },
        ),
      ),
      if (editInvalid)
        Positioned(
          left: left.toDouble(),
          top: top.toDouble() + height + 6,
          child: Material(
            color: c.danger,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '要填数字',
                key: const ValueKey('bk-inline-error'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onAccent),
              ),
            ),
          ),
        ),
    ];
  }

  // —— 下拉小菜单 ——

  Future<void> _openMenu(BkSlotRef ref, BkSlot slot) async {
    final tree = host.script(ref.scriptId);
    final found = findSlot(ref);
    if (tree == null || found == null) return;
    final hat = ref.hatSlotId;
    final block = hat == null ? tree.blockAt(ref.path) : null;
    final spec = slot.spec;
    final List<BlockOption> options;
    String current;
    if (hat != null) {
      options = host.hatSlotOptions(tree, hat);
      current = host.hatSlotValue(tree, hat);
    } else {
      if (block == null || spec == null) return;
      options = host.options(spec, tree: tree, block: block, expr: bkOwnerExpr(block, ref.arg, ref.exprPath));
      final v = bkExprAt(block, ref.arg, ref.exprPath);
      current = v is String ? v : '';
    }
    final extra = spec == null ? null : widget.menuExtra?.call(spec);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final at = Rect.fromPoints(globalOf(found.view.topLeft), globalOf(found.view.bottomRight));
    final screen = MediaQuery.sizeOf(context);
    final picked = await showMenu<String>(
      context: context,
      // 打开时就能看见现在选的是哪个（选项多的时候不用自己找）。
      initialValue: current.isEmpty ? null : current,
      position: RelativeRect.fromLTRB(at.left, at.bottom + 4, screen.width - at.right, 0),
      constraints: const BoxConstraints(minWidth: 148, maxWidth: 280, maxHeight: 360),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        if (spec != null && spec.optional && !options.any((o) => o.value.isEmpty))
          PopupMenuItem(
            key: const ValueKey('bk-menu-none'),
            value: '',
            height: 44,
            child: Text('不选', style: t.bodyMedium?.copyWith(color: c.textMuted)),
          ),
        for (final o in options)
          PopupMenuItem(
            key: ValueKey(o.value.isEmpty ? 'bk-menu-none' : 'bk-menu-${o.value}'),
            value: o.value,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium?.copyWith(fontWeight: o.value == current ? FontWeight.w700 : FontWeight.w400),
                      ),
                      if (o.hint.isNotEmpty)
                        Text(
                          o.hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                ),
                if (o.value == current) Icon(Icons.check_rounded, size: 18, color: c.accent),
              ],
            ),
          ),
        if (options.isEmpty && extra == null)
          PopupMenuItem(
            enabled: false,
            height: 44,
            child: Text('没有可选的', style: t.bodyMedium?.copyWith(color: c.textMuted)),
          ),
        if (extra != null)
          PopupMenuItem(
            key: const ValueKey('bk-menu-extra'),
            value: '\u0000extra',
            height: 44,
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: c.accent),
                const SizedBox(width: 6),
                Text(extra.label, style: t.bodyMedium?.copyWith(color: c.accent)),
              ],
            ),
          ),
      ],
    );
    if (!mounted || picked == null) return;
    if (picked == '\u0000extra') {
      final made = await extra!.run(context);
      if (!mounted || made == null) return;
      _write(ref, made.value, before: made.apply);
      return;
    }
    if (picked == current) return;
    _write(ref, picked);
  }

  // —— 换成… ——

  Future<void> openReplace(BkSlotRef ref) async {
    final found = findSlot(ref);
    final block = _blockOf(ref);
    if (found == null || block == null) return;
    final current = asExpr(bkExprAt(block, ref.arg, ref.exprPath));
    final inList = ref.exprPath.isNotEmpty && ref.exprPath.last is int;
    final listLen = inList ? (bkExprAt(block, ref.arg, ref.exprPath.sublist(0, ref.exprPath.length - 1)) as List?)?.length ?? 0 : 0;
    final at = Rect.fromPoints(globalOf(found.view.topLeft), globalOf(found.view.bottomRight));
    final choice = await showBlockReplace(
      context,
      host: host,
      kit: kit,
      anchor: at,
      wantBoolean: found.slot.hex || found.slot.spec?.valueType == LcType.boolean,
      canRemove: inList && listLen > 1,
      canReset: current != null && !inList,
    );
    if (!mounted || choice == null) return;
    host.edit(() {
      final tree = host.script(ref.scriptId);
      final b = tree?.blockAt(ref.path);
      if (tree == null || b == null) return;
      switch (choice.action) {
        case BkReplaceAction.remove || BkReplaceAction.reset:
          bkTakeExpr(host, b, ref.arg, ref.exprPath);
        case BkReplaceAction.pick:
          final next = host.newExpr(choice.kind!);
          // 原来是拼好的一块（不是直接填的值）：包进新的一块里的第一个值槽，不白白丢掉。
          final old = asExpr(bkExprAt(b, ref.arg, ref.exprPath));
          final oldSpec = old == null ? null : host.exprSpec(exprKind(old) ?? '');
          final keep = old != null && oldSpec != null && !oldSpec.args.any((a) => a.kind == LcArgKind.literalText || a.kind == LcArgKind.literalNumber || a.kind == LcArgKind.literalBool);
          if (keep) {
            for (final a in host.exprSpec(choice.kind!)?.args ?? const <LcArgSpec>[]) {
              if (a.kind == LcArgKind.expr) {
                next[a.name] = old;
                break;
              }
              if (a.kind == LcArgKind.exprList && next[a.name] is List) {
                (next[a.name] as List)[0] = old;
                break;
              }
            }
          }
          if (!bkSetExprAt(b, ref.arg, ref.exprPath, next)) return;
      }
      host.argChanged(tree, b, ref.arg, ref.exprPath);
    });
  }

  // —— 选中以后：复制 / 删除 ——

  Future<void> deleteSelection() async {
    final sel = selection;
    final tree = sel == null ? null : host.script(sel.scriptId);
    if (sel == null || tree == null) return;
    if (sel.path.isEmpty) {
      final n = bkCountBlocks(tree.body);
      if (n > 0 && !await confirmDialog(context, title: '删掉这一整串？', message: '这个事件下面还有 $n 块积木，会一起删掉。可以用撤销找回来。', confirmLabel: '删除', danger: true)) return;
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      host.edit(() => host.removeScript(sel.scriptId));
      select(null);
      return;
    }
    final block = tree.blockAt(sel.path);
    if (block == null) return;
    final inside = bkCountBlocks([block]) - 1;
    if (inside > 0 && !await confirmDialog(context, title: '连里面的一起删？', message: '这块积木里面还有 $inside 块积木，会一起删掉。可以用撤销找回来。', confirmLabel: '删除', danger: true)) return;
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    host.edit(() => host.script(sel.scriptId)?.removeBlock(sel.path));
    // 删掉以后同一个位置上是别的积木了：不能让选中框悄悄落到它头上。
    select(null);
  }

  void duplicateSelection() {
    final sel = selection;
    if (sel == null || sel.path.isEmpty) return;
    var ok = false;
    final parent = sel.path.sublist(0, sel.path.length - 1);
    final step = sel.path.last;
    final before = layout;
    host.edit(() {
      final tree = host.script(sel.scriptId);
      final block = tree?.blockAt(sel.path);
      if (tree == null || block == null) return;
      ok = tree.insertBlock(parent, block.clone(), inElse: step.inElse, arm: step.arm, index: step.index + 1);
      if (ok) bkPushDown(host, engine, before, sel.scriptId);
    });
    if (!ok) return toast('积木套得太深了，复制不了。');
    setState(() => selection = BlockSelection(sel.scriptId, [...parent, lcStep(step.index + 1, inElse: step.inElse, arm: step.arm)]));
    pulseBlocks(sel.scriptId, range: (scriptId: sel.scriptId, parent: parent, inElse: step.inElse, arm: step.arm, start: step.index + 1, count: 1));
  }

  // —— 点一下积木盒里的积木：快捷添加 ——

  void quickAdd(BlockPaletteItem item) {
    commitEdit();
    switch (item.kind) {
      case BlockPaletteKind.expr:
        toast('按住它，拖到积木上的槽里。');
      case BlockPaletteKind.hat:
        String? id;
        host.edit(() => id = host.addScript(item.id)?.id);
        final made = id;
        if (made == null) return;
        unawaited(HapticFeedback.lightImpact());
        jumpTo(made, const []);
        // 新的一串落在画布上：轻弹一下。
        pulseBlocks(made);
      case BlockPaletteKind.block:
        final sel = selection;
        final scriptId = sel?.scriptId ?? (host.scripts.isEmpty ? null : host.scripts.last.id);
        if (scriptId == null) return toast('先从“事件”里拿一块出来，积木要接在它下面。');
        final before = layout;
        LcBlockPath? at;
        host.edit(() {
          final tree = host.script(scriptId);
          if (tree == null) return;
          final block = host.newBlock(item.id)..args.addAll(item.preset);
          if (sel != null && sel.path.isNotEmpty) {
            final parent = sel.path.sublist(0, sel.path.length - 1);
            final step = sel.path.last;
            if (tree.insertBlock(parent, block, inElse: step.inElse, arm: step.arm, index: step.index + 1)) at = [...parent, lcStep(step.index + 1, inElse: step.inElse, arm: step.arm)];
          } else if (tree.insertBlock(const [], block)) {
            at = [lcStep(tree.body.length - 1)];
          }
          if (at != null) bkPushDown(host, engine, before, scriptId);
        });
        final path = at;
        if (path == null) return toast('积木套得太深了，放不进去。');
        unawaited(HapticFeedback.lightImpact());
        jumpTo(scriptId, path);
        final last = path.last;
        pulseBlocks(scriptId, range: (scriptId: scriptId, parent: path.sublist(0, path.length - 1), inElse: last.inElse, arm: last.arm, start: last.index, count: 1));
    }
  }
}
