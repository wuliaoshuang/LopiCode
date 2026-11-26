/// 规矩版本 2 的生成器·Go·语句、声明、整个程序。类型和式子在 gen2_go.dart。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_err.dart';
import 'package:lopicode/lang/gen2_go.dart';
import 'package:lopicode/lang/rt2_go_dyn.dart';
import 'package:lopicode/lang/rt2_go_host.dart';
import 'package:lopicode/lang/rt2_go_more.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/types.dart';

/// 一个函数里“试着做”的状态：现在套在几层闭包里（每层记下进闭包时的循环层数）、现在在第几层循环里。
class _TryState {
  final List<int> closures = [];
  int loops = 0;
}

class GoGen2 extends GoGen2Types {
  GoGen2(super.module, super.r);

  @override
  String get mainFile => 'main.go';
  @override
  Map<String, String> get runtimeFiles => const {'go.mod': 'module lcprog\n\ngo 1.18\n', 'lc/lc.go': kRt2GoSource, 'lc/host.go': kRt2GoHost, 'lc/more.go': kRt2GoMore};

  final Map<V2Fn, _TryState> _states = Map.identity();
  _TryState get _st => _states[fn] ??= _TryState();

  // —— 语句 ——

  @override
  String get end => '';
  @override
  String whileHead(String? cond) => cond == null ? 'for' : 'for $cond';
  @override
  String countHead(String k, String n) => 'for $k := int64(0); $k < $n; $k++';
  @override
  String tmpDecl(String name, LType type, String code) => '$name := $code\n_ = $name';
  @override
  List<String> exprStmt(String code, {required bool isVoid}) => code == 'nil' ? const [] : [isVoid ? code : '_ = $code'];
  @override
  List<String> throwLines(String message) => ['panic(lc.Error{Msg: $message})'];
  // gofmt 的缩进是制表符。
  @override
  String get indentUnit => '\t';
  @override
  List<String> unreachable() => ['panic(lc.Error{Msg: "到不了这里"})'];
  @override
  String snapshot(String list, LType elem) => '$list.Snap()';
  @override
  String nativeLen(String arr) => 'int64(len($arr))';
  @override
  String nativeAt(String arr, String k, LType elem) => '$arr[$k]';
  @override
  String dictKeysNative(String dict, LType value) => 'lc.Keys($dict)';
  @override
  String dictAt(String dict, String key, LType value) => '$dict[$key]';
  @override
  String stepsCode(String a, String b, String s, {required bool ints}) => 'lc.${ints ? 'Steps' : 'FSteps'}($a, $b, $s)';
  @override
  void loopIn() => _st.loops++;
  @override
  void loopOut() => _st.loops--;

  // “试着做”翻成 lc.Try(闭包)。闭包里的“返回”“跳出”“继续”出不了闭包：先记在 lcRet / lcDone / lcBrk 里，出了闭包再真的做。
  bool get _crossing => _st.closures.isNotEmpty && _st.loops == _st.closures.last;

  @override
  String returnLine(String? value) {
    if (_st.closures.isEmpty) return super.returnLine(value);
    return [if (value != null) 'lcRet = $value', 'lcDone = true', 'return'].join('\n');
  }

  @override
  List<String> breakLines() => _crossing ? ['lcBrk = 1', 'return'] : super.breakLines();
  @override
  List<String> continueLines() => _crossing ? ['lcBrk = 2', 'return'] : super.continueLines();

  List<String> _closure(List<String> Function() gen) {
    final st = _st;
    st.closures.add(st.loops);
    try {
      return gen();
    } finally {
      st.closures.removeLast();
    }
  }

