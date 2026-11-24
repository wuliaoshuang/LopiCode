/// 积木排版引擎：给一串积木（帽子 + 积木树 + 参数里的表达式树），算出每块的矩形、每个槽位的矩形、每个可拼接点。
///
/// 纯计算：不画东西，量字宽靠外面传进来的 [BkMeasure]（界面里用真字体量，单元测试里用假的），所以能直接单元测试。
/// 结果的形状见 block_geometry.dart。
///
/// 排法：
/// - 一块积木上的字和槽位从左到右排，超过 [BkMetrics.maxBlockWidth] 就在积木内部换行；每一行里的东西竖直居中。
/// - 表达式块自己也这样排（可以多行），整体当成上一层的一样东西；越套越窄，但不窄过 [BkMetrics.minExprWidth]。
/// - 语句积木上下紧贴（上一块的凸起正好落进下一块的凹口）。C 形块的口里的积木往右缩进一个“胳膊”的宽度。
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 量一段字有多宽（字号、字重由调用方定死：积木上的字都是同一种）。
typedef BkMeasure = double Function(String text);

/// 积木套积木最多排这么多层（模型自己最多 13 层；这里留余量，防自己套自己的坏数据把栈撑爆）。
const int kBkMaxBlockDepth = 40;

/// 就地输入时临时换掉某个输入框里的字（见 [BlockLayoutEngine.fieldOverride]）。帽子上的框给 `hatSlotId`，其余给积木路径 + 参数位置。
typedef BkFieldOverride = ({String scriptId, LcBlockPath path, String arg, BkExprPath exprPath, String? hatSlotId, String text, double minWidth});

/// 排版时流式摆放的一样东西：一段字或一个槽位。
class _Item {
  _Item.label(this.label) : slot = null;
  _Item.slot(this.slot) : label = null;
  final BkLabel? label;
  final BkSlot? slot;

  Rect get rect => label?.rect ?? slot!.rect;

  void moveTo(Offset topLeft) {
    final d = topLeft - rect.topLeft;
    if (label != null) {
      label!.rect = label!.rect.shift(d);
    } else {
      _shiftSlot(slot!, d);
    }
  }
}

void _shiftSlot(BkSlot s, Offset d) {
  s.rect = s.rect.shift(d);
  final e = s.expr;
  if (e != null) _shiftExpr(e, d);
}

void _shiftExpr(BkExpr e, Offset d) {
  e.rect = e.rect.shift(d);
  for (final l in e.labels) {
    l.rect = l.rect.shift(d);
  }
  for (final s in e.slots) {
    _shiftSlot(s, d);
  }
}

class BlockLayoutEngine {
  BlockLayoutEngine(this.host, this.measure, {this.metrics = const BkMetrics()});

  final BlockHost host;
  final BkMeasure measure;
  final BkMetrics metrics;

  /// 排过几次整串脚本（性能冒烟测试用：拖动时每帧不该重排）。
  int scriptLayouts = 0;

  /// 就地输入时：正在改的那个输入框按“框里现在的字”排（积木跟着字变宽，输入框正好盖住这个槽，不会压到旁边的槽）。
  BkFieldOverride? fieldOverride;
  String _curScript = '';
  LcBlockPath? _curBlock;

  bool _overridden(String arg, BkExprPath path, String? hatSlotId) {
    final o = fieldOverride;
    if (o == null || o.scriptId != _curScript) return false;
    if (hatSlotId != null || o.hatSlotId != null) return o.hatSlotId == hatSlotId && _curBlock == null;
    final at = _curBlock;
    return at != null && o.arg == arg && bkSameBlockPath(o.path, at) && bkSameExprPath(o.exprPath, path);
  }

  // —— 对外 ——

  /// 排一整串：帽子 + 下面所有积木。`body` 给了就用它代替 `tree.body`
  /// （拖动时预览“拿走一截 / 让出落点”以后的样子，不用真去改模型）。
  BkScriptLayout layoutScript(LcBlockTree tree, {List<LcBlock>? body}) {
    scriptLayouts++;
    final blocks = <BkBlock>[];
    final snaps = <BkSnap>[];
    _curScript = tree.id;
    _curBlock = null;
    final hat = _hat(host.hatOf(tree));
    blocks.add(hat);
    _list(body ?? tree.body, const [], false, 0, hat.rect.bottom, blocks, snaps, 0, hat.rect.width);
    _curScript = '';
    _curBlock = null;
    return _finish(tree.id, blocks, snaps);
  }

