/// 后端积木宿主里“类型”的那一半（规矩版本 2 的文档才有东西；版本 1 的文档这里每个入口都是“没有”，界面和以前一样）：
/// - 把类型检查的问题并进校验结果（标红、问题列表、小卡都走原来那一套），每条带上能在积木上做的“一键修”；
/// - 选中积木时那一行类型（`总和：整数`、`加倍：(整数) → 整数`）；
/// - 改标注：参数、函数交回什么、“新建变量 / 常量”；
/// - “升级到严格规矩”。
///
/// 做成 mixin 混进 `BeBlockHost`。类型检查本身和“问题对回哪一格”在 backend_type_bridge.dart；`validateBackend` 用的也是那一份。
library;

import 'package:lopicode/backend/backend_core_fix.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_type_fix.dart';
import 'package:lopicode/backend/backend_validate_types.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “升级到严格规矩”以后哪些地方会变（给确认面板列出来；设计 B 分册 2.2、5.1、5.2）。
const List<({String title, String detail})> kBeStrictChanges = [
  (title: '东西放错了地方会标红', detail: '比如要数字的地方放了文字。以前会悄悄换算（"abc" 当成 0），以后直接标出来；有红的时候不生成新代码。'),
  (title: '数字分成整数和小数', detail: '整数最大到 9007199254740991，加减乘超了会报“整数超出范围”；小数用在要整数的地方要先“取整”。'),
  (title: '除以 0 会报错', detail: '以前除以 0 得 0，以后运行到这里会报“除以 0”。'),
  (title: '“等于”不再悄悄换算', detail: '以前 1 和 "1"、空和 "" 算相等，以后不算：要比就先转成同一种，可能是空的先处理空。这一条不一定会标红，升级后请自己看一遍用到“等于”的地方。'),
  (title: '文字不再自动变成数字', detail: '要用“把 … 变成整数”或“转换类型”积木自己转；变不了的时候得到“空”。'),
  (title: '可能是空的值要先处理', detail: '用“如果 … 不是空”判断，或者包一层“… 是空就用 …”。'),
  (title: '可以给参数、结果、变量标类型', detail: '选中“定义”或“新建变量”那块积木，上面多一行类型，点“标类型”。不标也行，会自己推。'),
];

/// “升级到严格规矩”之前先算给用户看的：升级后会多出什么。
class BeStrictPreview {
  const BeStrictPreview(this.errors, this.others, this.fixable, this.items);

  /// 要改的（标红）有几处、提醒 / 警告有几处。
  final int errors, others;

  /// 要改的里面有几处能一键修。
  final int fixable;

