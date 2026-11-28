/// 后端积木宿主里管“库”的那一半（积木第 5 版·库 2）：库积木进积木盒（一个库一页）、库的帽子积木开头的串、
/// 库文档里才有的两块（“做口里的积木”“交给用的人选的变量”）。不依赖界面。
library;

import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_func_host.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_table.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' as lib_blocks show libCategories;
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 积木盒里库的帽子模板的 id：`libhat:` 加库积木的 op。
const String kBeLibHatTemplate = kLibHatTemplate;

mixin BeLibHost on BlockHost, BeFuncHost {
  BeLibTable get libTable => funcTable.libs;

  /// 页面逻辑里：页面上有什么（控件、状态、属性、页面）。不是页面逻辑（后端文档、库文档）＝null。
  BePageCx? pageCx;

  /// 接在积木盒后面的页：每个用上的库一页；库文档再多一页“做库积木”（怎么分是“文档无关”那一层定的）。
  List<BlockCategory> get libCategories => lib_blocks.libCategories(libTable, first: false);

  /// 前端文档排在积木盒最前面的那几页：自带“页面”库的事件、状态、控件、页面。
  List<BlockCategory> get pageCategories => lib_blocks.libCategories(libTable, first: true, hat: _hat);

  BlockHat _hat(BeLibEntry e, Map<String, dynamic> args) => libHatLook(e, args, label: pageCx?.label);

  List<BlockOption> _picks(String pick, {Object? node, Object? current}) {
    final cx = pageCx;
    final list =
        switch (pick) {
          'node' => cx?.nodes,
          'state' => cx?.states,
          'prop' => cx?.props(node is String ? node : null),
          'page' => cx?.pages,
          'instance' => cx?.instances,
          'event' => cx?.events(node is String ? node : null),
          _ => null,
        } ??
        const <BlockOption>[];
    return [...list, if (current is String && current.isNotEmpty && !list.any((o) => o.value == current)) BlockOption(current, current, hint: '页面里已经没有它了')];
  }

  /// 帽子上“从页面里挑一个”的槽有哪些选项；不归这边管返回 null。
  List<BlockOption>? libHatSlotOptions(LcBlockTree tree, String slotId) {
    if (tree is! BeLibHat) return null;
    final pick = libTable.of(tree.op)?.pickOf(slotId);
    return pick == null ? null : _picks(pick, node: tree.args['node'], current: tree.args[slotId]);
  }

  /// 下拉里选中的那个值在积木上显示成什么（控件的名字、页面的标题）；不归这边管返回 null。
  String? libOptionLabel(LcArgSpec arg, String value) {
    final cx = pageCx;
    if (cx == null || arg.kind != LcArgKind.choice || arg.choices.isNotEmpty || !kLibPickHints.containsValue(arg.label)) return null;
    return switch (arg.name) {
      'node' => value.isEmpty ? '选控件' : cx.label('node', value) ?? '（已经删掉的控件）',
      'page' => value.isEmpty ? '选页面' : cx.label('page', value) ?? '（已经删掉的页面）',
      'prop' => value.isEmpty ? '选属性' : cx.label('prop', value) ?? value,
      _ => null,
    };
  }

  static String _show(Object? v, String fallback) => libHatShow(v, fallback);

  BlockHat? libHatOf(LcBlockTree tree) {
    if (tree is! BeLibHat) return null;
    final e = libTable.of(tree.op);
    return e == null ? BlockHat([BlockHatPart.text('库「${beLibOpOf(tree.op)?.lib ?? ''}」的帽子（这个库现在用不了）')], colorKey: BlockColorKey.unknown) : _hat(e, tree.args);
  }

  String? libHatSlotValue(LcBlockTree tree, String slotId) => tree is BeLibHat ? _show(tree.args[slotId], '') : null;

  bool? libSetHatSlot(LcBlockTree tree, String slotId, String value) {
    if (tree is! BeLibHat) return null;
    final old = tree.args[slotId];
    final next = old is num ? (num.tryParse(value.trim()) ?? old) : value;
    if (next == old) return false;
    tree.args[slotId] = next;
    return true;
  }

  LcBlockTree? libAddScript(String templateId, {double? x, double? y}) {
    if (!templateId.startsWith(kBeLibHatTemplate)) return null;
    final e = libTable.of(templateId.substring(kBeLibHatTemplate.length));
    if (e == null || !e.isHat || doc.hats.length >= kBeMaxLibHats) return null;
    final ids = {for (final t in beTrees(doc)) t.id, for (final t in doc.core.trees) t.id, for (final h in doc.hats) h.id};
    var n = 1;
    while (ids.contains('h$n')) {
      n++;
    }
    final hat = BeLibHat(id: 'h$n', op: e.op, args: {for (final a in e.newArgs(beSlotValue).entries) a.key: _plain(a.value)}, x: x, y: y);
    doc.hats.add(hat);
    return hat;
  }

  /// 帽子上的槽只放直接填的字 / 数：把新积木的默认值（一个表达式）换成它里面的那个值。
  static Object? _plain(Object? v) => v is Map ? (v['v'] is String || v['v'] is num || v['v'] is bool ? v['v'] : '') : (v is String || v is num || v is bool ? v : '');

  bool isLibTemplate(String id) => id.startsWith(kBeLibHatTemplate);

  bool libRemoveScript(String id) {
    final before = doc.hats.length;
    doc.hats.removeWhere((h) => h.id == id);
    return doc.hats.length != before;
  }

  LcBlock? libNewBlock(String op) {
    final e = libTable.of(op);
    if (e != null) return LcBlock(op: op, args: e.newArgs(beSlotValue));
    if (doc.library == null) return null;
    return switch (op) {
      kBeLibMouthOp => LcBlock(op: op, args: {'name': ''}),
      kBeLibPutOp => LcBlock(op: op, args: {'value': exText('')}),
      _ => null,
    };
  }

  Map<String, dynamic>? libNewExpr(String kind) {
    final e = libTable.of(kind);
    return e == null ? null : {'e': kind, ...e.newArgs(beSlotValue)};
  }

  String? libColorKey(String op) => (libTable.of(op) == null ? null : libEntryColor(libTable.of(op)!)) ?? (op == kBeLibMouthOp || op == kBeLibPutOp ? BlockColorKey.custom : null);

  /// “做口里的积木”的下拉：这个函数公开成的积木有哪些口。不归这边管返回 null。
  List<BlockOption>? libOptions(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) {
    final args = expr ?? block?.args;
    final pick = libTable.of(expr != null ? exprKind(expr) : block?.op)?.pickOf(arg.name);
    if (pick != null) return _picks(pick, node: args?['node'], current: args?[arg.name]);
    if (block?.op != kBeLibMouthOp || arg.name != 'name') return null;
    final names = tree == null ? const <String>[] : libTable.mouthsOfFunction(tree.id);
    final current = block!.args['name'];
    return [for (final n in names) BlockOption(n, n), if (current is String && current.isNotEmpty && !names.contains(current)) BlockOption(current, '$current（已经没有这个口了）')];
  }
}