  /// 只排一个帽子（积木盒里的样品）。
  BkScriptLayout layoutHat(BlockHat hat) => _finish('', [_hat(hat)], []);

  /// 排一截没有帽子的积木（积木盒里的样品、拖在手上的那一截）。
  /// `parent / inElse / startIndex` 说明这一截原来在哪（路径照原样算）；样品不用给。
  BkScriptLayout layoutStack(List<LcBlock> list, {LcBlockPath parent = const [], bool inElse = false, int startIndex = 0}) {
    final blocks = <BkBlock>[];
    final snaps = <BkSnap>[];
    _list(list, parent, inElse, 0, 0, blocks, snaps, parent.length, metrics.minBlockWidth, startIndex: startIndex, edgeSnaps: false);
    return _finish('', blocks, snaps);
  }

  /// 排一个单独的表达式块（积木盒里的样品、拖在手上的表达式）。
  BkScriptLayout layoutExpr(Map<String, dynamic> expr) {
    final e = _expr(expr, '', const [], metrics.maxBlockWidth, 0);
    return BkScriptLayout(scriptId: '', blocks: [], snaps: [], size: Size(e.rect.width, e.rect.height + metrics.edgeH), loose: e);
  }

  BkScriptLayout _finish(String id, List<BkBlock> blocks, List<BkSnap> snaps) {
    var right = 0.0, bottom = 0.0;
    for (final b in blocks) {
      right = math.max(right, b.rect.right);
      bottom = math.max(bottom, b.rect.bottom);
    }
    return BkScriptLayout(scriptId: id, blocks: blocks, snaps: snaps, size: Size(right, bottom + metrics.notchD + metrics.edgeH));
  }

  // —— 流式摆放 ——

  /// 把一排东西从 (0,0) 开始摆：放不下就换行，每行竖直居中。返回占的大小。
  Size _flow(List<_Item> items, double maxW) {
    final m = metrics;
    var x = 0.0, y = 0.0, rowH = 0.0, width = 0.0;
    var rowStart = 0;
    void closeRow(int end) {
      for (var i = rowStart; i < end; i++) {
        final r = items[i].rect;
        items[i].moveTo(Offset(r.left, y + (rowH - r.height) / 2));
      }
      y += rowH + m.rowGap;
      rowStart = end;
      x = 0;
      rowH = 0;
    }

    for (var i = 0; i < items.length; i++) {
      final w = items[i].rect.width;
      if (x > 0 && x + w > maxW) closeRow(i);
      items[i].moveTo(Offset(x, 0));
      x += w + m.gap;
      width = math.max(width, x - m.gap);
      rowH = math.max(rowH, items[i].rect.height);
    }
    if (rowStart < items.length) closeRow(items.length);
    return Size(width, items.isEmpty ? 0 : y - m.rowGap);
  }

  BkLabel _label(String text, double maxW) => BkLabel(text, Rect.fromLTWH(0, 0, math.min(measure(text), maxW), metrics.textH));

  // —— 槽位 ——

  BkSlot _field(String arg, BkExprPath path, LcArgSpec? spec, String text, {String? hatSlotId, bool placeholder = false}) {
    final m = metrics;
    final live = _overridden(arg, path, hatSlotId);
    final shown = (live ? fieldOverride!.text : text).replaceAll(RegExp(r'[\r\n\t\u2028\u2029]+'), ' ');
    final w = math.max(live ? math.max(m.fieldMinW, fieldOverride!.minWidth) : m.fieldMinW, math.min(measure(shown), m.fieldMaxTextW) + m.fieldPadH * 2);
    return BkSlot(arg: arg, exprPath: path, spec: spec, look: BkSlotLook.field, rect: Rect.fromLTWH(0, 0, w, m.fieldH), text: shown, placeholder: placeholder, hatSlotId: hatSlotId);
  }

  BkSlot _dropdown(String arg, BkExprPath path, LcArgSpec? spec, String text, {bool placeholder = false, String? hatSlotId}) {
    final m = metrics;
    final w = math.min(measure(text), m.fieldMaxTextW) + m.fieldPadH * 2 + m.caretW;
    return BkSlot(arg: arg, exprPath: path, spec: spec, look: BkSlotLook.dropdown, rect: Rect.fromLTWH(0, 0, w, m.fieldH), text: text, placeholder: placeholder, hatSlotId: hatSlotId);
  }

