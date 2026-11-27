/// 一份后端文档眼里的库积木（积木第 5 版·库 2）：它用上了哪些库、每块库积木在编辑器里长什么样（规格、句子、口、“放进变量”槽）。
/// 校验、编辑器宿主都问它。文档一改就重新建一张；任何输入都不抛异常。
library;

import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 库文档里才有的两块：“做口里的积木”“把 … 交给用的人选的变量”。
const String kBeLibDefCategory = '做库积木';

/// 一块库积木在编辑器里的样子。
class BeLibEntry {
  BeLibEntry(this.lib, this.block) : op = beLibOp(lib.id, block.id);

  final LibLibrary lib;
  final LibBlock block;
  final String op;

  late final List<String> _slots = [
    ...{
      for (final part in parseLookTemplate(block.look.template))
        if (part.isSlot) part.text,
    },
  ];

  /// 口的名字（最多两个：第一个是积木的开头口，第二个是收尾口）。
  late final List<String> mouths = [
    for (final s in _slots)
      if (block.kindOf(s) == LibSlotKind.mouth) s,
  ];

  /// 积木上的槽（不算口）。
  late final List<String> params = [
    for (final s in _slots)
      if (block.kindOf(s) != LibSlotKind.mouth) s,
  ];

  bool get isHat => block.shape == CustomBlockShape.hat;
  bool get isValue => block.isValue;

  /// 去掉口以后的那句话。
  late final String template = [
    for (final part in parseLookTemplate(block.look.template))
      if (!part.isSlot) part.text.replaceAll('{', '{{').replaceAll('}', '}}') else if (block.kindOf(part.text) != LibSlotKind.mouth) '{${part.text}}',
  ].join().trim();

  late final BlockCustom custom = BlockCustom(op, block.look.copyWith(template: template, shape: isHat ? CustomBlockShape.statement : block.shape), params);

  late final List<LcArgSpec> args = [
    for (final a in bkLookArgs(custom))
      switch (block.kindOf(a.name)) {
        LibSlotKind.assign => LcArgSpec(a.name, a.name, LcArgKind.variable, optional: true),
        _ => a,
      },
  ];

  late final LcBlockSpec blockSpec = LcBlockSpec(
    op,
    block.look.name,
    lib.name,
    args,
    bodyLabel: mouths.isEmpty ? null : mouths.first,
    elseLabel: mouths.length > 1 ? mouths[1] : null,
    hint: block.look.hint,
  );
  late final LcExprSpec exprSpec = LcExprSpec(op, block.look.name, lib.name, args, hint: block.look.hint);
  late final String sentence = bkLookSentence(custom.look, params);

  /// 新拿出来的一块，各槽先放什么。
  Map<String, dynamic> newArgs(Object? Function(CustomBlockSlot slot) slotValue) => {
    for (final p in params)
      p: switch (block.kindOf(p)) {
        LibSlotKind.assign => '',
        _ => slotValue(block.look.slotFor(p)),
      },
  };
}

class BeLibTable {
  BeLibTable(this.doc);
  final BeDocument doc;

  /// 用上了、项目里有、读得懂的库，按“用上”的先后。
  late final List<LibLibrary> libs = [
    for (final u in doc.uses)
      if (doc.lib(u.id) case final l? when l.ok) l,
  ];

  late final Map<String, BeLibEntry> _entries = {
    for (final l in libs)
      for (final b in l.blocks) beLibOp(l.id, b.id): BeLibEntry(l, b),
  };

  bool get isEmpty => _entries.isEmpty;
  Iterable<BeLibEntry> get entries => _entries.values;
  BeLibEntry? of(Object? op) => op is String ? _entries[op] : null;
  List<BeLibEntry> ofLib(String id) => [
    for (final e in _entries.values)
      if (e.lib.id == id) e,
  ];

  /// 这个 op 是不是“库积木”的写法（不管库还在不在）。
  static bool isLibOp(Object? op) => beLibOpOf(op) != null;

  LcBlockSpec? blockSpec(String op) {
    final e = _entries[op];
    if (e != null) return e.isHat ? null : e.blockSpec;
    if (doc.library == null) return null;
    return switch (op) {
      kBeLibMouthOp => const LcBlockSpec(kBeLibMouthOp, '做口里的积木', kBeLibDefCategory, [LcArgSpec('name', '口', LcArgKind.choice)], hint: '用的人放进这个口里的积木，在这里做'),
      kBeLibPutOp => const LcBlockSpec(kBeLibPutOp, '交给用的人选的变量', kBeLibDefCategory, [LcArgSpec('value', '值', LcArgKind.expr)], hint: '用的人在“放进变量”那一格选了哪个变量，就写进哪个'),
      _ => null,
    };
  }

  LcExprSpec? exprSpec(String? kind) {
    final e = _entries[kind];
    return e != null && !e.isHat ? e.exprSpec : null;
  }

  String? sentenceOf(String op) =>
      _entries[op]?.sentence ??
      (doc.library == null
          ? null
          : switch (op) {
              kBeLibMouthOp => '做 {name} 里的积木',
              kBeLibPutOp => '把 {value} 交给用的人选的变量',
              _ => null,
            });

  bool isBool(Object? expr) => _entries[exprKind(expr)]?.block.shape == CustomBlockShape.boolean;

  /// 库文档里：这个函数公开成的积木有哪些口（“做口里的积木”的下拉用）。
  List<String> mouthsOfFunction(String fnId) => [
    for (final d in doc.library?.blocks ?? const <BeLibDef>[])
      if (d.fn == fnId) ...d.mouths,
  ];

  /// 库积木在这份文档里用了几处（帽子串也算）。
  int usesOfLib(String libId) {
    var n = 0;
    bool mine(Object? op) => beLibOpOf(op)?.lib == libId;
    void walk(List<LcBlock> list, int depth) {
      if (depth > LcBlock.maxDepth + 2) return;
      for (final b in list) {
        if (mine(b.op)) n++;
        _exprs(b.args, (e) => n += mine(e['e']) ? 1 : 0);
        for (final a in b.arms) {
          _exprs(a.args, (e) => n += mine(e['e']) ? 1 : 0);
          walk(a.body, depth + 1);
        }
        walk(b.body, depth + 1);
        walk(b.orElse, depth + 1);
      }
    }

    for (final r in doc.routes) {
      walk(r.body, 0);
    }
    for (final f in doc.functions) {
      walk(f.body, 0);
    }
    for (final t in doc.core.trees) {
      walk(t.body, 0);
    }
    for (final h in doc.hats) {
      if (mine(h.op)) n++;
      walk(h.body, 0);
    }
    return n;
  }
}

void _exprs(Object? v, void Function(Map<String, dynamic> e) f, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2 + 4) return;
  if (v is List<LcBlock>) return;
  if (v is List) {
    for (final x in v) {
      _exprs(x, f, depth + 1);
    }
  } else if (v is Map) {
    final e = asExpr(v);
    if (e != null && e['e'] is String) f(e);
    for (final x in v.values) {
      _exprs(x, f, depth + 1);
    }
  }
}
