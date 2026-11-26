// 设计约束（多口积木上的“＋”“−”，390 宽，浅色 + 深色）— 2026-11-25
// - “如果 … 否则如果 … 否则”“分情况”这类积木，段数是在积木上直接增减的，不用进别的面板：
//   底条左边一个“＋”＝在最后加一段；每段横栏右边一个“−”＝删掉这一段；收尾口（“否则”）的横栏右边一个“−”＝把它收起来。
// - 小按钮画成压进去的深色小圆（和“一串值”末尾的小“＋”一个样子），不抢积木上字和槽的戏；点击范围不小于 40。
// - “＋”一次只做一件事：能加段、收尾口又被收起来了，才弹一个两项的小菜单（加一段 / 加上“否则”）；否则直接做。
// - 删的那一段里面还有积木：先问一句（说清楚会一起删掉几块、可以撤销）；空的直接删。
// - 段分先后的积木（宿主说了算；现在只有严格规矩里的“试着做”“看是哪种情况”）且不止一段：点“−”先出一个小菜单
//   （往上挪 / 往下挪 / 删掉这一段），别的积木点“−”还是直接删。
// - 每次增减＝一次改动（一条撤销记录）；积木变高了，把正下方别的脚本往下推（和拖进一块积木时同一条规矩）。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_edit_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

mixin BkEditorArms on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas, BkEditorEdit {
  @override
  void onControlTap(BkPlaced script, BkHit hit) {
    final control = hit.control;
    if (control == null || hit.block.isHat) return;
    select(BlockSelection(script.id, hit.block.path));
    final at = rectToView(control.rect.shift(script.origin));
    unawaited(_runControl(script.id, hit.block.path, control, at));
  }

  LcBlock? _armBlock(String scriptId, LcBlockPath path) => host.script(scriptId)?.blockAt(path);

  /// 改这块积木的段（一次改动）；`change` 返回有没有真的改。
  bool _editArms(String scriptId, LcBlockPath path, bool Function(LcBlock block) change) {
    final before = layout;
    var done = false;
    host.edit(() {
      final block = _armBlock(scriptId, path);
      if (block == null) return;
      done = change(block);
      if (done) bkPushDown(host, engine, before, scriptId);
    });
    if (done) unawaited(HapticFeedback.lightImpact());
    return done;
  }

  Future<void> _runControl(String scriptId, LcBlockPath path, BkControl control, Rect viewAt) async {
    final block = _armBlock(scriptId, path);
    final spec = block == null ? null : host.blockSpec(block.op);
    final arms = spec?.arms;
    if (block == null || spec == null || arms == null) return;
    switch (control.kind) {
      case BkControlKind.add:
        final canArm = bkCanAddArm(host, block), canTail = bkCanShowTail(host, block);
        var what = canArm ? 'arm' : (canTail ? 'tail' : null);
        if (canArm && canTail) what = await _askAdd(viewAt, arms.label, spec.elseLabel ?? '否则');
        if (!mounted || what == null) return;
        if (what == 'arm') {
          _editArms(scriptId, path, (b) => bkAddArm(host, b) >= 0);
        } else {
          _editArms(scriptId, path, (b) => bkSetTail(host, b, shown: true));
        }
      case BkControlKind.removeArm:
        final arm = control.arm;
        if (arm < 0 || arm >= block.arms.length) return;
        if (host.armsOrdered(block) && block.arms.length > 1) {
          final what = await _askMenu(viewAt, [
            if (arm > 0) ('up', Icons.arrow_upward_rounded, '往上挪'),
            if (arm < block.arms.length - 1) ('down', Icons.arrow_downward_rounded, '往下挪'),
            ('remove', Icons.remove_rounded, '删掉这一段'),
          ]);
          if (!mounted || what == null) return;
          if (what != 'remove') {
            final to = what == 'up' ? arm - 1 : arm + 1;
            _editArms(scriptId, path, (b) {
              if (arm >= b.arms.length || to < 0 || to >= b.arms.length) return false;
              b.arms.insert(to, b.arms.removeAt(arm));
              return true;
            });
            return;
          }
        }
        final inside = bkCountBlocks(block.arms[arm].body);
        if (inside > 0 && !await _confirmRemove('删掉这一段？', '“${arms.label}”这一段里面还有 $inside 块积木，会一起删掉。可以用撤销找回来。')) return;
        if (!mounted) return;
        if (!_editArms(scriptId, path, (b) => bkRemoveArm(host, b, arm))) toast('至少要留 ${arms.min} 段。');
      case BkControlKind.removeTail:
        final label = spec.elseLabel ?? '否则';
        final inside = bkCountBlocks(block.orElse);
        if (inside > 0 && !await _confirmRemove('去掉“$label”？', '“$label”里面还有 $inside 块积木，会一起删掉。可以用撤销找回来。')) return;
        if (!mounted) return;
        _editArms(scriptId, path, (b) => bkSetTail(host, b, shown: false));
    }
  }

  Future<bool> _confirmRemove(String title, String message) => confirmDialog(context, title: title, message: message, confirmLabel: '删除', danger: true);

  /// “＋”有两件事可做时的小菜单。返回 `arm` / `tail` / null（没选）。
  Future<String?> _askAdd(Rect viewAt, String armLabel, String tailLabel) => _askMenu(viewAt, [('arm', Icons.add_rounded, '加一段“$armLabel”'), ('tail', Icons.add_rounded, '加上“$tailLabel”')]);

  Future<String?> _askMenu(Rect viewAt, List<(String, IconData, String)> entries) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final at = Rect.fromPoints(globalOf(viewAt.topLeft), globalOf(viewAt.bottomRight));
    final screen = MediaQuery.sizeOf(context);
    PopupMenuItem<String> item(String value, IconData icon, String text) => PopupMenuItem(
      key: ValueKey('bk-arm-menu-$value'),
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          ),
        ],
      ),
    );
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.left, at.bottom + 4, screen.width - at.right, 0),
      constraints: const BoxConstraints(minWidth: 148, maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [for (final (value, icon, text) in entries) item(value, icon, text)],
    );
  }
}