  BkSlot _toggle(String arg, BkExprPath path, LcArgSpec? spec, Object? value) {
    final m = metrics;
    final text = value is bool ? (value ? '是' : '否') : '？';
    final w = measure(text) + (m.hexTip + 4) * 2;
    return BkSlot(arg: arg, exprPath: path, spec: spec, look: BkSlotLook.toggle, rect: Rect.fromLTWH(0, 0, w, m.fieldH), text: text, hex: true);
  }

  BkSlot _empty(String arg, BkExprPath path, LcArgSpec? spec) {
    final hex = spec?.valueType == LcType.boolean;
    return BkSlot(arg: arg, exprPath: path, spec: spec, look: BkSlotLook.empty, rect: Rect.fromLTWH(0, 0, hex ? 44 : 36, metrics.fieldH), hex: hex);
  }

  static String _number(num v) => v.isFinite && v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

  static String _placeholder(LcArgSpec a) {
    if (a.optional) return '不选';
    return switch (a.kind) {
      LcArgKind.variable => '选变量',
      LcArgKind.node => '选控件',
      LcArgKind.collection => '选集合',
      _ => a.label,
    };
  }

  /// 一个参数排成的槽位（`exprList` 可能是好几个）。`path` 是这个参数的值在积木参数 `arg` 里的位置。
  List<BkSlot> _argSlots(LcArgSpec a, Object? value, String arg, BkExprPath path, double maxW, int depth) {
    switch (a.kind) {
      case LcArgKind.expr:
        return [_exprSlot(a, value, arg, path, maxW, depth)];
      case LcArgKind.exprList:
        if (value is! List) return const [];
        return [
          for (var i = 0; i < value.length; i++) _exprSlot(a, value[i], arg, [...path, i], maxW, depth),
          // 末尾的小“＋”：点一下加一项。
          BkSlot(arg: arg, exprPath: [...path, value.length], spec: a, look: BkSlotLook.add, rect: Rect.fromLTWH(0, 0, 24, metrics.fieldH)),
        ];
      case LcArgKind.variable || LcArgKind.node || LcArgKind.collection || LcArgKind.choice:
        final has = value is String && value.isNotEmpty;
        return [_dropdown(arg, path, a, has ? host.optionLabel(a, value) : _placeholder(a), placeholder: !has)];
      case LcArgKind.literalText:
        return [_field(arg, path, a, value is String ? value : '')];
      case LcArgKind.literalNumber:
        return [_field(arg, path, a, value is num ? _number(value) : '')];
      case LcArgKind.literalBool:
        return [_toggle(arg, path, a, value)];
    }
  }

  BkSlot _exprSlot(LcArgSpec a, Object? value, String arg, BkExprPath path, double maxW, int depth) {
    final expr = asExpr(value);
    if (expr == null) return _empty(arg, path, a);
    final e = _expr(expr, arg, path, maxW, depth);
    return BkSlot(arg: arg, exprPath: path, spec: a, look: BkSlotLook.expr, rect: e.rect, hex: e.hex, expr: e);
  }

  // —— 表达式 ——