  /// 逐条：在哪、什么问题、是不是要改的、能不能一键修。
  final List<({String where, String problem, bool isError, bool fixable})> items;
}

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
      _check = beTypeCheckShared(doc);
      _checkRev = revision;
    }
    return _check;
  }

  bool get strictRules => langRulesStrict(doc.rules);

  LcBlockTree? _tree(String id) => beTreeById(doc, id);

  /// 把类型问题并进 [base]（原来那些校验的结果）。版本 1 原样返回 [base]（同一个对象）。
  List<BlockIssue> withTypeIssues(List<BlockIssue> base) {
    final check = typeCheck;
    if (check == null || check.findings.isEmpty) return base;
    String? libName(String op) {
      final ref = beLibOpOf(op);
      return ref == null ? null : doc.loaded.where((l) => l.id == ref.lib).firstOrNull?.block(ref.block)?.look.name;
    }

    String? fnName(String id) => libName(id) ?? doc.function(id)?.name;
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
      for (final i in base)
        // 校验（validateBackend）已经带出来的类型问题不要：下面换成同一批、但带着“式子里的位置”和一键修的那一份，免得同一个问题出现两次。
        // 同一格上类型检查已经说了“要什么、放进来的是什么”，老的那条“类型对不上”（G10）也不重复。
        if (!beIsTypeRule(i.rule) && !(i.rule == 'G10' && check.findings.any((f) => sameSlot(i, f.at)))) i,
    ];
    for (final f in check.findings) {
      final tree = _tree(f.at.treeId);
      List<BlockIssueAction> extra() => [for (final x in f.extra) BlockIssueAction(x.label, () => applyCoreFix(x))];
      if (tree == null) {
        // 不在哪一串积木上的问题：类一级的（继承、实现接口）记在那个类型名下；模块之间的记在“模块”名下。
        final t = doc.core.type(f.at.treeId);
        if (t == null && f.at.treeId.isNotEmpty) continue;
        final scope = t == null ? '模块' : '${t.kind.label}「${t.name}」';
        out.add(
          BlockIssue(
            message: '$scope：${f.problem}',
            isError: f.issue.level == LTypeLevel.error,
            isHint: f.issue.level == LTypeLevel.hint,
            rule: f.issue.code,
            problem: f.problem,
            fix: f.issue.rule.advice,
            group: scope,
            actions: extra(),
          ),
        );
        continue;
      }
      final block = f.at.path.isEmpty ? null : tree.blockAt(f.at.path);
      final scope = tree is BeFunction
          ? '积木「${tree.name}」'
          : tree is BeRoute
          ? '接口「${describeBeRoute(tree)}」'
          : tree is BeLibHat
          ? '库的帽子「${libName(tree.op) ?? '找不到'}」'
          : (coreScopeName(tree) ?? '');
      final spot = block == null ? '' : '${describeBeBlockPath(tree, f.at.path)}（${describeBeBlock(block, fnName)}）';
      final issue = f.issue;
      out.add(
        BlockIssue(
          message: '$scope$spot：${f.problem}',
          isError: issue.level == LTypeLevel.error,
          isHint: issue.level == LTypeLevel.hint,
          scriptId: tree.id,
          path: f.at.path,
          arg: f.at.arg,
          exprPath: f.at.arg == null ? null : f.at.exprPath,
          rule: issue.code,
          problem: f.problem,
          fix: issue.rule.advice,
          group: scope,
          spot: spot,
          actions: [for (final x in f.fixes) BlockIssueAction(x.fix.label, () => applyTypeFix(x.fix, x.slot)), ...extra()],
        ),
      );
    }
    return out;
  }

  /// 核心 2 的串（方法、“创建时”、“程序开始时”）在问题列表里叫什么；宿主的另一半（BeCoreHost）给。
  String? coreScopeName(LcBlockTree tree) => null;

  /// 做一次核心 2 的“一键修”（一条撤销记录）。改成了返回 true。
  bool applyCoreFix(BeCoreFix fix) {
    var done = false;
    edit(() => done = fix.apply(doc));
    return done;
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

  /// 现在升级的话会多出什么：几处要改的（错误）、几处提醒 / 警告、其中几处错误能一键修，外加逐条的清单（错误在前）。
  /// 已经是严格规矩返回 null。
  BeStrictPreview? previewStrict() {
    if (strictRules) return null;
    final copy = doc.clone()..rules = kLangRulesStrict;
    final check = beTypeCheck(copy);
    if (check == null) return const BeStrictPreview(0, 0, 0, []);
    String where(BeTypeFinding f) {
      final tree = beTreeById(copy, f.at.treeId);
      if (tree is BeFunction) return '积木「${tree.name}」';
      if (tree is BeRoute) return '接口「${describeBeRoute(tree)}」';
      if (tree != null) return coreScopeName(tree) ?? '';
      final t = copy.core.type(f.at.treeId);
      return t == null ? '模块' : '${t.kind.label}「${t.name}」';
    }

    final items = [for (final f in check.findings) (where: where(f), problem: f.problem, isError: f.issue.isError, fixable: f.fixes.isNotEmpty || f.extra.isNotEmpty)];
    final errors = [
      for (final i in items)
        if (i.isError) i,
    ];
    return BeStrictPreview(errors.length, items.length - errors.length, errors.where((i) => i.fixable).length, [
      ...errors,
      for (final i in items)
        if (!i.isError) i,
    ]);
  }

  /// 升级到严格规矩（一条撤销记录：刚升完后悔可以点撤销；存盘以后再打开就回不去了）。
  void upgradeToStrict() {
    if (strictRules) return;
    edit(() => doc.rules = kLangRulesStrict);
  }
}
