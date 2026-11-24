/// 逻辑校验：把积木里“导出后会出错 / 不起作用”的地方找出来，用人话说清楚是哪个处理、第几块、什么问题。
///
/// 只读不改。分两级：错误（这一块导出后不会按想的那样工作）和警告（能导出，但多半不是你想要的）。
/// 每种问题有一个稳定的规则编号和一句“怎么改”（logic_rules.dart）；类型、次数、除以 0 这些和后端共用的检查在 logic_validate_types.dart。
/// 有“错误”时 logic.js 不重新导出（保留上一次的，见 logic_gate.dart）；翻代码（logic_js.dart）本身不依赖校验结果。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart' show kRepeatLimit;
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_rules.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/logic_validate_types.dart';
import 'package:lopicode/lowcode/model.dart';

enum LcIssueLevel { error, warning }

/// 问题的种类。界面可以按它决定把红圈画在哪个参数上；测试按它断言。
abstract final class LcIssueCode {
  /// 变量本身有问题（名字不合规矩、重名、类型不认识）。
  static const String badVariable = 'badVariable';

  /// 用了没声明的变量。
  static const String unknownVar = 'unknownVar';

  /// 处理挂的控件、或积木 / 表达式里指的控件不存在。
  static const String nodeNotFound = 'nodeNotFound';

  /// click / input 处理没说挂在哪个控件上。
  static const String missingTarget = 'missingTarget';

  /// input 事件挂在不是输入框的控件上（警告）。
  static const String inputOnNonInput = 'inputOnNonInput';

  /// 不认识的事件。
  static const String unknownEvent = 'unknownEvent';

  /// 参数没填。
  static const String missingArg = 'missingArg';

  /// 参数填了但类型 / 取值不对。
  static const String badArg = 'badArg';

  /// 不认识的积木（警告：数据留着，导出时跳过）。
  static const String unknownOp = 'unknownOp';

  /// 不认识的表达式（警告）。
  static const String unknownExpr = 'unknownExpr';

  /// “变量加上”用在不是数字的变量上。
  static const String changeVarNotNumber = 'changeVarNotNumber';

  /// “输入的内容”用在不是 input 的处理里。
  static const String eventOutsideInput = 'eventOutsideInput';

  /// 积木或表达式嵌套太深。
  static const String tooDeep = 'tooDeep';

  /// 这种控件没有这个属性（警告：比如改容器的文字、读按钮的输入内容）。
  static const String propNotSupported = 'propNotSupported';

  /// 不能嵌积木的积木里放了积木（警告：导出时里面的被忽略）。
  static const String strayBody = 'strayBody';

  /// 值的类型和这一格要的对不上（数字格里填了不是数字的文字＝错误，其余＝警告）。
  static const String badType = 'badType';

  /// 事件下面一块积木都没有（警告）。
  static const String emptyScript = 'emptyScript';

  /// “重复”的次数直接填了负数（错误）、小数或超过上限（警告）。
  static const String badRepeat = 'badRepeat';

  /// 除以 / 对直接填的 0 取余（警告：运行时得 0）。
  static const String divByZero = 'divByZero';

  /// 网址没填或明显不是网址。
  static const String badUrl = 'badUrl';

  /// 同一个控件的同一个事件有两串（警告：两串都会执行）。
  static const String duplicateEvent = 'duplicateEvent';
}

class LcLogicIssue {
  const LcLogicIssue({
    required this.level,
    required this.code,
    required this.problem,
    required this.where,
    this.handlerId,
    this.path = const [],
    this.arg,
    this.exprPath,
    this.fix,
    this.scope = '',
    this.spot = '',
  });

  final LcIssueLevel level;

  /// 见 [LcIssueCode]。
  final String code;

  /// 问题本身：“变量 total 还没有声明”。
  final String problem;

  /// 在哪：“「点击「按钮“提交”」时」第 2 块（把 count 加上 1）”；变量的问题是“变量 xxx”。
  final String where;

  /// 哪个处理（变量的问题为 null）。
  final String? handlerId;

  /// 哪一块积木（处理本身的问题、变量的问题为空）。
  final LcBlockPath path;

  /// 哪个参数（能定位到时）；帽子上的问题是帽子的槽（target / method / path）。
  final String? arg;

  /// 参数里的哪个位置（和积木编辑器的槽位路径同一种写法：字段名或列表下标）；null＝定位不到具体哪一格。
  final List<Object>? exprPath;