  /// 排一个表达式块，左上角在 (0,0)。`arg / path`＝它在积木参数里的位置；`maxW`＝最多能占多宽。
  BkExpr _expr(Map<String, dynamic> expr, String arg, BkExprPath path, double maxW, int depth) {
    final m = metrics;
    final kind = exprKind(expr) ?? '';
    final spec = host.exprSpec(kind);
    if (spec == null || depth > kMaxExprDepth) {
      final text = spec == null ? '不认识的值（${_clip(kind)}）' : '…';
      final e = BkExpr(expr: expr, kind: kind, colorKey: BlockColorKey.unknown, rect: Rect.zero, hex: false, bare: false, unknown: true);
      final label = _label(text, math.max(m.minExprWidth, maxW) - m.exprPadH * 2);
      label.rect = label.rect.shift(Offset(m.exprPadH, m.exprPadV));
      e.labels.add(label);
      e.rect = Rect.fromLTWH(0, 0, label.rect.width + m.exprPadH * 2, m.textH + m.exprPadV * 2);
      return e;
    }
    final parts = parseBlockSentence(host.exprSentence(kind) ?? defaultExprSentence(spec), spec.args);
    final onlyArg = spec.args.length == 1 && parts.length == 1 && parts.first.arg != null ? spec.args.first : null;
    final bare = onlyArg != null && (onlyArg.kind == LcArgKind.literalText || onlyArg.kind == LcArgKind.literalNumber || onlyArg.kind == LcArgKind.literalBool);
    final hex = !bare && host.isBooleanExpr(expr);
    final padX = bare ? 0.0 : (hex ? m.hexTip + 3 : m.exprPadH);
    final padY = bare ? 0.0 : m.exprPadV;
    final inner = math.max(m.minExprWidth, maxW) - padX * 2;

    final e = BkExpr(expr: expr, kind: kind, colorKey: host.exprColorKey(kind), rect: Rect.zero, hex: hex || (bare && onlyArg.kind == LcArgKind.literalBool), bare: bare);
    final items = <_Item>[];
    for (final p in parts) {
      final a = p.arg == null ? null : spec.arg(p.arg!);
      if (a == null) {
        final l = _label(p.text, inner);
        e.labels.add(l);
        items.add(_Item.label(l));
      } else {
        for (final s in _argSlots(a, expr[a.name], arg, [...path, a.name], inner, depth + 1)) {
          e.slots.add(s);
          items.add(_Item.slot(s));
        }
      }
    }
    final size = _flow(items, inner);
    final h = math.max(size.height, bare ? 0.0 : m.textH);
    for (final it in items) {
      it.moveTo(it.rect.topLeft + Offset(padX, padY + (h - size.height) / 2));
    }
    e.rect = Rect.fromLTWH(0, 0, math.max(size.width + padX * 2, bare ? 0.0 : m.fieldMinW), h + padY * 2);
    return e;
  }

  static String _clip(String s, [int limit = 12]) {
    final runes = s.runes.toList();
    return runes.length <= limit ? s : '${String.fromCharCodes(runes.take(limit))}…';
  }

  // —— 积木 ——

  BkBlock _hat(BlockHat hat) {
    final m = metrics;
    final b = BkBlock(path: const [], block: null, shape: BkShape.hat, colorKey: hat.colorKey, rect: Rect.zero, head: Rect.zero);
    final inner = m.maxBlockWidth - m.padH * 2;
    final items = <_Item>[];
    for (final p in hat.parts) {
      final id = p.slotId;
      if (id == null) {
        final l = _label(p.text, inner);
        b.labels.add(l);
        items.add(_Item.label(l));
      } else {
        final typed = p.kind == LcArgKind.literalText || p.kind == LcArgKind.literalNumber;
        final s = typed ? _field('', const [], null, p.text, hatSlotId: id, placeholder: p.empty) : _dropdown('', const [], null, p.text, placeholder: p.empty, hatSlotId: id);
        b.slots.add(s);
        items.add(_Item.slot(s));
      }
    }
    final size = _flow(items, inner);
    final headH = math.max(size.height + m.padV * 2, m.minBlockHeight);
    final w = math.max(size.width + m.padH * 2, math.max(m.minMouthBlockWidth, m.hatDomeW + 28));
    // 字放在圆顶下面那一截的正中，再往上提一点（圆顶在左上，视觉重心偏上）。
    final top = m.hatDome + (headH - size.height) / 2 - 1;
    for (final it in items) {
      it.moveTo(it.rect.topLeft + Offset(m.padH, top));
    }
    b.rect = Rect.fromLTWH(0, 0, w, m.hatDome + headH);
    b.head = b.rect;
    return b;
  }

  /// 排一列积木，从 (x, y) 往下。返回最下面的 y。`fallbackWidth`＝列表为空时落点阴影画多宽。
  double _list(
    List<LcBlock> list,
    LcBlockPath parent,
    bool inElse,
    double x,
    double y,
    List<BkBlock> out,
    List<BkSnap> snaps,
    int depth,
    double fallbackWidth, {
    int startIndex = 0,
    bool edgeSnaps = true,
  }) {
    if (depth > kBkMaxBlockDepth) return y;
    var width = fallbackWidth;
    for (var i = 0; i < list.length; i++) {
      final index = startIndex + i;
      final snapAt = snaps.length;
      final b = _block(list[i], [...parent, lcStep(index, inElse: inElse)], x, y, out, snaps, depth);
      width = b.head.width;
      // 这块上方的插入位（排在这块自己的那些拼接点前面）。
      if (edgeSnaps || i > 0) snaps.insert(snapAt, BkSnap.statement(parent: parent, inElse: inElse, index: index, anchor: Offset(x, y), width: width));
      y = b.rect.bottom;
    }
    if (edgeSnaps) snaps.add(BkSnap.statement(parent: parent, inElse: inElse, index: startIndex + list.length, anchor: Offset(x, y), width: width));
    return y;
  }

