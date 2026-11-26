/// 后端积木宿主里“类型”的那一半（规矩版本 2 的文档才有东西；版本 1 的文档这里每个入口都是“没有”，界面和以前一样）：
/// - 把类型检查的问题并进校验结果（标红、问题列表、小卡都走原来那一套），每条带上能在积木上做的“一键修”；
/// - 选中积木时那一行类型（`总和：整数`、`加倍：(整数) → 整数`）；
/// - 改标注：参数、函数交回什么、“新建变量 / 常量”；
/// - “升级到严格规矩”。
///
/// 做成 mixin 混进 `BeBlockHost`。类型检查本身和“问题对回哪一格”在 backend_type_bridge.dart（临时的，见那个文件开头）。
library;

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_type_fix.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “升级到严格规矩”以后哪些地方会变（给确认面板列出来；设计 B 分册 2.2、5.1、5.2）。
const List<({String title, String detail})> kBeStrictChanges = [
  (title: '东西放错了地方会标红', detail: '比如要数字的地方放了文字。以前会悄悄换算（"abc" 当成 0），以后直接标出来；有红的时候不生成新代码。'),
  (title: '数字分成整数和小数', detail: '整数最大到 9007199254740991，加减乘超了会报“整数超出范围”；小数用在要整数的地方要先“取整”。'),
  (title: '除以 0 会报错', detail: '以前除以 0 得 0，以后运行到这里会报“除以 0”。'),
  (title: '文字不再自动变成数字', detail: '要用“把 … 变成整数”或“转换类型”积木自己转；变不了的时候得到“空”。'),
  (title: '可能是空的值要先处理', detail: '用“如果 … 不是空”判断，或者包一层“… 是空就用 …”。'),
  (title: '可以给参数、结果、变量标类型', detail: '选中“定义”或“新建变量”那块积木，上面多一行类型，点“标类型”。不标也行，会自己推。'),
];

/// “运算”页加上严格规矩才有的那一组。
BlockCategory beStrictOperatorCategory(BlockCategory c) => BlockCategory(
  id: c.id,
  label: c.label,
  colorKey: c.colorKey,
  hats: c.hats,
  blocks: c.blocks,
  exprs: c.exprs,
  groups: [
    ...c.groups,
    const BlockGroup('空和整数', exprs: ['parseInt', 'orElse', 'must']),
  ],
);

/// 类型标注能选的几种（界面上的选择表；“不标”另算）。
const List<LType> kBeTypeChoices = [LType.integer, LType.number, LType.text, LType.boolean, LType.any];