  /// 这一条专门的“怎么改”；null＝用规则表里默认的那句（见 [advice]）。
  final String? fix;

  /// 属于哪一组：事件 / 接口的读法，或“变量”“服务设置”这类（问题列表按它分组）。
  final String scope;

  /// 组里的哪一处：“第 2 块（把 count 加上 1）”；帽子本身、变量的问题为空。
  final String spot;

  bool get isError => level == LcIssueLevel.error;

  /// 稳定的规则编号（见 logic_rules.dart），如 `G01`。
  String get rule => lcRuleId(code);

  /// 建议怎么改。
  String get advice => fix ?? kLcRules[code]?.fix ?? '';

  /// 完整的一句话：在哪 + 什么问题。
  String get message => '$where：$problem';

  @override
  String toString() => '${isError ? '错误' : '警告'} $message';
}

/// 检查整页的逻辑，返回所有问题（按变量、处理、积木的顺序）。没有问题返回空表。
List<LcLogicIssue> validateLogic(LcDocument doc) {
  final v = _Validator(doc);
  v.run();
  return v.issues;
}

/// 只要“错误”级的。
List<LcLogicIssue> logicErrors(LcDocument doc) => [
  for (final i in validateLogic(doc))
    if (i.isError) i,
];

class _Validator {
  _Validator(this.doc);

  final LcDocument doc;
  final List<LcLogicIssue> issues = [];

  // 正在检查的位置。
  LcHandler? _handler;
  LcBlockPath _path = const [];
  LcBlock? _block;

  /// 正在检查积木的哪个参数、参数里的哪个位置（表达式里面报的问题都记到这一格上，界面才知道圈哪里）。
  String? _top;
  List<Object> _xp = const [];

  late final LcValueChecker _values = LcValueChecker(
    exprSpec: (kind) => lcExprSpecs[kind],
    typeOf: (e) => exprType(e, (name) => doc.logic.variable(name)?.type),
    repeatLimit: kRepeatLimit,
    report: (level, code, problem, {required arg, required exprPath, fix}) => _add(level, code, problem, arg: arg, xp: exprPath, fix: fix),
  );

  void _add(LcIssueLevel level, String code, String problem, {String? arg, String? where, List<Object>? xp, String? fix}) {
    final h = _handler;
    final b = _block;
    final scope = where ?? (h == null ? '逻辑' : describeHandler(h, doc));
    final spot = where != null || h == null || b == null ? '' : '${describeBlockPath(h, _path)}（${describeBlock(b, doc)}）';
    final place = where ?? (h == null ? '逻辑' : '「$scope」$spot');
    final at = _top ?? arg;
    issues.add(
      LcLogicIssue(level: level, code: code, problem: problem, where: place, handlerId: h?.id, path: _path, arg: at, exprPath: at == null ? null : (xp ?? _xp), fix: fix, scope: scope, spot: spot),
    );
  }

  void _error(String code, String problem, {String? arg, String? where, String? fix}) => _add(LcIssueLevel.error, code, problem, arg: arg, where: where, fix: fix);
  void _warn(String code, String problem, {String? arg, String? where, String? fix}) => _add(LcIssueLevel.warning, code, problem, arg: arg, where: where, fix: fix);

  void run() {
    _variables();
    final seen = <String>{}; // “事件 控件”
    for (final h in doc.logic.handlers) {
      _handler = h;
      _path = const [];
      _block = null;
      final before = issues.length;
      _handlerHead(h);
      final headOk = issues.length == before;
      final target = h.event == 'load' ? '' : (h.target ?? '');
      if (LcHandler.events.contains(h.event) && (h.event == 'load' || doc.find(target) != null) && !seen.add('${h.event} $target')) {
        _warn(LcIssueCode.duplicateEvent, '前面已经有一串一样的事件了：两串都会执行（先前面那串，再这一串）', arg: h.event == 'load' ? null : 'target');
      }
      // 帽子自己还有问题（没选控件、控件没了…）时先不提“下面是空的”：一次说一件事。
      if (h.body.isEmpty && headOk) _warn(LcIssueCode.emptyScript, '下面还没有积木，触发了也什么都不会做');
      _blocks(h.body, const [], false);
    }
    _handler = null;
  }

