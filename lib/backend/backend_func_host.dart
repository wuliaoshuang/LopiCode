/// 后端积木宿主里“函数 / 我的积木”的那一半（积木第 4 版·第 2 阶段的“接线”）：
/// 定义帽子（名字、参数小块）、匿名函数的参数、调用积木的规格与样子、“我的积木”的全部回调（新建 / 编辑 / 删除 / 看定义 / 包成积木）。
///
/// 做成 mixin 混进 `BeBlockHost`（backend_block_host.dart），真正改文档的逻辑在 backend_func_edit.dart。
/// 写模型的回调都已经被编辑器包在一次 `edit` 里，这里不再开 `edit`。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 积木盒“函数”页里那个帽子模板的名字（交给 `addScript`）。
const String kBeDefineTemplate = 'define';

/// “参数”“这块积木本身”在编辑器里是下拉（从看得见的参数 / 文档里的函数里挑），所以给编辑器的说明和目录里的不一样（目录里是直接填的文字）。
const LcExprSpec _paramSpec = LcExprSpec('param', '参数', '函数', [LcArgSpec('name', '参数', LcArgKind.choice)], hint: '读一个参数的值；从帽子 / 匿名函数上把参数小块拖出来就是它');
const LcExprSpec _funcRefSpec = LcExprSpec('funcRef', '函数本身', '函数', [LcArgSpec('fn', '哪个', LcArgKind.choice)], hint: '把“我的积木”当成一个值交出去（不调用它）');

BlockHat beDefineHat(String name) =>
    BlockHat([const BlockHatPart.text('定义'), BlockHatPart.slot('name', name.isEmpty ? '名字' : name, empty: name.isEmpty, kind: LcArgKind.literalText)], colorKey: BlockColorKey.function);

List<BlockParam> _blockParams(BeFunction f) => [for (final p in f.params) BlockParam(p.name, defaultValue: p.defaultValue, rest: p.rest)];

