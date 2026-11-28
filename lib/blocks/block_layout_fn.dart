part of 'block_layout.dart';

// 第 4 版·阶段 2 的排版：参数小块（定义帽子上的、匿名函数上的）和“带口的值”。
//
// - 参数小块：一个小胶囊，上面写参数名（有默认值写“名字＝值”，“剩下的全收”前面带“…”）；一排小块后面跟一个小“＋”。
// - 带口的值：上面一行是它那句话（字、槽、参数小块），下面是一个凹进去的口，口里的语句积木照常一块接一块。
//   口四周留一圈边（[_mouthPad]）；口至少 [_mouthMinW] 宽、放得下一块空积木那么高。
//   口里的积木先按“相对这个值左上角”的位置排好存着（值自己还要被外面一层层挪位置），
//   等外面那块语句积木的字和槽都摆到位了，再一次挪到位、接进整串的表里（[_flush]）。

/// 那句话里用来指“参数小块排在这”的写法，和排版时临时替它的记号。
const String _paramsMark = '{@params}';
const String _paramsHere = '\u0001';

/// 口四周留的边；口里的积木离口的边多远；口最窄多宽。
const double _mouthPad = 8;
const double _mouthInset = 6;
const double _mouthMinW = 132;

extension _FnLayout on BlockLayoutEngine {
  /// 一排参数小块 + 末尾的“＋”。`arg / path`：在帽子上是空的；在带参数表的值上指着那个值。
  List<BkSlot> _paramSlots(List<BlockParam> params, String arg, BkExprPath path, {required bool canAdd}) {
    final m = metrics;
    return [
      for (final (i, p) in params.indexed)
        BkSlot(
          arg: arg,
          exprPath: path,
          spec: null,
          look: BkSlotLook.param,
          rect: Rect.fromLTWH(0, 0, math.min(measure(p.chipText), m.fieldMaxTextW) + m.fieldPadH * 2 + 2, m.fieldH),
          text: p.chipText,
          param: i,
          colorKey: _paramColor(p.name),
        ),
      if (canAdd) BkSlot(arg: arg, exprPath: path, spec: null, look: BkSlotLook.add, rect: Rect.fromLTWH(0, 0, 24, m.fieldH), param: params.length),
    ];
  }

  /// 参数小块的颜色＝它拖出来变成的那个值的颜色。
  String _paramColor(String name) {
    final kind = exprKind(host.paramExpr(name));
    return kind == null ? BlockColorKey.variable : host.exprColorKey(kind);
  }

  List<BkSlot> _exprParamSlots(Map<String, dynamic> expr, LcExprSpec spec, String arg, BkExprPath path) {
    final names = bkExprParams(expr, spec);
    return _paramSlots(
      [
        for (final (i, n) in names.indexed)
          if (bkExprParamType(expr, i) case final t?) BlockParam(n, type: t, typeLabel: host.paramTypeLabel(t)) else BlockParam(n),
      ],
      arg,
      path,
      canAdd: _controls && names.length < kExprParamMax,
    );
  }

  /// 给一个已经排好头那一行的值加上口：口里的积木排在 [BkExpr.inner] 里（相对这个值的左上角）。
  void _exprMouth(BkExpr e, Map<String, dynamic> expr) {
    final m = metrics;
    final body = lcExprBody(expr);
    final owner = _curOwner, ownerPath = _curBlock, ownerDepth = _curDepth;
    // 这个口在所属积木里排第几个（模型按同一个顺序数，见 LcBlock.exprMouths）。没有所属积木（单独摆着的值）就顺着数。
    var k = _looseMouths++;
    if (owner != null && body != null) {
      final all = owner.exprMouths;
      for (var i = 0; i < all.length; i++) {
        if (identical(all[i], body)) k = i;
      }
    }
    final top = e.rect.bottom - 1;
    final x = _mouthPad + _mouthInset, y = top + _mouthInset;
    final blocks = <BkBlock>[];
    final snaps = <BkSnap>[];
    final bottom = _list(
      body ?? const [],
      ownerPath ?? const [],
      false,
      x,
      y,
      blocks,
      snaps,
      ownerDepth + 1,
      _mouthMinW - _mouthInset * 2,
      edgeSnaps: body != null && ownerPath != null,
      arm: lcExprMouthArm(k),
    );
    _curBlock = ownerPath;
    _curOwner = owner;
    _curDepth = ownerDepth;
    var right = x;
    for (final b in blocks) {
      right = math.max(right, b.rect.right);
    }
    final holeW = math.max(math.max(_mouthMinW, right - _mouthPad + _mouthInset), e.rect.width - _mouthPad * 2);
    final holeH = math.max(m.mouthMinH + _mouthInset * 2, bottom - top + m.notchD + m.edgeH + _mouthInset);
    e
      ..mouth = Rect.fromLTWH(_mouthPad, top, holeW, holeH)
      ..rect = Rect.fromLTWH(0, 0, holeW + _mouthPad * 2, top + holeH + _mouthPad)
      ..inner = blocks
      ..innerSnaps = snaps;
  }

  /// 把这些槽里（一层层往里）“带口的值”口里的积木挪到位，接进整串的表里。
  void _flush(List<BkSlot> slots, List<BkBlock> out, List<BkSnap> snaps) {
    for (final s in slots) {
      final e = s.expr;
      if (e != null) _flushExpr(e, out, snaps);
    }
  }

  void _flushExpr(BkExpr e, List<BkBlock> out, List<BkSnap> snaps) {
    if (e.inner.isNotEmpty || e.innerSnaps.isNotEmpty) {
      final d = e.rect.topLeft;
      for (final b in e.inner) {
        _shiftBlock(b, d);
        out.add(b);
      }
      for (final s in e.innerSnaps) {
        snaps.add(s.shifted(d));
      }
      e
        ..inner = []
        ..innerSnaps = [];
    }
    _flush(e.slots, out, snaps);
  }
}

/// 带参数表的值最多几个参数。
const int kExprParamMax = 6;

/// 整块积木挪一下（它上面的字、槽、槽里的值、口、小按钮都跟着）。口里别的积木是单独的 [BkBlock]，不在这里管。
void _shiftBlock(BkBlock b, Offset d) {
  if (d == Offset.zero) return;
  b
    ..rect = b.rect.shift(d)
    ..head = b.head.shift(d);
  for (final l in b.labels) {
    l.rect = l.rect.shift(d);
  }
  for (final s in b.slots) {
    _shiftSlot(s, d);
  }
  for (final mo in b.mouths) {
    mo
      ..rect = mo.rect.shift(d)
      ..bar = mo.bar?.shift(d);
    // 收尾口上的字不在 labels 里（段横栏上的在，上面已经挪过了）。
    final l = mo.label;
    if (l != null) l.rect = l.rect.shift(d);
  }
  for (final c in b.controls) {
    c.rect = c.rect.shift(d);
  }
}