  void _variables() {
    final seen = <String>{};
    for (final v in doc.logic.variables) {
      final where = '变量 ${v.name.isEmpty ? '（没有名字）' : v.name}';
      if (!LcVariable.namePattern.hasMatch(v.name)) {
        _error(LcIssueCode.badVariable, '名字只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符', where: where);
      } else if (!seen.add(v.name)) {
        _error(LcIssueCode.badVariable, '有两个变量叫这个名字', where: where);
      }
      if (!LcVariable.types.contains(v.type)) {
        _error(LcIssueCode.badVariable, '不认识的类型 ${v.type}（只能是文字、数字、是 / 否）', where: where);
      }
    }
  }

  void _handlerHead(LcHandler h) {
    if (!LcHandler.events.contains(h.event)) {
      _error(LcIssueCode.unknownEvent, '不认识的事件 ${h.event}');
      return;
    }
    if (h.event == 'load') return;
    final target = h.target;
    if (target == null || target.isEmpty) {
      _error(LcIssueCode.missingTarget, '还没选是哪个控件触发的', arg: 'target');
      return;
    }
    final node = doc.find(target);
    if (node == null) {
      _error(LcIssueCode.nodeNotFound, '触发它的控件已经不在页面里了', arg: 'target', fix: '点帽子上标红的那一格，重新选一个控件；不需要这一串就删掉它。');
    } else if (h.event == 'input' && node.type != 'input') {
      _warn(LcIssueCode.inputOnNonInput, '“输入内容变化时”只有输入框会触发，${describeNode(doc, target)}不是输入框', arg: 'target');
    }
  }

  void _blocks(List<LcBlock> list, LcBlockPath parent, bool inElse) {
    for (var i = 0; i < list.length; i++) {
      final path = [...parent, lcStep(i, inElse: inElse)];
      _path = path;
      _block = list[i];
      // 第几步就是第几层（从 0 数）；超过的存盘再读会被丢掉，翻代码也不翻。
      if (path.length - 1 > LcBlock.maxDepth) {
        _error(LcIssueCode.tooDeep, '积木套得太深了（最多 ${LcBlock.maxDepth + 1} 层），这一块和它里面的不会生效');
        continue;
      }
      _oneBlock(list[i]);
      _blocks(list[i].body, path, false);
      _blocks(list[i].orElse, path, true);
    }
    _path = parent;
    _block = null;
  }

  void _oneBlock(LcBlock b) {
    final spec = lcBlockSpecs[b.op];
    if (spec == null) {
      _warn(LcIssueCode.unknownOp, '不认识的积木 ${b.op}，导出时会跳过它（数据会留着）');
      return;
    }
    for (final a in spec.args) {
      _top = a.name;
      _arg(a, b.args[a.name], b.args.containsKey(a.name));
    }
    _top = null;
    _xp = const [];
    _values.block(b, spec);
    if (b.op == 'navigate' || b.op == 'fetch') _url(b);
    if (!spec.hasBody && b.body.isNotEmpty) {
      _warn(LcIssueCode.strayBody, '“${spec.label}”里面不能放积木，里面的 ${b.body.length} 块导出时会被忽略');
    }
    if (!spec.hasElse && b.orElse.isNotEmpty) {
      _warn(LcIssueCode.strayBody, '“${spec.label}”没有“否则”，那里的 ${b.orElse.length} 块导出时会被忽略');
    }
    final name = b.args['name'];
    if (b.op == 'changeVar' && name is String) {
      final v = doc.logic.variable(name);
      if (v != null && v.type != 'number') {
        _error(LcIssueCode.changeVarNotNumber, '变量 $name 是${describeVarType(v.type)}，不是数字，不能“加上”；要改它请用“设置变量”', arg: 'name');
      }
    }
    if (b.op == 'setProp') _propFit(b.args['node'], b.args['prop'], write: true);
  }

  /// 直接填的网址：跳转的空着 / 不像网址＝警告；请求的空着＝错误（一定请求不到），不像网址＝警告。
  void _url(LcBlock b) {
    final url = b.args['url'];
    if (exprKind(url) != 'text') return;
    final why = lcUrlProblem(exprString(url, 'v') ?? '', httpOnly: false);
    if (why == null) return;
    final fetch = b.op == 'fetch';
    final problem = switch (why) {
      'empty' => fetch ? '请求的网址还没填，这一块请求不到任何东西' : '跳转的网址还没填，点了会原地刷新',
      'partial' => '网址只填了开头，还没填完',
      _ => '这个网址里有空格或格式不对，多半打不开',
    };
    _add(fetch && why == 'empty' ? LcIssueLevel.error : LcIssueLevel.warning, LcIssueCode.badUrl, problem, arg: 'url', xp: const []);
  }