mixin BeFuncHost on BlockHost {
  BeDocument get doc;
  void Function(String message)? get onNotice;

  BeFuncTable? _table;

  /// 这一刻文档里的“我的积木”一览；文档一变就丢掉重算（宿主的 `_bump` 调 [dropFuncTable]）。
  BeFuncTable get funcTable {
    final t = _table;
    return t != null && identical(t.doc, doc) ? t : _table = BeFuncTable(doc);
  }

  void dropFuncTable() => _table = null;

  late final BlockCustomHost _custom = _BeCustomHost(this);

  @override
  BlockCustomHost? get custom => _custom;

  // —— 规格 ——

  LcBlockSpec? funcBlockSpec(String op) => funcTable.blockSpec(op);

  LcExprSpec? funcExprSpec(String kind) => switch (kind) {
    'param' => _paramSpec,
    'funcRef' => _funcRefSpec,
    _ => funcTable.exprSpec(kind),
  };

  /// 调用积木的颜色跟着它的外观；不是调用返回 null。
  String? funcColorKey(String op) => funcTable.callOf(op)?.look.colorKey;

  /// “参数”“这块积木本身”的下拉里有什么；不归这边管返回 null。
  List<BlockOption>? funcOptions(LcArgSpec arg, {LcBlockTree? tree, Map<String, dynamic>? expr}) {
    if (expr == null || arg.kind != LcArgKind.choice) return null;
    if (exprKind(expr) == 'funcRef' && arg.name == 'fn') {
      final current = expr['fn'];
      return [
        for (final f in doc.functions) BlockOption(f.id, f.name),
        if (current is String && current.isNotEmpty && doc.function(current) == null) BlockOption(current, '（已经删掉的积木）', hint: '这块积木已经不在了'),
      ];
    }
    if (exprKind(expr) == 'param' && arg.name == 'name') {
      final names = <String>[if (tree is BeFunction) ...tree.paramNames];
      if (tree != null) {
        beVisitBlocks(tree.body, (b) {
          beVisitExprs(b, (e) {
            final ps = e['params'];
            if ((e['e'] == 'lambda' || e['e'] == 'lambdaExpr') && ps is List) names.addAll(ps.whereType<String>().where((p) => !names.contains(p)));
          });
        });
      }
      final current = expr['name'];
      return [for (final n in names) BlockOption(n, n), if (current is String && current.isNotEmpty && !names.contains(current)) BlockOption(current, current, hint: '这里没有这个参数')];
    }
    return null;
  }

  /// “这块积木本身”那一格显示函数的名字（存的是 id）。
  String? funcOptionLabel(LcArgSpec arg, String value) => arg.name == 'fn' && arg.kind == LcArgKind.choice && arg.choices.isEmpty ? (doc.function(value)?.name ?? '（已经删掉的积木）') : null;

  // —— 定义帽子 ——

  /// 改名：去掉两头空格；空的、太长、和别的积木重名都不改，并说原因。调用按 id 认，不用动。
  bool renameFunction(BeFunction f, String value) {
    final name = value.trim();
    final why = name.isEmpty
        ? '名字不能空着'
        : name.runes.length > 24
        ? '名字太长了（最多 24 个字）'
        : doc.functions.any((o) => !identical(o, f) && o.name == name)
        ? '已经有一块叫“$name”的积木了'
        : null;
    if (why != null) {
      onNotice?.call('$why，没有改。');
      return false;
    }
    // 没写文案模板的积木，积木上的话就是“名字 + 各个槽”，跟着名字变；写了模板的不动模板。
    f.look = f.look.copyWith(name: name);
    return true;
  }

  @override
  BlockHatParams? hatParams(LcBlockTree tree) => tree is BeFunction ? BlockHatParams(_blockParams(tree), max: kBeMaxParams) : null;

  @override
  bool setHatParams(LcBlockTree tree, List<BlockParam> params, {({String from, String to})? renamed}) {
    if (tree is! BeFunction) return false;
    final names = <String>{};
    for (final p in params) {
      final n = p.name.trim();
      final why = beParamNameReserved(n) ? '参数不能叫“$n”（这个名字积木自己要用）' : bkParamNameProblem(n, names);
      if (why != null) {
        onNotice?.call('$why，没有改。');
        return false;
      }
      names.add(n);
    }
    if (params.length > kBeMaxParams) {
      onNotice?.call('参数最多 $kBeMaxParams 个，没有改。');
      return false;
    }
    final old = tree.params;
    // 按名字认；改了名的那个靠 renamed 认。
    final origin = <int?>[
      for (final p in params)
        () {
          final i = old.indexWhere((o) => o.name == (renamed != null && p.name == renamed.to ? renamed.from : p.name));
          return i < 0 ? null : i;
        }(),
    ];
    // 标过的类型跟着原来那个参数走（改名、调顺序都不丢）。
    final next = [
      for (final (i, p) in params.indexed) BeParam(p.name.trim(), defaultValue: p.rest ? null : p.defaultValue, rest: p.rest, type: origin[i] == null ? null : old[origin[i]!].type),
    ];
    // 帽子上给的默认值同时是调用积木那个槽里先放的内容。
    var look = tree.look;
    for (final p in next) {
      final slot = look.slotFor(p.name);
      final was = renamed != null && p.name == renamed.to ? look.slotFor(renamed.from) : slot;
      if (was.kind != CustomSlotKind.value || was.defaultValue == p.defaultValue) continue;
      if (look.slots.any((s) => s.name == was.name)) {
        look = look.copyWith(
          slots: [for (final s in look.slots) s.name == was.name ? s.copyWith(defaultValue: p.defaultValue, clearDefault: p.defaultValue == null) : s],
        );
      } else if (p.defaultValue != null) {
        // 外观里还没有这个槽的设置（刚加的参数、或者一直用默认样子的）：补一条，各处调用才会先放上默认值。
        look = look.copyWith(
          slots: [
            ...look.slots,
            CustomBlockSlot(was.name, defaultValue: p.defaultValue),
          ],
        );
      }
    }
    final dropped = beReshapeFunction(doc, tree, look, next, origin);
    if (dropped > 0) onNotice?.call('删掉的参数在别处填的 $dropped 格内容一起丢掉了（点撤销能找回来）。');
    return true;
  }

  @override
  int hatParamUses(LcBlockTree tree, String name) => tree is BeFunction ? beFunctionUses(doc, tree.id) : 0;

  @override
  Map<String, dynamic>? paramExpr(String name) => beParam(name);

  @override
  void exprParamRenamed(LcBlockTree tree, Map<String, dynamic> expr, String from, String to) {
    // 匿名函数的参数改了名：它的式子、它口里的积木里读这个参数的地方跟着改。
    final body = <LcBlock>[
      LcBlock(
        op: 'do',
        args: {
          for (final e in expr.entries)
            if (e.key != kLcExprBody && e.key != 'e' && e.key != 'params') e.key: e.value,
        },
      ),
    ];
    beRenameParams(body, {from: to});
    for (final e in body.first.args.entries) {
      expr[e.key] = e.value;
    }
    beRenameParams(lcExprBody(expr) ?? <LcBlock>[], {from: to});
  }

  /// 画布上删掉定义那一串：和“我的积木”里点删除一样，各处的调用一起收拾掉。
  bool removeFunctionScript(String id) => beRemoveFunction(doc, id);

  BeFunction? addDefinition({double? x, double? y}) {
    if (doc.functions.length >= kBeMaxFunctions) {
      onNotice?.call('自定义积木已经有 $kBeMaxFunctions 块了，先删掉几块不用的。');
      return null;
    }
    return beAddFunction(doc, CustomBlockLook(beFreshFunctionName(doc)), const [], x: x, y: y);
  }
}