mixin BeTypeHost on BlockHost {
  BeDocument get doc;

  BeTypeCheck? _check;
  int _checkRev = -1;

  /// 这一刻的类型检查结果（内容没变不重查）；规矩版本 1 的文档是 null。
  BeTypeCheck? get typeCheck {
    if (!langRulesStrict(doc.rules)) return null;
    if (_checkRev != revision) {
      _check = beTypeCheck(doc);
      _checkRev = revision;
    }
    return _check;
  }

  bool get strictRules => langRulesStrict(doc.rules);

  LcBlockTree? _tree(String id) => doc.function(id) ?? doc.routes.where((r) => r.id == id).firstOrNull;

  /// 把类型问题并进 [base]（原来那些校验的结果）。版本 1 原样返回 [base]（同一个对象）。
  List<BlockIssue> withTypeIssues(List<BlockIssue> base) {
    final check = typeCheck;
    if (check == null || check.findings.isEmpty) return base;
    String? fnName(String id) => doc.function(id)?.name;
    bool sameSlot(BlockIssue i, BeSlotRef at) {
      final xp = i.exprPath ?? const <Object>[];
      if (i.scriptId != at.treeId || i.arg != at.arg || i.path.length != at.path.length || xp.length != at.exprPath.length) return false;
      for (var k = 0; k < i.path.length; k++) {
        if (!lcSameStep(i.path[k], at.path[k]) && !(k == 0 && i.path[k].index == at.path[k].index)) return false;
      }
      for (var k = 0; k < xp.length; k++) {
        if (xp[k] != at.exprPath[k]) return false;
      }
      return true;
    }

    final out = <BlockIssue>[
      // 同一格上类型检查已经说了“要什么、放进来的是什么”，老的那条“类型对不上”（G10）就不重复了。
      for (final i in base)
        if (!(i.rule == 'G10' && check.findings.any((f) => sameSlot(i, f.at)))) i,
    ];
    for (final f in check.findings) {
      final tree = _tree(f.at.treeId);
      if (tree == null) continue;
      final block = f.at.path.isEmpty ? null : tree.blockAt(f.at.path);
      final scope = tree is BeFunction ? '积木「${tree.name}」' : '接口「${describeBeRoute(tree as BeRoute)}」';
      final spot = block == null ? '' : '${describeBeBlockPath(tree, f.at.path)}（${describeBeBlock(block, fnName)}）';
      final issue = f.issue;
      out.add(
        BlockIssue(
          message: '$scope$spot：${issue.message}',
          isError: issue.level == LTypeLevel.error,
          isHint: issue.level == LTypeLevel.hint,
          scriptId: tree.id,
          path: f.at.path,
          arg: f.at.arg,
          exprPath: f.at.arg == null ? null : f.at.exprPath,
          rule: issue.code,
          problem: issue.message,
          fix: issue.rule.advice,
          group: scope,
          spot: spot,
          actions: [for (final x in f.fixes) BlockIssueAction(x.fix.label, () => applyTypeFix(x.fix, x.slot))],
        ),
      );
    }
    return out;
  }

  /// 做一次“一键修”（一条撤销记录）。改成了返回 true。
  bool applyTypeFix(LFix fix, BeSlotRef slot) {
    final target = fix.target;
    final got = target is LExpr ? typeCheck?.result.typeOf(target) : null;
    var done = false;
    edit(() {
      final tree = _tree(slot.treeId);
      done = tree != null && beApplyTypeFix(tree, fix, slot, got: got);
    });
    return done;
  }

  // —— 类型一行字 ——

  String? _sigLine(BeFunction f) {
    final sig = typeCheck?.result.funcs[f.ident];
    if (sig == null) return null;
    return '${f.name}：(${[for (final p in sig.params) p.show()].join(', ')}) → ${sig.returns.show()}';
  }

  static const Map<String, String> _nameArgs = {'let': 'name', 'const': 'name', 'setVar': 'name', 'changeVar': 'name', 'forCount': 'name', 'forEach': 'item'};

  @override
  String? typeLineOf(String scriptId, LcBlockPath path) {
    final check = typeCheck;
    final tree = _tree(scriptId);
    if (check == null || tree == null) return null;
    if (path.isEmpty) return tree is BeFunction ? _sigLine(tree) : null;
    final b = tree.blockAt(path);
    if (b == null) return null;
    final callee = doc.function(beCallId(b.op) ?? '');
    if (callee != null) return _sigLine(callee);
    final name = b.args[_nameArgs[b.op]];
    if (name is! String || name.isEmpty) return null;
    final scope = check.scopes[scriptId];
    // 先找这一串自己这一层的；匿名函数里新建的在它自己那一层，按名字再找一遍。
    final v = check.result.vars.where((v) => v.scope == scope && v.name == name).firstOrNull ?? check.result.vars.where((v) => v.name == name).firstOrNull;
    return v == null ? null : '$name：${v.type.show()}';
  }

  @override
  bool typeEditableAt(String scriptId, LcBlockPath path) {
    if (!strictRules) return false;
    final tree = _tree(scriptId);
    if (tree == null) return false;
    if (path.isEmpty) return tree is BeFunction;
    final op = tree.blockAt(path)?.op;
    return op == 'let' || op == 'const';
  }

  // —— 改标注（null＝不标）——

  void setParamType(String functionId, String param, LType? type) => edit(() {
    final p = doc.function(functionId)?.params.where((p) => p.name == param).firstOrNull;
    if (p != null) p.type = type;
  });

  void setReturnType(String functionId, LType? type) => edit(() => doc.function(functionId)?.returns = type);

  /// “新建变量 / 常量”那块上标的类型。
  LType? letTypeAt(String scriptId, LcBlockPath path) {
    final b = _tree(scriptId)?.blockAt(path);
    return b == null ? null : beLetType(b);
  }

  void setLetType(String scriptId, LcBlockPath path, LType? type) => edit(() {
    final b = _tree(scriptId)?.blockAt(path);
    if (b == null || (b.op != 'let' && b.op != 'const')) return;
    type == null ? b.args.remove(kBeLetTypeArg) : b.args[kBeLetTypeArg] = lTypeToJson(type);
  });

  // —— 升级 ——

  /// 现在升级的话，会多出几处要改的（错误）、几处提醒 / 警告。已经是严格规矩返回 null。
  ({int errors, int others})? previewStrict() {
    if (strictRules) return null;
    final copy = doc.clone()..rules = kLangRulesStrict;
    final check = beTypeCheck(copy);
    if (check == null) return (errors: 0, others: 0);
    final errors = check.findings.where((f) => f.issue.isError).length;
    return (errors: errors, others: check.findings.length - errors);
  }

  /// 升级到严格规矩（一条撤销记录：刚升完后悔可以点撤销；存盘以后再打开就回不去了）。
  void upgradeToStrict() {
    if (strictRules) return;
    edit(() => doc.rules = kLangRulesStrict);
  }
}