  /// 出了一层闭包以后：里面要“返回”“跳出”“继续”的，在这里接着做。
  List<String> _after() {
    final st = _st;
    final inside = st.closures.isNotEmpty;
    final inLoop = st.loops > (inside ? st.closures.last : 0);
    return [
      'if lcDone {',
      ...indent([inside || fn.isVoid ? 'return' : 'return lcRet']),
      '}',
      if (inLoop) ...[
        'if lcBrk == 1 {',
        ...indent(['lcBrk = 0', 'break']),
        '}',
        'if lcBrk == 2 {',
        ...indent(['lcBrk = 0', 'continue']),
        '}',
      ] else if (inside) ...[
        'if lcBrk != 0 {',
        ...indent(['return']),
        '}',
      ],
    ];
  }

  @override
  List<String> throwObjLines(String obj, String message) => ['panic(lc.Error{Msg: $message, Obj: $obj})'];
  @override
  String errObjCode(String e) => 'lcErrObj(&$e)';
  @override
  List<String> rethrowLines(String e) => ['panic($e)'];
  @override
  String errKindCode(String obj, LType type) => '$obj.LcName()';
  @override
  List<String> errSupport() {
    final et = gt(Gen2Err.errType);
    return [
      'func lcErrObj(lcE *lc.Error) $et {',
      ...indent([
        'if lcE.Obj == nil {',
        ...indent([
          'lcM := lcE.Msg',
          'switch lc.ErrKind(lcM) {',
          for (final (k, make) in errMakers('lcM').skip(1)) ...[
            'case ${textLit(k)}:',
            ...indent(['lcE.Obj = $make']),
          ],
          'default:',
          ...indent(['lcE.Obj = ${errMakers('lcM').first.$2}']),
          '}',
        ]),
        '}',
        'return lcE.Obj.($et)',
      ]),
      '}',
    ];
  }

  @override
  List<String> tryFrame(LTry s, List<String> Function(List<LStmt>) gen, List<String> Function(String e)? handler) {
    List<String> core() {
      if (handler == null) return gen(s.body);
      final m = tmpName('E'), ok = tmpName('O');
      final body = _closure(() => gen(s.body));
      return [
        '$m, $ok := lc.TryE(func() {',
        ...indent(body),
        '})',
        'if !$ok {',
        ...indent(['_ = &$m', ...handler(m)]),
        '}',
        ..._after(),
      ];
    }

    if (s.finallyBody.isEmpty) return core();
    final inner = _closure(() {
      final fin = _closure(() => gen(s.finallyBody));
      return ['defer func() {', ...indent(fin), '}()', ...core()];
    });
    return ['func() {', ...indent(inner), '}()', ..._after()];
  }

  @override
  List<String> alwaysTail(V2Fn f) => f.hasTry ? unreachable() : const [];

  @override
  List<String> declareLocals(V2Fn f) => [
    for (final v in localsOf(f.scope)) ...['var ${varCode(V2Var(v, f.depth))} ${gt(v.type)}', '_ = ${varCode(V2Var(v, f.depth))}'],
    if (f.hasTry) ...[
      if (!f.isVoid) ...['var lcRet ${gt(f.ret)}', '_ = lcRet'],
      'lcDone, lcBrk := false, 0',
      '_, _ = lcDone, lcBrk',
    ],
  ];

  // —— 函数 ——

  String _retOf(LType ret) => ret.isNul ? '' : ' ${gt(ret)}';

  /// 参数表（[types] 是签名上的类型）；参数变量自己的类型和签名不一样时，先收进临时名字再转。
  (String, List<String>) _params(V2Fn f, List<LParam> params, List<LType> types) => inFn(f, () {
    final parts = <String>[], first = <String>[];
    for (var i = 0; i < params.length; i++) {
      final v = mustVar(params[i].name, module);
      final pt = i < types.length ? types[i] : v.type;
      if (pt == v.type) {
        parts.add('${varCode(v)} ${gt(pt)}');
      } else {
        parts.add('lcP$i ${gt(pt)}');
        first.addAll(['var ${varCode(v)} ${gt(v.type)} = ${conv('lcP$i', pt, v.type)}', '_ = ${varCode(v)}']);
      }
    }
    return (parts.join(', '), first);
  });

