/// 前端（低代码页面逻辑）这一边的积木宿主：把 [LcDocument] 的变量、事件处理、积木目录、校验、翻出来的 JavaScript
/// 包成积木编辑器认的 [BlockHost]。编辑器（lib/blocks）从此不直接碰 LcDocument。
///
/// 一串脚本＝一个事件处理（[LcHandler]）；帽子＝“当 [控件] 被点击”这类；积木盒按 事件 / 变量 / 控件 / 流程 / 交互 / 网络 / 运算 / 值 分页。
/// 改动走搭建页给的 [LcEdit]（一次＝一条撤销记录＝一次落盘），撤销重做也交还给搭建页。
library;

import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/logic_blocks.dart' as catalog;
import 'package:lopicode/lowcode/logic_blocks.dart' hide newBlock, newExpr;
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';

/// 积木上的话。`{名字}` 是参数的位置。
const Map<String, String> _blockSentences = {
  'setVar': '把 {name} 设为 {value}',
  'changeVar': '把 {name} 加上 {by}',
  'setProp': '把 {node} 的 {prop} 改成 {value}',
  'if': '如果 {cond} 那么',
  'repeat': '重复 {times} 次',
  'wait': '等 {ms} 毫秒，然后',
  'alert': '弹出提示 {message}',
  'navigate': '跳转到 {url}',
  'log': '写到控制台 {value}',
  'fetch': '用 {method} 请求 {url} 结果放进 {into} 成功后',
};

const Map<String, String> _exprSentences = {'var': '{name}', 'prop': '{node} 的 {prop}', 'event': '输入的内容', 'bin': '{l} {op} {r}', 'not': '不是 {x}', 'join': '拼接 {items}'};

/// 运算符在积木上显示成符号（下拉里还是中文全称）。
const Map<String, String> _opSigns = {'+': '+', '-': '−', '*': '×', '/': '÷', '%': '余', '==': '=', '!=': '≠', '<': '<', '<=': '≤', '>': '>', '>=': '≥', 'and': '并且', 'or': '或者'};

const Map<String, String> _colorOfCategory = {
  '变量': BlockColorKey.variable,
  '控件': BlockColorKey.widget,
  '流程': BlockColorKey.control,
  '交互': BlockColorKey.action,
  '网络': BlockColorKey.network,
  '运算': BlockColorKey.operator,
  '直接填': BlockColorKey.value,
};

class LogicBlockHost extends BlockHost {
  /// `doc`＝搭建页手里那份活的文档；`onEdit`＝搭建页的统一改动入口。
  /// 撤销重做交给搭建页：`onUndo / onRedo` 做完以后返回换上来的那份文档（没得撤返回 null）。
  LogicBlockHost({required LcDocument doc, required this.onEdit, this.canUndoOf, this.canRedoOf, this.onUndo, this.onRedo, this.preferTarget})
    : _doc = doc; // ignore: prefer_initializing_formals 对外的参数名要叫 doc，不叫 _doc

  LcDocument _doc;
  final LcEdit onEdit;
  final bool Function()? canUndoOf;
  final bool Function()? canRedoOf;
  final LcDocument? Function()? onUndo;
  final LcDocument? Function()? onRedo;

  /// 新建事件时优先挂在这个控件上（从某个控件点进逻辑页时给）；它不适合那种事件就照旧挑第一个合适的。
  final String? preferTarget;
  int _revision = 0;

  LcDocument get doc => _doc;

  /// 外面换了文档（搭建页撤销重做、重新读盘）时调。
  void replaceDoc(LcDocument doc) {
    _doc = doc;
    _bump();
  }

  void _bump() {
    _revision++;
    _categories = null;
    onChanged?.call();
  }

  // —— 目录 ——

  List<BlockCategory>? _categories;

  @override
  List<BlockCategory> get categories => _categories ??= [
    BlockCategory(
      id: 'event',
      label: '事件',
      colorKey: BlockColorKey.event,
      hats: [for (final e in LcHandler.events) BlockHatTemplate(e, _hat(e, null), hint: describeEvent(e))],
    ),
    for (final c in {...lcBlockCategories, ...lcExprCategories})
      BlockCategory(
        id: c,
        label: c == '直接填' ? '值' : c,
        colorKey: _colorOfCategory[c] ?? BlockColorKey.unknown,
        blocks: [for (final s in blockSpecsIn(c)) s.op],
        exprs: [for (final s in exprSpecsIn(c)) s.kind],
      ),
  ];