class _BeCustomHost extends BlockCustomHost {
  _BeCustomHost(this.host);
  final BeFuncHost host;

  BeDocument get _doc => host.doc;
  BeFunction? _fn(String id) => _doc.function(beCallId(id) ?? '');

  @override
  List<BlockCustom> get customs => host.funcTable.customs;

  @override
  String? create(CustomBlockLook look, List<String> params) {
    if (_doc.functions.length >= kBeMaxFunctions) {
      host.onNotice?.call('自定义积木已经有 $kBeMaxFunctions 块了，先删掉几块不用的。');
      return null;
    }
    return beCallOp(beAddFunction(_doc, look, params).id);
  }

  @override
  bool update(String id, CustomBlockLook look, List<String> params, List<int?> origin) {
    final f = _fn(id);
    if (f == null) return false;
    final old = f.params;
    final next = <BeParam>[
      for (final (i, p) in params.indexed)
        () {
          final o = i < origin.length ? origin[i] : null;
          final slot = look.slotFor(p);
          final was = o != null && o >= 0 && o < old.length ? old[o] : null;
          // 值槽“先放什么”就是参数的默认值；“剩下的全收”跟着原来那个参数走。
          return BeParam(p, defaultValue: was?.rest == true || slot.kind != CustomSlotKind.value ? null : slot.defaultValue, rest: was?.rest ?? false, type: was?.type);
        }(),
    ];
    final dropped = beReshapeFunction(_doc, f, look, next, origin, lookIsNew: true);
    _note = dropped > 0 ? '删掉的参数在别处填的 $dropped 格内容一起丢掉了' : null;
    return true;
  }

  String? _note;

  @override
  String? takeNotice() {
    final note = _note;
    _note = null;
    return note;
  }

  @override
  Object? slotValue(CustomBlockSlot slot) => beSlotValue(slot);

  @override
  int usesOf(String id) => beFunctionUses(_doc, beCallId(id) ?? '');

  @override
  bool remove(String id) => beRemoveFunction(_doc, beCallId(id) ?? '');

  @override
  String? definitionOf(String id) => _fn(id)?.id;

  @override
  bool get canWrap => true;

  @override
  String? wrapBlocker(LcBlockTree tree, LcBlockPath from) => beWrapBlocker(_doc, tree, from);

  @override
  List<String> outerNames(LcBlockTree tree, LcBlockPath from) => beWrapOuterNames(_doc, tree, from);

  @override
  String? wrap(LcBlockTree tree, LcBlockPath from, CustomBlockLook look, List<String> params) {
    final f = beWrapTail(_doc, tree, from, look, params);
    return f == null ? null : beCallOp(f.id);
  }

  @override
  List<BlockLookProblem> check(CustomBlockLook look, List<String> params, {String? editing}) {
    final name = look.name.trim();
    return [
      if (beBlockSpecs.values.any((s) => s.label == name) || beExprSpecs.values.any((s) => s.label == name)) BlockLookProblem(BlockLookField.name, '“$name”是内置积木的名字，换一个'),
      for (final p in params)
        if (beParamNameReserved(p.trim())) BlockLookProblem(BlockLookField.slot, '参数不能叫“${p.trim()}”（这个名字积木自己要用）', slot: p),
      if (params.length > kBeMaxParams) const BlockLookProblem(BlockLookField.template, '参数太多了（最多 $kBeMaxParams 个）'),
    ];
  }
}