  @override
  String lambdaCode(LLambda e, LType ft, V2Fn inner) {
    final (params, first) = _params(inner, e.params, ft.hasShape ? ft.params : const []);
    final body = funcBody(inner, e.stmts, first: () => first);
    return 'func($params)${_retOf(inner.ret)} {\n${indent(body).join('\n')}\n}';
  }

  String _typeParams(List<String> vars, Map<String, String> bounds) {
    if (vars.isEmpty) return '';
    String bound(String v) => switch (bounds[v]) {
      null || kBoundKey => 'any',
      kBoundComparable => 'lc.Ordered',
      final String name => typeName(name),
    };
    return '[${vars.map((v) => '${typeVar(v)} ${bound(v)}').join(', ')}]';
  }

  String _typeArgs(List<String> vars) => vars.isEmpty ? '' : '[${vars.map(typeVar).join(', ')}]';

  List<String> _function(LFuncDecl d) {
    final sig = r.funcs[d.name]!;
    final f = V2Fn(d.name, sig.returns, waits: d.waits);
    final (params, first) = _params(f, d.params, sig.params);
    return ['func ${funcName(d.name)}${_typeParams(sig.info.own, sig.info.bounds)}($params)${_retOf(sig.returns)} {', ...indent(funcBody(f, d.body, first: () => first)), '}'];
  }

  // —— 类型的声明 ——

  /// 字段名按码点排好（写成 JSON 时的顺序，和别的语言一样）。
  List<String> _sorted(Iterable<String> names) {
    int cmp(String a, String b) {
      final x = a.runes.toList(), y = b.runes.toList();
      for (var i = 0; i < x.length && i < y.length; i++) {
        if (x[i] != y[i]) return x[i] - y[i];
      }
      return x.length - y.length;
    }

    return names.toList()..sort(cmp);
  }

  /// 记录 / 变体的一种情况：结构体＋名字＋按内容相等＋写成 JSON。
  List<String> _struct(String name, String label, List<String> tvars, List<(String, LType)> fields, {String? marker}) {
    final tp = _typeParams(tvars, const {}), self = '$name${_typeArgs(tvars)}';
    final eqs = [for (final f in fields) eqSame(f.$2, 'a.${member(f.$1)}', 'b.${member(f.$1)}')];
    final types = {for (final f in fields) f.$1: f.$2};
    final json = [for (final n in _sorted(types.keys)) '${textLit('${n == _sorted(types.keys).first ? '' : ','}${_jsonKey(n)}:')} + lc.ToJson(a.${member(n)})'];
    return [
      'type $name$tp struct {',
      ...indent([for (final f in fields) '${member(f.$1)} ${gt(f.$2)}']),
      '}',
      'func (a $self) LcName() string { return ${textLit(label)} }',
      if (marker != null) 'func (a $self) $marker() {}',
      'func (a $self) LcEq(o any) bool {',
      ...indent(fields.isEmpty ? ['_, ok := o.($self)', 'return ok'] : ['b, ok := o.($self)', 'return ok && ${eqs.join(' && ')}']),
      '}',
      'func (a $self) LcJson() string { return ${['"{"', ...json, '"}"'].join(' + ')} }',
    ];
  }