  @override
  LcBlockSpec? blockSpec(String op) => lcBlockSpecs[op];

  @override
  LcExprSpec? exprSpec(String kind) => lcExprSpecs[kind];

  @override
  String? blockSentence(String op) => _blockSentences[op];

  @override
  String? exprSentence(String kind) => _exprSentences[kind];

  @override
  bool isBooleanExpr(Map<String, dynamic> expr) => exprType(expr, (name) => _doc.logic.variable(name)?.type) == LcType.boolean;

  // —— 脚本 ——

  @override
  List<LcBlockTree> get scripts => _doc.logic.handlers;

  BlockHat _hat(String event, String? target) {
    BlockHatPart who() => target == null || target.isEmpty || _doc.find(target) == null
        ? BlockHatPart.slot('target', target == null || target.isEmpty ? '选控件' : '已删除的控件', empty: true)
        : BlockHatPart.slot('target', _nodeName(target));
    return BlockHat(switch (event) {
      'click' => [const BlockHatPart.text('当'), who(), const BlockHatPart.text('被点击')],
      'input' => [const BlockHatPart.text('当'), who(), const BlockHatPart.text('的内容变化')],
      'load' => const [BlockHatPart.text('当页面打开时')],
      _ => [BlockHatPart.text(describeEvent(event))],
    });
  }

  @override
  BlockHat hatOf(LcBlockTree tree) => tree is LcHandler ? _hat(tree.event, tree.target) : const BlockHat([BlockHatPart.text('不认识的事件')], colorKey: BlockColorKey.unknown);

  @override
  String hatSlotValue(LcBlockTree tree, String slotId) => tree is LcHandler && slotId == 'target' ? (tree.target ?? '') : '';

