/// 后端积木的校验：把“生成后会出错 / 不起作用”的地方找出来，用人话说清楚是哪个接口、第几块、什么问题。
/// 只读不改。问题的结构沿用前端的 [LcLogicIssue]（`handlerId` 这里放接口的 id），这样积木编辑器只认一种问题。
/// 分两级：错误（这一块不会按想的那样工作）和警告 / 提示（能跑，但多半不是你想要的）。
/// 每种问题有稳定的规则编号和一句“怎么改”（lib/lowcode/logic_rules.dart）；类型、次数、除以 0 这些和页面逻辑共用的检查在
/// lib/lowcode/logic_validate_types.dart。有“错误”时不重新生成代码（backend_project.dart 拦，上一次生成的文件原样留着）。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart' show kBeRepeatLimit;
import 'package:lopicode/backend/backend_issue_codes.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_to_service.dart' show beUsedLibs;
import 'package:lopicode/backend/backend_validate_func.dart';
import 'package:lopicode/backend/backend_validate_lang.dart';
import 'package:lopicode/backend/backend_validate_types.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_rules.dart';
import 'package:lopicode/lowcode/logic_validate.dart';
import 'package:lopicode/lowcode/logic_validate_types.dart';

export 'package:lopicode/backend/backend_issue_codes.dart';
export 'package:lopicode/backend/backend_validate_func.dart' show BeFuncIssueCode;
export 'package:lopicode/backend/backend_validate_lang.dart' show BeLangIssueCode, beExprType;
export 'package:lopicode/lowcode/logic_validate.dart' show LcIssueCode, LcIssueLevel, LcLogicIssue;

/// 检查整份后端文档，返回所有问题（按 服务设置、变量、集合、接口、积木 的顺序）。没有问题返回空表。
/// `languages`＝现在有生成器的语言 id；给了就检查文档选的语言在不在里面。`table`＝调用方手上已经有的“我的积木”一览（省得再算一遍）。
List<LcLogicIssue> validateBackend(BeDocument doc, {Iterable<String>? languages, BeFuncTable? table}) {
  final v = _Validator(doc, languages?.toSet(), table ?? BeFuncTable(doc));
  v.run();
  return v.issues;
}

/// 只要“错误”级的。
List<LcLogicIssue> backendErrors(BeDocument doc) => [
  for (final i in validateBackend(doc))
    if (i.isError) i,
];

const Set<String> _respondOps = {'respondJson', 'respondText'};

bool _alwaysResponds(List<LcBlock> list) => beAlwaysResponds(list);