  /// JSON 里的键（带引号、转义好）。
  String _jsonKey(String name) => '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  List<String> _record(LRecordDecl d) {
    final tv = [for (final p in d.typeParams) p.name];
    return _struct(typeName(d.name), d.name, tv, [for (final f in d.fields) (f.name, w.resolve(f.type, tv))]);
  }

  List<String> _enum(LEnumDecl d) {
    final t = typeName(d.name);
    return [
      'type $t int64',
      'const (',
      ...indent([for (var i = 0; i < d.cases.length; i++) '${enumCode(d, d.cases[i])} $t = $i']),
      ')',
      'func (e $t) LcName() string { return [...]string{${d.cases.map(textLit).join(', ')}}[e] }',
      'func (e $t) LcEnum() {}',
    ];
  }

  List<String> _variant(LVariantDecl d) {
    final t = typeName(d.name), marker = 'lcIs_$t';
    return [
      'type $t interface {',
      ...indent(['$marker()', 'LcName() string']),
      '}',
      for (final c in d.cases) ..._struct(caseType(d.name, c.name), c.name, const [], [for (final f in c.fields) (f.name, w.resolve(f.type))], marker: marker),
    ];
  }

  List<String> _interface(LInterfaceDecl d) => [
    'type ${typeName(d.name)} interface {',
    ...indent([
      for (final m in d.methods) '${member(m.name)}(${[for (final p in m.params) gt(w.resolve(p.type))].join(', ')})${_retOf(w.resolve(m.returns ?? LType.nul))}',
      'lcIs_${v2Ident(d.name)}()',
    ]),
    '}',
  ];

  List<String> _class(LClassInfo c) {
    final d = c.decl, open = isOpen(c.name), id = v2Ident(c.name);
    final parent = w.classes[d.parent];
    if (parent != null && parent.typeVars.isNotEmpty) unsupported('继承带类型变量的类「${parent.name}」（Go 的带类型生成路径里还没有）', d);
    final tp = _typeParams(c.typeVars, const {}), ta = _typeArgs(c.typeVars);
    final s = '${open ? bodyName(c.name) : typeName(c.name)}$ta', recv = '(o *$s)';
    final out = <String>[];
    final sigs = {for (final m in d.ownMethods) m.fn.name: r.funcs['${c.name}.${m.fn.name}']!};
    for (final m in d.ownMethods) {
      if (sigs[m.fn.name]!.info.own.isNotEmpty) unsupported('方法「${m.fn.name}」自己带类型变量（Go 的方法不能带）', d);
    }
    if (open) {
      out.addAll([
        'type ${typeName(c.name)}$tp interface {',
        ...indent([
          if (parent != null) typeName(parent.name),
          // 实现了的接口也嵌进来：拿着“可以被继承的类”这个类型的值，才能直接当那个接口用。
          for (final i in d.interfaces)
            if (w.interfaces.containsKey(i)) typeName(i),
          for (final m in d.ownMethods) '${member(m.fn.name)}(${sigs[m.fn.name]!.params.map(gt).join(', ')})${_retOf(sigs[m.fn.name]!.returns)}',
          'lcAs_$id() *$s',
          'LcName() string',
          'LcObj()',
        ]),
        '}',
      ]);
    }
    // 根上的类如果能被继承，“体”里放一个 self 指回最外面那个对象：父类方法里“让自己做”会找到子类重写的那个。
    var root = c;
    while (w.classes[root.decl.parent] != null) {
      root = w.classes[root.decl.parent]!;
    }
    final hasSelf = isOpen(root.name);
    out.addAll([
      'type ${open ? bodyName(c.name) : typeName(c.name)}$tp struct {',
      ...indent([
        if (parent != null) bodyName(parent.name),
        if (parent == null && open) 'self ${typeName(c.name)}$ta',
        for (final f in d.ownFields) '${member(f.name)} ${gt(w.resolve(f.type, c.typeVars))}',
      ]),
      '}',
      'func $recv LcName() string { return ${textLit(c.name)} }',
      if (parent == null) 'func $recv LcObj() {}',
      if (open) 'func $recv lcAs_$id() *$s { return o }',
      for (final i in d.interfaces) 'func $recv lcIs_${v2Ident(i)}() {}',
    ]);
    // 字段的初始值。
    final init = V2Fn('${c.name}.字段', LType.nul, cls: c);
    out.addAll([
      'func $recv lcF_$id() {',
      ...indent(
        inFn(
          init,
          () => [
            for (final f in d.ownFields)
              if (f.init != null) 'o.${member(f.name)} = ${x(f.init!, w.resolve(f.type, c.typeVars))}',
          ],
        ),
      ),
      '}',
    ]);
    // “创建时”。
    final ctor = d.ctor;
    final String params;
    final List<String> args;
    if (ctor != null) {
      final sig = r.funcs['${c.name}.创建']!;
      final f = V2Fn(sig.key, LType.nul, cls: c, isCtor: true);
      final (ps, first) = _params(f, ctor.params, sig.params);
      var explicit = false;
      lWalk(ctor.body, (LStmt st) {
        for (final e in lStmtExprs(st)) {
          if (e is LSuperSend && e.isCtor) explicit = true;
        }
      });
      final head = [if (!explicit && parent != null) 'o.${bodyName(parent.name)}.lcInit()', if (!explicit) 'o.lcF_$id()'];
      out.addAll([
        'func $recv lcInit($ps) {',
        ...indent(funcBody(f, ctor.body, first: () => [...head, ...first])),
        '}',
      ]);
      params = [for (var i = 0; i < sig.params.length; i++) 'a$i ${gt(sig.params[i])}'].join(', ');
      args = [for (var i = 0; i < sig.params.length; i++) 'a$i'];
    } else {
      final inherited = parent == null ? null : r.funcs[w.classCtor(parent)?.key];
      final types = inherited?.params ?? const <LType>[];
      params = [for (var i = 0; i < types.length; i++) 'a$i ${gt(types[i])}'].join(', ');
      args = [for (var i = 0; i < types.length; i++) 'a$i'];
      out.addAll([
        'func $recv lcInit($params) {',
        ...indent([if (parent != null) 'o.${bodyName(parent.name)}.lcInit(${args.join(', ')})', 'o.lcF_$id()']),
        '}',
      ]);
    }
    out.addAll([
      'func New_$id$tp($params) *$s {',
      ...indent(['o := &$s{}', if (hasSelf) 'o.self = o', 'o.lcInit(${args.join(', ')})', 'return o']),
      '}',
    ]);
    for (final m in d.ownMethods) {
      final sig = sigs[m.fn.name]!;
      final f = V2Fn(sig.key, sig.returns, cls: c, waits: m.fn.waits);
      final (ps, first) = _params(f, m.fn.params, sig.params);
      out.addAll(['func $recv ${member(m.fn.name)}($ps)${_retOf(sig.returns)} {', ...indent(funcBody(f, m.fn.body, first: () => first)), '}']);
    }
    return out;
  }

  // —— 整个程序 ——

  @override
  String program() {
    final top = <String>[];
    void add(List<String> lines) {
      if (lines.isEmpty) return;
      top
        ..add('')
        ..addAll(lines);
    }

    add([for (final g in globals) 'var ${varCode(V2Var(g, 0, global: true))} ${gt(g.type)}']);
    if (r.usesErrors) add(errSupport());
    for (final d in decls) {
      switch (d) {
        case LRecordDecl():
          add(_record(d));
        case LEnumDecl():
          add(_enum(d));
        case LVariantDecl():
          add(_variant(d));
        case LInterfaceDecl():
          add(_interface(d));
        case LClassDecl():
          add(_class(w.classes[d.name]!));
        case LFuncDecl():
          add(_function(d));
        case LAliasDecl() || LVarDecl() || LNativeDecl():
          break;
      }
    }
    final main = V2Fn(Gen2Base.mainScope, LType.nul, isMain: true, waits: true);
    final body = funcBody(main, startup);
    return [
      '// 由 LopiCode 积木生成（Go，严格规矩、带原生类型）。',
      'package main',
      '',
      'import "lcprog/lc"',
      ...top,
      '',
      'func main() {',
      ...indent(['lc.Run(func() {', ...indent(body), '})']),
      '}',
      '',
    ].join('\n');
  }
}