  BkBlock _block(LcBlock block, LcBlockPath path, double x, double y, List<BkBlock> out, List<BkSnap> snaps, int depth) {
    final m = metrics;
    final spec = host.blockSpec(block.op);
    final hasBody = spec?.hasBody == true || block.body.isNotEmpty;
    final hasElse = spec?.hasElse == true || block.orElse.isNotEmpty;
    final mouthed = hasBody || hasElse;
    final b = BkBlock(
      path: path,
      block: block,
      shape: mouthed ? BkShape.mouth : BkShape.stack,
      colorKey: spec == null ? BlockColorKey.unknown : host.blockColorKey(block.op),
      rect: Rect.zero,
      head: Rect.zero,
      unknown: spec == null,
    );
    out.add(b);

    final inner = m.maxBlockWidth - m.padH * 2;
    final items = <_Item>[];
    _curBlock = path;
    if (spec == null) {
      final l = _label('不认识的积木（${_clip(block.op)}）', inner);
      b.labels.add(l);
      items.add(_Item.label(l));
    } else {
      for (final p in parseBlockSentence(host.blockSentence(block.op) ?? defaultBlockSentence(spec), spec.args)) {
        final a = p.arg == null ? null : spec.arg(p.arg!);
        if (a == null) {
          final l = _label(p.text, inner);
          b.labels.add(l);
          items.add(_Item.label(l));
        } else {
          for (final s in _argSlots(a, block.args[a.name], a.name, const [], inner, 0)) {
            b.slots.add(s);
            items.add(_Item.slot(s));
          }
        }
      }
    }
    final size = _flow(items, inner);
    final headH = math.max(size.height + m.padV * 2, m.minBlockHeight);
    final w = math.max(size.width + m.padH * 2, mouthed ? m.minMouthBlockWidth : m.minBlockWidth);
    for (final it in items) {
      it.moveTo(it.rect.topLeft + Offset(x + m.padH, y + (headH - size.height) / 2));
    }
    b.head = Rect.fromLTWH(x, y, w, headH);
    _exprSnaps(b.slots, path, snaps);

    var cy = y + headH;
    void mouth(bool inElse, List<LcBlock> list, String? barLabel) {
      Rect? bar;
      BkLabel? label;
      if (barLabel != null) {
        bar = Rect.fromLTWH(x, cy, w, m.dividerH);
        final lw = math.min(measure(barLabel), w - m.padH * 2);
        label = BkLabel(barLabel, Rect.fromLTWH(x + m.padH, cy + (m.dividerH - m.textH) / 2, lw, m.textH));
        cy += m.dividerH;
      }
      final bottom = _list(list, path, inElse, x + m.armW, cy, out, snaps, depth + 1, w - m.armW);
      final h = math.max(m.mouthMinH, bottom - cy);
      b.mouths.add(BkMouth(inElse: inElse, rect: Rect.fromLTWH(x + m.armW, cy, w - m.armW, h), bar: bar, label: label));
      cy += h;
    }

    if (hasBody) mouth(false, block.body, null);
    // 只有“否则”没有 body 的（坏数据）也照样画出来，口上的标签照常写。
    if (hasElse) mouth(true, block.orElse, spec?.elseLabel ?? '否则');
    if (mouthed) cy += m.footerH;
    b.rect = Rect.fromLTWH(x, y, w, cy - y);
    return b;
  }

  void _exprSnaps(List<BkSlot> slots, LcBlockPath path, List<BkSnap> snaps) {
    for (final s in slots) {
      if (s.hatSlotId != null || !s.acceptsExpr) continue;
      snaps.add(BkSnap.expr(block: path, arg: s.arg, exprPath: s.exprPath, rect: s.rect, hex: s.hex));
      final e = s.expr;
      if (e != null && !e.bare) _exprSnaps(e.slots, path, snaps);
    }
  }
}