  @override
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId) {
    if (tree is! LcHandler || slotId != 'target' || tree.event == 'load') return const [];
    return _nodeOptions(tree.event == 'input' ? const ['input'] : null);
  }

  @override
  bool setHatSlot(LcBlockTree tree, String slotId, String value) {
    if (tree is! LcHandler || slotId != 'target' || tree.event == 'load' || _doc.find(value) == null) return false;
    tree.target = value;
    return true;
  }

  @override
  LcBlockTree? addScript(String templateId, {double? x, double? y}) {
    final wanted = templateId == 'input' ? const ['input'] : const ['button'];
    final nodes = _nodeOptions(wanted);
    final prefer = preferTarget;
    final target = prefer != null && nodes.any((n) => n.value == prefer) ? prefer : (nodes.isEmpty ? null : nodes.first.value);
    final h = _doc.logic.addHandler(templateId, target: target);
    h?.x = x;
    h?.y = y;
    return h;
  }

  @override
  bool removeScript(String id) => _doc.logic.removeHandler(id);

  // —— 造新的 ——

  @override
  LcBlock newBlock(String op) => catalog.newBlock(op, _doc);

  @override
  Map<String, dynamic> newExpr(String kind) => catalog.newExpr(kind, _doc);

  // —— 参数 ——

  /// 控件叫什么：describeNode 的结果去掉两头的「」（积木的槽位本身就是个框）。
  String _nodeName(String id) {
    final s = describeNode(_doc, id);
    return s.length >= 2 && s.startsWith('「') && s.endsWith('」') ? s.substring(1, s.length - 1) : s;
  }

  /// 页面里的控件（从上到下）；`types` 不为 null 就只要这几种。
  List<BlockOption> _nodeOptions(List<String>? types) {
    final out = <BlockOption>[];
    void walk(LcNode n) {
      if (types == null || types.contains(n.type)) out.add(BlockOption(n.id, _nodeName(n.id)));
      n.children.forEach(walk);
    }

    walk(_doc.root);
    return out;
  }

  @override
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) {
    switch (arg.kind) {
      case LcArgKind.variable:
        return [if (arg.optional) const BlockOption('', '不选'), for (final v in _doc.logic.variables) BlockOption(v.name, v.name, hint: describeVarType(v.type))];
      case LcArgKind.node:
        return _nodeOptions(null);
      case LcArgKind.choice:
        // 选“改什么 / 读什么”时，只列这个控件真有的属性。
        final nodeId = expr != null ? expr['node'] : block?.args['node'];
        final node = arg.name == 'prop' && nodeId is String ? _doc.find(nodeId) : null;
        final allowed = node == null ? arg.choices : (expr != null ? readablePropsFor(node.type) : writablePropsFor(node.type));
        return [
          for (final c in arg.choices)
            if (allowed.contains(c)) BlockOption(c, arg.choiceLabel(c)),
        ];
      default:
        return const [];
    }
  }

  /// 换了控件 / 换了“改什么”以后，把旁边对不上的参数顺手调对（都在同一次改动里）：
  /// - “把 [控件] 的 [属性] 改成 …”：新控件没有原来那个属性，就换成它有的第一个；属性在“显示 / 隐藏”和别的之间换，值也跟着换成 是否 / 文字。
  /// - “[控件] 的 [属性]”这种取值：新控件读不到原来那个属性，同样换成第一个读得到的。
  @override
  void argChanged(LcBlockTree tree, LcBlock block, String arg, List<Object> exprPath) {
    if (exprPath.isEmpty) {
      if (block.op != 'setProp') return;
      if (arg == 'node') {
        final node = block.args['node'], prop = block.args['prop'];
        final type = node is String ? _doc.find(node)?.type : null;
        if (type != null && prop is String && !propFitsNode(prop, type)) {
          final fits = writablePropsFor(type);
          if (fits.isNotEmpty) block.args['prop'] = fits.first;
        }
      }
      if (arg == 'node' || arg == 'prop') {
        final value = asExpr(block.args['value']);
        final kind = value == null ? null : exprKind(value);
        if (block.args['prop'] == 'visible' && (kind == 'text' || kind == 'num')) block.args['value'] = exBool(true);
        if (block.args['prop'] != 'visible' && kind == 'bool') block.args['value'] = exText('');
      }
      return;
    }
    if (exprPath.last != 'node') return;
    final owner = asExpr(bkExprAt(block, arg, exprPath.sublist(0, exprPath.length - 1)));
    if (owner == null || exprKind(owner) != 'prop') return;
    final node = owner['node'], prop = owner['prop'];
    final type = node is String ? _doc.find(node)?.type : null;
    if (type == null || prop is! String) return;
    final fits = readablePropsFor(type);
    if (fits.isNotEmpty && !fits.contains(prop)) owner['prop'] = fits.first;
  }

  @override
  String optionLabel(LcArgSpec arg, String value) => switch (arg.kind) {
    LcArgKind.node => _nodeName(value),
    LcArgKind.choice => arg.name == 'op' ? (_opSigns[value] ?? value) : arg.choiceLabel(value).split('（').first,
    _ => value,
  };

  // —— 校验与代码 ——

  late final BlockIssueCache _issueCache = BlockIssueCache(() => [for (final i in validateLogic(_doc)) blockIssueOf(i)], () => _revision, () => onChanged?.call());

  @override
  List<BlockIssue> get issues => _issueCache.fresh();

  @override
  List<BlockIssue> get liveIssues => _issueCache.read();

  @override
  void stopIssueTimer() => _issueCache.stop();

  /// “错误”级的问题有几条（有错误时 logic.js 不重新导出）。
  int get errorCount => issues.where((i) => i.isError).length;

  @override
  String get codeText => exportLogicJs(_doc);

  @override
  String get codeLanguage => 'JavaScript';

  @override
  String get codeFileName => 'logic.js';

  // —— 改动、撤销 ——

  @override
  void edit(void Function() change) {
    onEdit((d) {
      _doc = d;
      change();
    });
    _bump();
  }

  @override
  bool get canUndo => canUndoOf?.call() ?? false;

  @override
  bool get canRedo => canRedoOf?.call() ?? false;

  @override
  void undo() {
    final d = onUndo?.call();
    if (d != null) replaceDoc(d);
  }

  @override
  void redo() {
    final d = onRedo?.call();
    if (d != null) replaceDoc(d);
  }

  @override
  int get revision => _revision;
}