bool _samePath(LcBlockPath a, LcBlockPath b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameXp(List<Object>? a, List<Object> b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _hasRespond(BeRoute r) {
  var found = false;
  r.visitBlocks((b, _) => found = found || _respondOps.contains(b.op));
  return found;
}

class _Validator {
  _Validator(this.doc, this.languages, this.table);

  final BeDocument doc;
  final BeFuncTable table;
  final Set<String>? languages;
  final List<LcLogicIssue> issues = [];

  // 正在检查的位置。
  BeRoute? _route;
  Set<String> _params = const {};

  /// 正在检查的是哪个函数的定义（“我的积木”）；null＝在接口里。[_lambdas]＝现在套在几层匿名函数的口里。
  BeFunction? _fn;
  int _lambdas = 0;
  BeMethod? _core;
  BeLibHat? _hat;
  bool get _inFn => _fn != null || _core != null || _hat != null;
  LcBlockTree? get _tree => _fn ?? _core ?? _hat ?? _route;
  Map<String, bool> _withGlobals(Map<String, bool> m) => {...m, for (final g in doc.core.globals) g.name: g.isConst, for (final p in _core?.params ?? const <BeParam>[]) p.name: false};
  String? _fnName(String id) => doc.function(id)?.name;

  /// 这一串里出现过的参数名（定义的 + 匿名函数的）。
  Set<String> _known = const {};

  /// 这个接口里新积木新建的名字（新建变量 / 常量、循环变量）→ 是不是常量。
  Map<String, bool> _locals = const {};
  LcBlockPath _path = const [];
  LcBlock? _block;

  /// 正在检查积木的哪个参数、参数里的哪个位置（表达式里面报的问题都记到这一格上，界面才知道圈哪里）。
  String? _top;
  List<Object> _xp = const [];

  late final LcValueChecker _values = LcValueChecker(
    exprSpec: table.exprSpec,
    typeOf: (e) => table.callOf(exprKind(e)) != null ? (table.isBool(e) ? LcType.boolean : LcType.any) : beExprType(e),
    repeatLimit: kBeRepeatLimit,
    report: (level, code, problem, {required arg, required exprPath, fix}) => _add(level, code, problem, arg: arg, xp: exprPath, fix: fix),
  );

  void _add(LcIssueLevel level, String code, String problem, {String? arg, String? where, List<Object>? xp, String? fix}) {
    final r = _tree;
    final b = _block;
    final scope =
        where ??
        (r == null
            ? '后端'
            : (r is BeFunction
                  ? '积木「${r.name}」'
                  : (r is BeMethod ? doc.core.labelOf(r) : (r is BeLibHat ? '库的帽子「${table.libs.of(r.op)?.block.look.name ?? '找不到'}」' : '接口「${describeBeRoute(r as BeRoute)}」'))));
    final spot = where != null || r == null || b == null ? '' : '${describeBeBlockPath(r, _path)}（${describeBeBlock(b, _fnName)}）';
    final at = _top ?? arg;
    issues.add(
      LcLogicIssue(
        level: level,
        code: code,
        problem: problem,
        where: '$scope$spot',
        handlerId: r?.id,
        path: _path,
        arg: at,
        exprPath: at == null ? null : (xp ?? _xp),
        fix: fix,
        scope: scope,
        spot: spot,
      ),
    );
  }

  void _error(String code, String problem, {String? arg, String? where, String? fix}) => _add(LcIssueLevel.error, code, problem, arg: arg, where: where, fix: fix);
  void _warn(String code, String problem, {String? arg, String? where, String? fix}) => _add(LcIssueLevel.warning, code, problem, arg: arg, where: where, fix: fix);

  void run() {
    _service();
    _variables();
    _collections();
    final seen = <String, BeRoute>{}; // “方式 路径形状” → 第一个这样的接口
    final used = <String>{}; // 各个接口用到了哪些函数（“没人用的积木”要看全部接口）
    for (var i = 0; i < doc.routes.length; i++) {
      final r = doc.routes[i];
      _route = r;
      _path = const [];
      _block = null;
      _routeHead(r, i, seen);
      _locals = beLocalNames(r.body, beNamePattern);
      _known = beTreeParamNames(r);
      _blocks(r.body, const [], false);
      _lang(r, beLangFindings(doc, r, table: table, used: used));
      // 严格规矩（规矩版本 2）的文档再过一遍类型检查；版本 1 的文档这里是空表。
      _lang(r, beTypeFindings(doc, r, table: table));
      _path = const [];
      _block = null;
      // 一块“返回”都没有的接口是有意回 204（比如删除），不提示；有“返回”但不是每种走法都碰得到的，多半是漏了。
      if (r.body.isEmpty) {
        _warn(BeIssueCode.noRespond, '还没有积木，访问它会得到 204 空响应');
      } else if (!_alwaysResponds(r.body) && _hasRespond(r)) {
        _warn(BeIssueCode.noRespond, '有的走法没有碰到“返回”积木，那时会回 204 空响应');
      }
    }
    _route = null;
    for (final f in doc.functions) {
      if (beFunctionUsedInCore(doc, f.id)) used.add(f.ident);
    }
    _functions(used);
    for (final m in doc.core.trees) {
      _core = m; // 核心 2 的串（方法、“创建时”、“程序开始时”）：这里只看格子填没填好，类型由类型检查说
      _locals = _withGlobals(beLocalNames(m.body, beNamePattern));
      _known = beTreeParamNames(m);
      _blocks(m.body, const [], false);
    }
    _core = null;
    for (final h in doc.hats) {
      _hat = h; // 库的帽子积木开头的串
      _path = const [];
      _block = null;
      if (table.libs.of(h.op) == null) _error(BeIssueCode.badLibrary, _libGone(h.op));
      _locals = _withGlobals(beLocalNames(h.body, beNamePattern));
      _known = beTreeParamNames(h);
      _blocks(h.body, const [], false);
    }
    _hat = null;
    // 库：用上的库在不在、读不读得懂；这份文档自己是库的话，它出不出得了库文件。
    final libProblems = <String>[];
    if (doc.usesLibs) beUsedLibs(doc, libProblems);
    if (doc.library != null) libProblems.addAll(beLibFiles(doc).problems);
    for (final p in libProblems.toSet()) {
      _error(BeIssueCode.badLibrary, p, where: '库');
    }
  }

  /// “我的积木”的定义：外观、参数表、函数体里的每一块，再加语言核心的检查器对这一批函数说的。
  void _functions(Set<String> used) {
    _params = const {};
    for (final f in doc.functions) {
      _fn = f;
      _path = const [];
      _block = null;
      for (final p in beFuncHeadProblems(f, table)) {
        _add(p.isError ? LcIssueLevel.error : LcIssueLevel.warning, p.code, p.problem, arg: p.arg, xp: const [], fix: p.fix);
      }
      _locals = _withGlobals(beLocalNames(f.body, beNamePattern));
      _known = beTreeParamNames(f);
      _blocks(f.body, const [], false);
      _lang(f, beFuncFindings(table, f, used));
      _lang(f, beFuncTypeFindings(doc, table, f));
    }
    _fn = null;
  }

  void _service() {
    if (doc.port < 1 || doc.port > 65535) _error(BeIssueCode.badPort, '端口要在 1 到 65535 之间', where: '服务设置', arg: 'port');
    final langs = languages;
    if (langs != null && !langs.contains(doc.language)) {
      _warn(BeIssueCode.noGenerator, '选的语言 ${doc.language} 现在还不能生成代码', where: '服务设置', arg: 'language');
    }
  }

  void _variables() {
    final seen = <String>{};
    for (final v in doc.variables) {
      final where = '变量 ${v.name.isEmpty ? '（没有名字）' : v.name}';
      if (!beNamePattern.hasMatch(v.name)) {
        _error(LcIssueCode.badVariable, '名字只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符', where: where);
      } else if (!seen.add(v.name)) {
        _error(LcIssueCode.badVariable, '有两个变量叫这个名字', where: where);
      }
      if (!LcVariable.types.contains(v.type)) {
        _error(LcIssueCode.badVariable, '不认识的类型 ${v.type}（只能是文字、数字、是 / 否）', where: where);
      }
    }
  }

  void _collections() {
    final seen = <String>{};
    for (final c in doc.collections) {
      final where = '集合 ${c.name.isEmpty ? '（没有名字）' : c.name}';
      if (!beNamePattern.hasMatch(c.name)) {
        _error(BeIssueCode.badCollection, '名字只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符', where: where);
      } else if (!seen.add(c.name)) {
        _error(BeIssueCode.badCollection, '有两个集合叫这个名字', where: where);
      }
    }
  }

  void _routeHead(BeRoute r, int index, Map<String, BeRoute> seen) {
    _params = const {};
    if (!kBeMethods.contains(r.method)) {
      _error(BeIssueCode.badMethod, '请求方式只能是 ${kBeMethods.join(' / ')}', arg: 'method');
    }
    final segs = parseBePath(r.path);
    if (segs == null) {
      _error(BeIssueCode.badPath, '路径格式不对：要以 / 开头，每段只能用英文字母、数字和 _ . ~ -，路径参数写成 :名字，末尾不带 /', arg: 'path');
      return;
    }
    final params = <String>{};
    for (final s in segs) {
      if (s.isParam && !params.add(s.text)) {
        _error(BeIssueCode.badPath, '路径里有两个参数都叫 ${s.text}', arg: 'path');
      }
    }
    _params = params;
    final key = '${r.method} ${bePathShape(r.path)}';
    final first = seen[key];
    if (first != null) {
      _error(BeIssueCode.duplicateRoute, '和前面的接口「${describeBeRoute(first)}」是同一个地址，请求只会进前面那个', arg: 'path');
      return;
    }
    seen[key] = r;
    // 被前面的接口挡住：同一种方式、段数一样，前面那个每一段要么是参数、要么和这个的文字一样。
    for (final earlier in doc.routes.take(index)) {
      if (earlier.method != r.method) continue;
      final other = parseBePath(earlier.path);
      if (other == null || other.length != segs.length) continue;
      var covers = true;
      for (var i = 0; i < segs.length && covers; i++) {
        covers = other[i].isParam || (!segs[i].isParam && other[i].text == segs[i].text);
      }
      if (covers) {
        _warn(BeIssueCode.shadowedRoute, '排在前面的接口「${describeBeRoute(earlier)}」也能匹配这个地址，请求会先进它；把这个接口挪到它前面', arg: 'path');
        break;
      }
    }
  }

  /// 语言核心的检查器报的（只有用到新积木的接口才有）；和上面已经报过的同一条不重复报。
  void _lang(LcBlockTree r, List<BeLangFinding> findings) {
    for (final f in findings) {
      final rule = lcRuleId(f.code);
      final xp = f.exprPath;
      // 带着“参数里的哪个位置”的（类型检查的问题）：位置也一样才算同一条。
      bool sameSpot(LcLogicIssue i) => xp == null || _sameXp(i.exprPath, xp);
      if (issues.any((i) => i.handlerId == r.id && i.rule == rule && _samePath(i.path, f.path) && (f.arg == null || i.arg == f.arg) && sameSpot(i))) continue;
      // 同一格上类型检查已经说了“要什么、放进来的是什么”，老的那条“类型对不上”（G10）就不重复了。
      if (f.code.startsWith('T')) issues.removeWhere((i) => i.handlerId == r.id && i.rule == 'G10' && _samePath(i.path, f.path) && i.arg == f.arg && sameSpot(i));
      _path = f.path;
      _block = r.blockAt(f.path);
      _add(f.isError ? LcIssueLevel.error : LcIssueLevel.warning, f.code, f.problem, arg: f.arg, xp: xp ?? const [], fix: f.fix);
    }
    _path = const [];
    _block = null;
  }

  void _blocks(List<LcBlock> list, LcBlockPath parent, bool inElse, {int arm = -1}) {
    var responded = false;
    for (var i = 0; i < list.length; i++) {
      final path = [...parent, lcStep(i, inElse: inElse, arm: arm)];
      _path = path;
      _block = list[i];
      // 第几步就是第几层（从 0 数）；超过的存盘再读会被丢掉，翻代码也不翻。
      if (path.length - 1 > LcBlock.maxDepth) {
        _error(LcIssueCode.tooDeep, '积木套得太深了（最多 ${LcBlock.maxDepth + 1} 层），这一块和它里面的不会生效');
        continue;
      }
      if (responded) {
        _warn(BeIssueCode.unreachable, '前面已经“返回”了，从这一块起后面的 ${list.length - i} 块都不会执行');
        responded = false; // 只在第一块上提示一次
      }
      _oneBlock(list[i]);
      // 这块积木上“带口的值”（匿名函数）口里的积木：路径是序号，每次现数。
      final mouths = list[i].exprMouths;
      _lambdas++;
      for (var k = 0; k < mouths.length; k++) {
        _blocks(mouths[k], path, false, arm: lcExprMouthArm(k));
      }
      _lambdas--;
      _blocks(list[i].body, path, false);
      for (var k = 0; k < list[i].arms.length; k++) {
        _blocks(list[i].arms[k].body, path, false, arm: k);
      }
      _blocks(list[i].orElse, path, true);
      if (i < list.length - 1 && _alwaysResponds([list[i]])) responded = true;
    }
    _path = parent;
    _block = null;
  }

  String _libGone(String op) {
    final ref = beLibOpOf(op)!;
    final l = doc.use(ref.lib) == null ? null : doc.lib(ref.lib);
    return l == null ? '这块积木是库「${ref.lib}」的，可是这份文档没有用上这个库（或者库不在项目里）' : '库「${l.name}」里已经没有这块积木了（库改过了？）';
  }

  void _oneBlock(LcBlock b) {
    final spec = table.blockSpec(b.op);
    if (spec == null && beCallId(b.op) != null) {
      _error(BeFuncIssueCode.unknownFunction, '这块自定义积木的定义已经不在了', fix: '删掉这一块；想留着就到“我的积木”里重新做一块，再换上。');
      return;
    }
    if (spec == null && beLibOpOf(b.op) != null) {
      _error(BeIssueCode.badLibrary, _libGone(b.op), fix: '到“积木库”里把这个库用上（或者重新导入）；不要了就删掉这一块。');
      return;
    }
    if (spec == null) {
      _warn(LcIssueCode.unknownOp, '不认识的积木 ${b.op}，生成代码时会跳过它（数据会留着）');
      return;
    }
    for (final a in spec.args) {
      _top = a.name;
      if (!b.args.containsKey(a.name) && table.argFallsBack(b.op, a.name)) continue; // 调用时没给、参数有默认值：用默认值
      _arg(a, b.args[a.name], b.args.containsKey(a.name), ownerKind: null);
    }
    _arms(b, spec);
    _top = null;
    _xp = const [];
    _values.block(b, spec);
    _newNames(b);
    if (b.op == 'fetch') _url(b);
    // 库文档里的函数可以公开成拿着“这次请求”的积木，能不能回响应由库的类型检查说。
    final misplaced = doc.library != null && b.op != 'fetch' ? null : beHostOnlyProblem(b.op, inFunction: _inFn, inLambda: _lambdas > 0);
    if (misplaced != null) _error(BeFuncIssueCode.hostInFunction, misplaced.$1, fix: misplaced.$2);
    if (!spec.hasBody && b.body.isNotEmpty) {
      _warn(LcIssueCode.strayBody, '“${spec.label}”里面不能放积木，里面的 ${b.body.length} 块生成代码时会被忽略');
    }
    if (!spec.hasElse && b.orElse.isNotEmpty) {
      _warn(LcIssueCode.strayBody, '“${spec.label}”没有“否则”，那里的 ${b.orElse.length} 块生成代码时会被忽略');
    }
    final name = b.args['name'];
    if (b.op == 'changeVar' && name is String) {
      final v = doc.variable(name);
      if (v != null && v.type != 'number') {
        _warn(LcIssueCode.changeVarNotNumber, '变量 $name 声明的是${_typeName(v.type)}，不是数字；“加上”会先把它当数字（转不了当 0）', arg: 'name');
      }
    }
    if (_respondOps.contains(b.op)) {
      final status = b.args['status'];
      final n = exprKind(status) == 'num' ? exprNum(status, 'v') : null;
      if (n != null && (n != n.roundToDouble() || n < 200 || n > 599)) {
        _warn(BeIssueCode.badStatus, '状态码要是 200 到 599 之间的整数，现在这个运行时会当成 200', arg: 'status');
      }
    }
  }

  /// 多口积木中间那些段（否则如果 / 是…时）的参数；段参数的名字是 `@<第几段>:<名字>`。
  void _arms(LcBlock b, LcBlockSpec spec) {
    _top = null;
    final arms = spec.arms;
    if (arms == null) {
      if (b.arms.isNotEmpty) _warn(LcIssueCode.strayBody, '“${spec.label}”不能加段，多出来的 ${b.arms.length} 段生成代码时会被忽略');
      return;
    }
    if (b.arms.length < arms.min) {
      _error(LcIssueCode.missingArg, '“${spec.label}”至少要有 ${arms.min} 段“${arms.label}”', fix: '点这块积木上的“＋”，加一段“${arms.label}”。');
    }
    for (var k = 0; k < b.arms.length; k++) {
      for (final a in arms.args) {
        final value = b.arms[k].args[a.name];
        _top = lcArmArg(k, a.name);
        _arg(a, value, b.arms[k].args.containsKey(a.name), ownerKind: null);
        _xp = const [];
        _values.arg(a, value, lcArmArg(k, a.name));
      }
    }
  }

  /// “新建一个名字”的格子：名字要合规矩，不能和“变量”里声明的重名（同一个接口里重复新建由语言核心的检查器报）。
  void _newNames(LcBlock b) {
    for (final n in kBeNewNameArgs[b.op] ?? const <String>[]) {
      final name = b.args[n];
      if (name is! String || name.isEmpty) continue;
      if (!beNamePattern.hasMatch(name)) {
        _error(LcIssueCode.badArg, '名字只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符', arg: n);
      } else if (doc.variable(name) != null) {
        _error(BeLangIssueCode.duplicateName, '“变量”里已经声明了一个叫 $name 的，这里不能再新建同名的', arg: n);
      }
    }
  }

  /// 直接填的网址：空着＝错误（一定请求不到）；没填完、不是 http / https 开头的完整网址＝警告（运行时不会去请求，结果是空）。
  void _url(LcBlock b) {
    final url = b.args['url'];
    if (exprKind(url) != 'text') return;
    final why = lcUrlProblem(exprString(url, 'v') ?? '', httpOnly: true);
    if (why == null) return;
    final problem = switch (why) {
      'empty' => '请求的网址还没填，这一块请求不到任何东西',
      'partial' => '网址只填了开头，还没填完；现在这样不会去请求，结果是空的',
      _ => '只能请求 http:// 或 https:// 开头的完整网址；现在这样不会去请求，结果是空的',
    };
    _add(why == 'empty' ? LcIssueLevel.error : LcIssueLevel.warning, LcIssueCode.badUrl, problem, arg: 'url', xp: const []);
  }

  static String _typeName(String type) => switch (type) {
    'number' => '数字',
    'bool' => '是 / 否',
    'text' => '文字',
    _ => type,
  };

  /// 检查一个参数（积木的或表达式的）。`present`＝JSON 里有没有这个字段；`ownerKind`＝它属于哪种表达式（积木的参数为 null）。
  /// `xp`＝它在积木参数里的位置。
  void _arg(LcArgSpec a, Object? value, bool present, {required String? ownerKind, int depth = 0, List<Object> xp = const []}) {
    final was = _xp;
    _xp = xp;
    _argAt(a, value, present, ownerKind, depth, xp);
    _xp = was;
  }

  void _argAt(LcArgSpec a, Object? value, bool present, String? ownerKind, int depth, List<Object> xp) {
    final missing = !present || value == null;
    switch (a.kind) {
      case LcArgKind.expr:
        if (missing) {
          if (!a.optional) _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (!isExpr(value)) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一个值', arg: a.name);
        } else {
          _expr(value, a.name, depth, inObj: false);
        }
      case LcArgKind.exprList:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        } else if (value is! List) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是一串值', arg: a.name);
        } else {
          final inObj = ownerKind == 'obj' || (a.name == 'fields' && beIsCoreExpr(ownerKind));
          final keys = <String>{};
          for (var i = 0; i < value.length; i++) {
            final item = value[i];
            _xp = [...xp, i];
            if (!isExpr(item)) {
              _error(LcIssueCode.badArg, '“${a.label}”里有一项不是值', arg: a.name);
              continue;
            }
            if (inObj && exprKind(item) != 'pair') {
              _error(BeIssueCode.badPair, '“对象”里只能放“名字: 值”这样的字段', arg: a.name);
              continue;
            }
            _expr(item, a.name, depth, inObj: inObj);
            final key = exprString(item, 'key');
            if (inObj && key != null && key.isNotEmpty && !keys.add(key)) {
              _warn(BeIssueCode.badPair, '对象里有两个字段都叫 $key，后面的会盖掉前面的', arg: a.name);
            }
          }
        }
      case LcArgKind.variable:
        if (missing || value == '') {
          if (!a.optional) _error(LcIssueCode.missingArg, '还没选变量', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是变量的名字', arg: a.name);
        } else if (_inFn && !_locals.containsKey(value)) {
          _error(LcIssueCode.unknownVar, doc.variable(value) == null ? '变量 $value 在这块积木里还没有新建' : '变量 $value 是接口里用的，自定义积木里看不见', arg: a.name, fix: '在这块积木里用“新建变量”，或者给它加一个参数、调用时把值传进来。');
        } else if (doc.variable(value) == null && !_locals.containsKey(value)) {
          _error(LcIssueCode.unknownVar, '变量 $value 还没有声明（先到“变量”里加一个）', arg: a.name);
        }
      case LcArgKind.collection:
        if (missing || value == '') {
          _error(LcIssueCode.missingArg, '还没选集合', arg: a.name);
        } else if (value is! String) {
          _error(LcIssueCode.badArg, '“${a.label}”应该是集合的名字', arg: a.name);
        } else if (doc.collection(value) == null) {
          _error(BeIssueCode.unknownCollection, '集合 $value 还没有（先到“数据集合”里加一个）', arg: a.name);
        }
      case LcArgKind.node:
        _error(LcIssueCode.badArg, '后端积木里没有“控件”', arg: a.name);
      case LcArgKind.choice:
        if (missing) {
          _error(LcIssueCode.missingArg, '“${a.label}”还没选', arg: a.name);
        } else if (value is! String || (!a.choices.contains(value) && !(a.choices.isEmpty && value.isNotEmpty && langRulesStrict(doc.rules)))) {
          _error(LcIssueCode.badArg, a.choices.isEmpty ? '“${a.label}”还没选' : '“${a.label}”只能是 ${a.choices.join(' / ')}', arg: a.name);
        }
      case LcArgKind.literalText:
        if (a.optional && (missing || value == '')) {
          // 可填可不填的名字（“对每一项”的序号、备注）空着不报。
        } else if (value is! String) {
          _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一段文字', arg: a.name);
        } else if (value.isEmpty && ownerKind != 'text') {
          // 文字字面量可以是空的；名字、字段名空着多半是忘了填。
          _error(LcIssueCode.missingArg, '“${a.label}”还没填', arg: a.name);
        }
      case LcArgKind.literalNumber:
        if (value is! num || !value.isFinite) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是一个数字', arg: a.name);
      case LcArgKind.literalBool:
        if (value is! bool) _error(missing ? LcIssueCode.missingArg : LcIssueCode.badArg, '“${a.label}”应该是“是”或“否”', arg: a.name);
    }
  }

  /// `arg` 是这个表达式最终属于积木的哪个参数（报问题时定位用）。`inObj`＝它是不是直接放在“对象”的字段里。
  void _expr(Object? expr, String arg, int depth, {required bool inObj}) {
    if (depth >= kMaxExprDepth) {
      _error(LcIssueCode.tooDeep, '值套得太深了（最多 $kMaxExprDepth 层）', arg: arg);
      return;
    }
    final kind = exprKind(expr);
    final spec = table.exprSpec(kind);
    if (spec == null && beCallId(kind) != null) {
      _error(BeFuncIssueCode.unknownFunction, '这里用的自定义积木，定义已经不在了；生成代码时会当成空的', arg: arg, fix: '长按这个值换成别的；想留着就到“我的积木”里重新做一块，再换上。');
      return;
    }
    if (spec == null && beLibOpOf(kind) != null) {
      _error(BeIssueCode.badLibrary, _libGone(kind!), arg: arg, fix: '到“积木库”里把这个库用上（或者重新导入）；不要了就长按这个值换成别的。');
      return;
    }
    if (kind == null || spec == null || expr is! Map) {
      _warn(LcIssueCode.unknownExpr, '不认识的值 ${kind ?? ''}，生成代码时会当成空的', arg: arg);
      return;
    }
    final base = _xp;
    final noValue = beCallNoValueProblem(table, kind);
    if (noValue != null) _warn(BeFuncIssueCode.badReturn, noValue, arg: arg, fix: '在它的定义里加一块“返回 (值)”；或者把它单独当一句用。');
    if (kind == 'pair' && !inObj) {
      _error(BeIssueCode.badPair, '“一个字段”只能放在“对象”里', arg: arg);
    }
    for (final a in spec.args) {
      if (!expr.containsKey(a.name) && table.argFallsBack(kind, a.name)) continue;
      _arg(a, expr[a.name], expr.containsKey(a.name), ownerKind: kind, depth: depth + 1, xp: [...base, a.name]);
    }
    final bad = beFuncExprProblem(doc, kind, expr, _known);
    if (bad != null) _error(bad.$1, bad.$2, arg: arg, fix: bad.$3);
    if (kind == 'pathParam') {
      final name = expr['name'];
      if (name is String && name.isNotEmpty && !_params.contains(name)) {
        final have = _params.isEmpty ? '这个接口的路径里没有参数' : '路径里有的是 ${_params.join('、')}';
        _error(BeIssueCode.unknownPathParam, '路径里没有叫 $name 的参数（$have）；读到的会是空的', arg: arg);
      }
    }
  }
}
