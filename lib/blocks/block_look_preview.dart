/// “新建积木”页上方的预览：把还没存的外观当成一块真的积木排出来。
///
/// 做法：套一层只管这一块的宿主（[BkLookPreviewHost]）——问到预览那块就照草稿答，别的值（槽里先放的字面量）问真宿主，
/// 这样预览和存好以后积木盒里的样子用的是同一套排版、同一套颜色。不碰真宿主的内容。
library;

import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 预览那一块在模型里的名字（不会存下来）。
const String kBlockLookPreviewId = '@look-preview';

class BkLookPreviewHost extends BlockHost {
  BkLookPreviewHost(this.base, CustomBlockLook look, List<String> params) : draft = BlockCustom(kBlockLookPreviewId, look, params);

  final BlockHost base;
  final BlockCustom draft;

  String get _color => BlockColorKey.all.contains(draft.look.colorKey) ? draft.look.colorKey : BlockColorKey.custom;

  /// 预览那一块的排版。参数名不合适（空的、重名）时那几个槽先不画，其余照常。
  BkScriptLayout layout(BlockLayoutEngine engine) {
    final custom = base.custom;
    final args = <String, dynamic>{
      for (final s in draft.slots) s.name: custom?.slotValue(s) ?? (s.kind == CustomSlotKind.choice ? (s.options.isEmpty ? '' : s.options.first) : null),
    };
    if (draft.isValue) return engine.layoutExpr({'e': kBlockLookPreviewId, ...args}, controls: false);
    return engine.layoutStack([LcBlock(op: kBlockLookPreviewId, args: args)], controls: false);
  }

  @override
  LcBlockSpec? blockSpec(String op) => op == kBlockLookPreviewId ? (draft.isValue ? null : bkLookBlockSpec(draft)) : base.blockSpec(op);
  @override
  LcExprSpec? exprSpec(String kind) => kind == kBlockLookPreviewId ? (draft.isValue ? bkLookExprSpec(draft) : null) : base.exprSpec(kind);
  @override
  String blockColorKey(String op) => op == kBlockLookPreviewId ? _color : base.blockColorKey(op);
  @override
  String exprColorKey(String kind) => kind == kBlockLookPreviewId ? _color : base.exprColorKey(kind);
  @override
  String? blockSentence(String op) => op == kBlockLookPreviewId ? bkLookSentence(draft.look, draft.params) : base.blockSentence(op);
  @override
  String? exprSentence(String kind) => kind == kBlockLookPreviewId ? bkLookSentence(draft.look, draft.params) : base.exprSentence(kind);
  @override
  String? armSentence(String op) => base.armSentence(op);
  @override
  bool isBooleanExpr(Map<String, dynamic> expr) => exprKind(expr) == kBlockLookPreviewId ? draft.look.shape == CustomBlockShape.boolean : base.isBooleanExpr(expr);
  @override
  Map<String, dynamic> defaultExpr(LcArgSpec arg) => base.defaultExpr(arg);
  @override
  String optionLabel(LcArgSpec arg, String value) => base.optionLabel(arg, value);
  @override
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) => const [];

  // —— 下面这些预览用不到：没有内容，也不能改 ——
  @override
  List<BlockCategory> get categories => const [];
  @override
  List<LcBlockTree> get scripts => const [];
  @override
  BlockHat hatOf(LcBlockTree tree) => base.hatOf(tree);
  @override
  String hatSlotValue(LcBlockTree tree, String slotId) => '';
  @override
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId) => const [];
  @override
  bool setHatSlot(LcBlockTree tree, String slotId, String value) => false;
  @override
  LcBlockTree? addScript(String templateId, {double? x, double? y}) => null;
  @override
  bool removeScript(String id) => false;
  @override
  LcBlock newBlock(String op) => base.newBlock(op);
  @override
  Map<String, dynamic> newExpr(String kind) => base.newExpr(kind);
  @override
  List<BlockIssue> get issues => const [];
  @override
  String get codeText => '';
  @override
  String get codeLanguage => '';
  @override
  void edit(void Function() change) {}
  @override
  bool get canUndo => false;
  @override
  bool get canRedo => false;
  @override
  void undo() {}
  @override
  void redo() {}
  @override
  int get revision => 0;
}