  /// 检查一个参数（积木的或表达式的）。`present`＝JSON 里有没有这个字段；`xp`＝它在积木参数里的位置。
  void _arg(LcArgSpec a, Object? value, bool present, [int depth = 0, List<Object> xp = const []]) {
    final was = _xp;
    _xp = xp;
    _argAt(a, value, present, depth, xp);
    _xp = was;
  }

  void _argAt(LcArgSpec a, Object? value, bool present, int depth, List<Object> xp) {
    final missing = !present || value == null;
    switch (a.kind) {
      case LcArgKind.expr:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (!isExpr(value)) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一个值', arg: a.name);
        } else {
          _expr(value, a.name, depth);
        }
      case LcArgKind.exprList:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (value is! List) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一串值', arg: a.name);
        } else {
          for (var i = 0; i < value.length; i++) {
            final item = value[i];
            _xp = [...xp, i];
            if (isExpr(item)) {
              _expr(item, a.name, depth);
            } else {
              _error(LcIssueCode.badArg, '“${a.label}”里有一项不是值', arg: a.name);
            }
          }
        }
      case LcArgKind.variable:
        if (missing || value == '') {
          if (!a.optional) _error(LcIssueCode.missingArg, '还没选变量', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是变量的名字', arg: a.name);
        } else if (doc.logic.variable(value) == null) {
          _error(LcIssueCode.unknownVar, '变量 $value 还没有声明（先到“变量”里加一个）', arg: a.name);
        }
      case LcArgKind.node:
        if (missing || value == '') {
          _error(LcIssueCode.missingArg, '还没选控件', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是控件的 id', arg: a.name);
        } else if (doc.find(value) == null) {
          _error(LcIssueCode.nodeNotFound, '它指的控件已经不在页面里了', arg: a.name);
        }
      case LcArgKind.collection:
        _error(LcIssueCode.badArg, '页面逻辑里没有“数据集合”', arg: a.name);
      case LcArgKind.choice:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没选', arg: a.name);
        } else if (value is! String || !a.choices.contains(value)) {
          _error(LcIssueCode.badArg, '“${a.label}”只能是 ${a.choices.join(' / ')}', arg: a.name);
        }
      case LcArgKind.literalText:
        if (value is! String) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一段文字', arg: a.name);
      case LcArgKind.literalNumber:
        if (value is! num || !value.isFinite) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一个数字', arg: a.name);
      case LcArgKind.literalBool:
        if (value is! bool) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是“是”或“否”', arg: a.name);
    }
  }

  /// `arg` 是这个表达式最终属于积木的哪个参数（报问题时定位用）。
  void _expr(Object? expr, String arg, int depth) {
    if (depth >= kMaxExprDepth) {
      _error(LcIssueCode.tooDeep, '值套得太深了（最多 $kMaxExprDepth 层）', arg: arg);
      return;
    }
    final kind = exprKind(expr);
    final spec = lcExprSpecs[kind];
    if (kind == null || spec == null || expr is! Map) {
      _warn(LcIssueCode.unknownExpr, '不认识的值 ${kind ?? ''}，导出时会当成空的', arg: arg);
      return;
    }
    if (kind == 'event' && _handler?.event != 'input') {
      _error(LcIssueCode.eventOutsideInput, '“输入的内容”只能用在“输入内容变化时”的处理里', arg: arg);
    }
    final base = _xp;
    for (final a in spec.args) {
      _arg(a, expr[a.name], expr.containsKey(a.name), depth + 1, [...base, a.name]);
    }
    if (kind == 'prop') _propFit(expr['node'], expr['prop'], write: false, arg: arg);
  }

  /// 这种控件有没有这个属性。控件不存在、属性不认识的情况别处已经报过，这里不重复。
  void _propFit(Object? nodeId, Object? prop, {required bool write, String? arg}) {
    if (nodeId is! String || prop is! String) return;
    final node = doc.find(nodeId);
    if (node == null || !(write ? kWritableProps : kReadableProps).contains(prop)) return;
    // 读“文字”对所有控件都行（读到的是里面所有的字）；改“文字”只有文本和按钮行，别的会把里面的控件冲掉。
    if (!write && prop == 'text') return;
    if (propFitsNode(prop, node.type)) return;
    final who = describeNode(doc, nodeId);
    final what = describeProp(prop);
    _warn(LcIssueCode.propNotSupported, write ? '$who没有“$what”可以改，这一块导出时会跳过' : '$who没有“$what”，读到的会是空的', arg: arg ?? 'prop');
  }
}
