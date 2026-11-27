/// 规矩版本 2 的生成器·Java·语句、声明、整个程序。类型和式子在 gen2_java.dart。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_err.dart';
import 'package:lopicode/lang/gen2_java.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/rt2_java_dyn.dart';
import 'package:lopicode/lang/rt2_java_host.dart';
import 'package:lopicode/lang/rt2_java_task.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/types.dart';

class JavaGen2 extends JavaGen2Types {
  JavaGen2(super.module, super.r);

  @override
  String get mainFile => 'Main.java';
  @override
  Map<String, String> get runtimeFiles => const {'Lc.java': kRt2JavaSource, 'LcHost.java': kRt2JavaHost, 'LcTask.java': kRt2JavaTask};

  // —— 语句 ——

  /// 条件看上去是写死的 true / false 时前面垫一个 Lc.yes()：Java 见到 while (true) 会认定后面的代码永远到不了，不让编。
  @override
  String whileHead(String? cond) {
    if (cond == null) return 'while (Lc.yes())';
    final fixed = cond.replaceAll(RegExp(r'true|false|[\s()!&|]'), '').isEmpty;
    return fixed ? 'while (Lc.yes() && $cond)' : 'while ($cond)';
  }

  @override
  String countHead(String k, String n) => 'for (long $k = 0; $k < $n; $k++)';
  @override
  String tmpDecl(String name, LType type, String code) => 'final var $name = $code;';
  @override
  List<String> exprStmt(String code, {required bool isVoid}) => code == 'null' ? const [] : [isVoid ? '$code;' : 'Lc.drop($code);'];
  @override
  List<String> throwLines(String message) => ['throw new Lc.LcError($message);'];
  @override
  List<String> unreachable() => ['throw new Lc.LcError("到不了这里");'];
  @override
  String snapshot(String list, LType elem) => 'Lc.items($list)';
  @override
  String nativeLen(String arr) => '$arr.size()';
  @override
  String nativeAt(String arr, String k, LType elem) => '$arr.get((int) $k)';
  @override
  String dictKeysNative(String dict, LType value) => 'Lc.keys($dict)';
  @override
  String dictAt(String dict, String key, LType value) => '$dict.get($key)';
  @override
  String stepsCode(String a, String b, String s, {required bool ints}) => 'Lc.${ints ? 'steps' : 'fsteps'}($a, $b, $s)';

  @override
  List<String> throwObjLines(String obj, String message) => ['throw new Lc.LcError($message, $obj);'];
  @override
  String errObjCode(String e) => '${split == null || curModule == Gen2Split.kinds ? '' : 'LcKinds.'}lcErrObj($e)';
  @override
  List<String> rethrowLines(String e) => ['throw $e;'];
  @override
  String errKindCode(String obj, LType type) => '$obj.lcName()';
  @override
  List<String> errSupport() {
    final et = jt(Gen2Err.errType);
    return [
      'static $et lcErrObj(Lc.LcError lcE) {',
      ...indent([
        'if (lcE.obj == null) {',
        ...indent([
          'final String lcM = lcE.getMessage();',
          'switch (Lc.errKind(lcM)) {',
          ...indent([for (final (k, make) in errMakers('lcM').skip(1)) 'case ${textLit(k)} -> lcE.obj = $make;', 'default -> lcE.obj = ${errMakers('lcM').first.$2};']),
          '}',
        ]),
        '}',
        'return ($et) lcE.obj;',
      ]),
      '}',
    ];
  }

  @override
  List<String> tryFrame(LTry s, List<String> Function(List<LStmt>) gen, List<String> Function(String e)? handler) {
    final e = tmpName('E');
    return [
      'try {',
      ...indent(gen(s.body)),
      if (handler != null) ...['} catch (Lc.LcError $e) {', ...indent(handler(e))],
      if (s.finallyBody.isNotEmpty) ...['} finally {', ...indent(gen(s.finallyBody))],
      '}',
    ];
  }

  // Java 自己算“这句后面的代码到不到得了”，到不了的代码不让编。下面照它的算法来（JLS 14.22），生成的结构和这里一一对应。
  bool _completes(List<LStmt> list) => list.every(_stmtCompletes);

  bool _stmtCompletes(LStmt s) => switch (s) {
    LReturn() || LThrow() || LBreak() || LContinue() => false,
    LIf(:final arms, :final orElse) => arms.isEmpty ? _completes(orElse) : orElse.isEmpty || arms.any((a) => _completes(a.body)) || _completes(orElse),
    LTry(:final body, :final catches, :final finallyBody) => (_completes(body) || catches.any((c) => _completes(c.body))) && _completes(finallyBody),
    LMatch(:final arms, :final orElse) => arms.any((a) => _completes(a.body)) || (orElse != null && _completes(orElse)),
    _ => true,
  };

  @override
  bool stmtExits(LStmt s) => !_stmtCompletes(s);
  @override
  bool fallsOff(List<LStmt> body) => _completes(body);

  @override
  List<String> declareLocals(V2Fn f) => [
    for (final v in localsOf(f.scope))
      () {
        final vv = V2Var(v, f.depth);
        return isCaptured(vv) ? 'final Lc.Ref<${jb(v.type)}> ${varBase(vv)} = new Lc.Ref<>(${zero(v.type)});' : '${jt(v.type)} ${varBase(vv)} = ${zero(v.type)};';
      }(),
  ];

  // —— 函数 ——

  String _retOf(LType ret) => ret.isNul ? 'void' : jt(ret);

  /// 参数的名字（[types] 是签名上的类型）＋函数开头要补的几句：参数变量自己的类型和签名不一样、或者它被里层匿名函数用到
  /// （要装盒子）时，先收进临时名字再转。
  (List<String>, List<String>) _bind(V2Fn f, List<LParam> params, List<LType> types, String Function(int i, LType pt) source) => inFn(f, () {
    final names = <String>[], first = <String>[];
    for (var i = 0; i < params.length; i++) {
      final v = mustVar(params[i].name, module);
      final pt = i < types.length ? types[i] : v.type;
      final boxed = isCaptured(v);
      final given = source(i, pt);
      final src = given.isEmpty ? (!boxed && pt == v.type ? varBase(v) : 'lcP${f.depth}_$i') : given;
      names.add(src);
      if (src == varBase(v)) continue;
      final value = conv(src, pt, v.type);
      first.add(boxed ? 'final Lc.Ref<${jb(v.type)}> ${varBase(v)} = new Lc.Ref<>($value);' : '${jt(v.type)} ${varBase(v)} = $value;');
    }
    return (names, first);
  });

  /// 写在声明里的参数表（带类型）。
  (String, List<String>) _params(V2Fn f, List<LParam> params, List<LType> types) {
    final (names, first) = _bind(f, params, types, (i, pt) => '');
    return ([for (var i = 0; i < names.length; i++) '${jt(i < types.length ? types[i] : inFn(f, () => mustVar(params[i].name, module).type))} ${names[i]}'].join(', '), first);
  }

  @override
  String lambdaCode(LLambda e, LType ft, V2Fn inner) {
    if (!ft.hasShape) {
      // 不知道形状的匿名函数：参数、结果都当任意，装成 Lc.DynFn。
      final arr = 'lcA${inner.depth}_${inner.next()}';
      final (_, first) = _bind(inner, e.params, const [], (i, pt) => fromAny('$arr[$i]', pt));
      final body = funcBody(inner, e.stmts, first: () => first);
      return 'new Lc.DynFn(${e.params.length}, ($arr) -> {\n${indent(body).join('\n')}\n}, null)';
    }
    final (names, first) = _bind(inner, e.params, ft.params, (i, pt) => '');
    final body = funcBody(inner, e.stmts, first: () => first);
    return '((${jb(ft)}) (${names.join(', ')}) -> {\n${indent(body).join('\n')}\n})';
  }

  String _typeParams(List<String> vars, Map<String, String> bounds) {
    if (vars.isEmpty) return '';
    String one(String v) => switch (bounds[v]) {
      null || kBoundKey || kBoundComparable => typeVar(v),
      final String name => '${typeVar(v)} extends ${typeName(name)}',
    };
    return '<${vars.map(one).join(', ')}>';
  }

  String _typeArgs(List<String> vars) => vars.isEmpty ? '' : '<${vars.map(typeVar).join(', ')}>';

  List<String> _function(LFuncDecl d) {
    final sig = r.funcs[d.name]!;
    final f = V2Fn(d.name, sig.returns, waits: sig.waits);
    final (params, first) = _params(f, d.params, sig.params);
    final tp = _typeParams(sig.info.own, sig.info.bounds);
    return ['static ${tp.isEmpty ? '' : '$tp '}${_retOf(sig.returns)} ${funcName(d.name)}($params) {', ...indent(funcBody(f, d.body, first: () => first)), '}'];
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

  /// 记录 / 变体的一种情况：record＋名字＋字段表（比相等用）＋写成 JSON＋每个字段一个“复制并改”。
  List<String> _record(String name, String label, List<String> tvars, List<(String, LType)> fields, {String? variant}) {
    final self = '$name${_typeArgs(tvars)}';
    final keys = _sorted([for (final f in fields) f.$1]);
    final json = ['"{"', for (final k in keys) '${textLit('${k == keys.first ? '' : ','}${langJsonKey(k)}:')} + Lc.toJson(${member(k)})', '"}"'];
    return [
      'record $name${_typeParams(tvars, const {})}(${[for (final f in fields) '${jt(f.$2)} ${member(f.$1)}'].join(', ')}) implements ${[?variant, 'Lc.Rec'].join(', ')} {',
      ...indent([
        'public String lcName() { return ${textLit(label)}; }',
        'public Object[] lcFields() { return new Object[] {${[for (final f in fields) member(f.$1)].join(', ')}}; }',
        'public String lcJson() { return ${json.join(' + ')}; }',
        for (final f in fields)
          '$self w_${v2Ident(f.$1)}(${jt(f.$2)} lcV) { return new $name${tvars.isEmpty ? '' : '<>'}(${[for (final g in fields) g.$1 == f.$1 ? 'lcV' : member(g.$1)].join(', ')}); }',
      ]),
      '}',
    ];
  }

  /// JSON 里的键（带引号、转义好）。
  String langJsonKey(String name) => '"${name.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  List<String> _recordDecl(LRecordDecl d) {
    final tv = [for (final p in d.typeParams) p.name];
    return _record(typeName(d.name), d.name, tv, [for (final f in d.fields) (f.name, w.resolve(f.type, tv))]);
  }

  List<String> _enum(LEnumDecl d) => [
    'enum ${typeName(d.name)} implements Lc.Named {',
    ...indent([
      '${[for (final c in d.cases) 'c_${v2Ident(c)}(${textLit(c)})'].join(', ')};',
      'private final String label;',
      '${typeName(d.name)}(String label) { this.label = label; }',
      'public String lcName() { return label; }',
    ]),
    '}',
  ];

  List<String> _variant(LVariantDecl d) => [
    'interface ${typeName(d.name)} extends Lc.Named {}',
    for (final c in d.cases) ..._record(caseType(d.name, c.name), c.name, const [], [for (final f in c.fields) (f.name, w.resolve(f.type))], variant: typeName(d.name)),
  ];

  List<String> _interface(LInterfaceDecl d) => [
    'interface ${typeName(d.name)} {',
    ...indent([
      for (final m in d.methods) '${_retOf(w.resolve(m.returns ?? LType.nul))} ${member(m.name)}(${[for (var i = 0; i < m.params.length; i++) '${jt(w.resolve(m.params[i].type))} a$i'].join(', ')});',
    ]),
    '}',
  ];

  List<String> _class(LClassInfo c) {
    final d = c.decl, id = ascii(c.name);
    final parent = w.classes[d.parent];
    if (parent != null && parent.typeVars.isNotEmpty) unsupported('继承带类型变量的类「${parent.name}」（Java 的带类型生成路径里还没有）', d);
    final tp = _typeParams(c.typeVars, const {}), self = '${typeName(c.name)}${_typeArgs(c.typeVars)}';
    final impl = [if (parent == null) 'Lc.Obj', for (final i in d.interfaces) typeName(i)];
    final out = <String>[
      for (final f in d.ownFields) '${jt(w.resolve(f.type, c.typeVars))} ${member(f.name)};',
      if (parent == null) 'public String lcName() { return this.lcLabel(); }',
      'String lcLabel() { return ${textLit(c.name)}; }',
    ];
    // 字段的初始值。
    final init = V2Fn('${c.name}.字段', LType.nul, cls: c);
    out.addAll([
      'void lcF_$id() {',
      ...indent(
        inFn(
          init,
          () => [
            for (final f in d.ownFields)
              if (f.init != null) 'this.${member(f.name)} = ${x(f.init!, w.resolve(f.type, c.typeVars))};',
          ],
        ),
      ),
      '}',
    ]);
    // “创建时”。不用 Java 自己的构造函数：它要求“父创建”必须是第一句，积木没有这条规矩。
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
      final head = [if (!explicit && parent != null) 'super.lcInit_${ascii(parent.name)}();', if (!explicit) 'this.lcF_$id();'];
      out.addAll([
        'void lcInit_$id($ps) {',
        ...indent(funcBody(f, ctor.body, first: () => [...head, ...first])),
        '}',
      ]);
      params = [for (var i = 0; i < sig.params.length; i++) '${jt(sig.params[i])} a$i'].join(', ');
      args = [for (var i = 0; i < sig.params.length; i++) 'a$i'];
    } else {
      final inherited = parent == null ? null : r.funcs[w.classCtor(parent)?.key];
      final types = inherited?.params ?? const <LType>[];
      params = [for (var i = 0; i < types.length; i++) '${jt(types[i])} a$i'].join(', ');
      args = [for (var i = 0; i < types.length; i++) 'a$i'];
      out.addAll([
        'void lcInit_$id($params) {',
        ...indent([if (parent != null) 'super.lcInit_${ascii(parent.name)}(${args.join(', ')});', 'this.lcF_$id();']),
        '}',
      ]);
    }
    out.addAll([
      'static ${tp.isEmpty ? '' : '$tp '}$self lcNew_$id($params) {',
      ...indent(['$self o = new ${typeName(c.name)}${c.typeVars.isEmpty ? '' : '<>'}();', 'o.lcInit_$id(${args.join(', ')});', 'return o;']),
      '}',
    ]);
    for (final m in d.ownMethods) {
      final sig = r.funcs['${c.name}.${m.fn.name}']!;
      final f = V2Fn(sig.key, sig.returns, cls: c, waits: sig.waits);
      final (ps, first) = _params(f, m.fn.params, sig.params);
      final own = _typeParams(sig.info.own, sig.info.bounds);
      out.addAll(['public ${own.isEmpty ? '' : '$own '}${_retOf(sig.returns)} ${member(m.fn.name)}($ps) {', ...indent(funcBody(f, m.fn.body, first: () => first)), '}']);
    }
    final head = 'static class ${typeName(c.name)}$tp${parent == null ? '' : ' extends ${typeName(parent.name)}'}${impl.isEmpty ? '' : ' implements ${impl.join(', ')}'}';
    return ['$head {', ...indent(out), '}'];
  }

  // —— 整个程序 ——

  /// 顶层代码按“归哪一份”攒好（不分文件时只有一份），外加主程序的代码。
  (Gen2Parts, List<String>) _collect() {
    final parts = Gen2Parts();
    String part(String name) => split?.of(name) ?? Gen2Split.kinds;
    void add(String p, List<String> lines) => parts.add(p, lines.isEmpty ? lines : [...lines, '']);
    final vars = <String, List<String>>{};
    for (final g in globals) {
      curModule = part(g.name);
      (vars[curModule] ??= []).add('static ${jt(g.type)} ${varBase(V2Var(g, 0, global: true))} = ${zero(g.type)};');
    }
    vars.forEach(add);
    curModule = Gen2Split.kinds;
    if (r.usesErrors) add(Gen2Split.kinds, errSupport());
    for (final d in decls) {
      final p = curModule = part(d.name);
      switch (d) {
        case LRecordDecl():
          add(p, _recordDecl(d));
        case LEnumDecl():
          add(p, _enum(d));
        case LVariantDecl():
          add(p, _variant(d));
        case LInterfaceDecl():
          add(p, _interface(d));
        case LClassDecl():
          add(p, _class(w.classes[d.name]!));
        case LFuncDecl():
          add(p, _function(d));
        case LAliasDecl() || LVarDecl() || LNativeDecl():
          break;
      }
    }
    curModule = split?.entry ?? Gen2Split.kinds;
    final main = V2Fn(Gen2Base.mainScope, LType.nul, isMain: true, waits: true);
    return (parts, funcBody(main, startup));
  }

  String _mainText(List<String> top, List<String> body) => [
    '// 由 LopiCode 积木生成（Java，严格规矩、带原生类型）。',
    'import java.util.ArrayList;',
    'import java.util.TreeMap;',
    '',
    '@SuppressWarnings({"unchecked", "rawtypes", "cast"})',
    'public final class Main {',
    ...indent([
      'private Main() {}',
      '',
      ...top,
      'public static void main(String[] args) {',
      ...indent(['Lc.run(() -> {', ...indent(body), '});']),
      '}',
    ]),
    '}',
    '',
  ].join('\n');

  @override
  String program() {
    final (parts, body) = _collect();
    return _mainText(parts.of(Gen2Split.kinds), body);
  }

  /// 一个模块一个类文件，里面的东西都是 static 的：内置错误种类 `LcKinds`、别的模块 `M_模块名`、入口在 `Main`。
  /// 类和类之间没有继承关系：别的模块的函数、变量、类型在代码里都带着它所在的类名（`M_甲.f_x`、`M_甲.T_点`、`LcKinds.T_…`），
  /// 自己这一份里的只写名字（见 gen2_java.dart 的 `from`）。多个库一起用时，各是各的类，谁也不是谁的子类。
  @override
  Map<String, String> programFiles() {
    final s = split;
    if (s == null) return super.programFiles();
    final (parts, body) = _collect();
    const kinds = Gen2Split.kinds;
    final out = <String, String>{};
    void file(String cls, String what, List<String> top) {
      out['$cls.java'] = [
        '// 由 LopiCode 积木生成（Java，严格规矩、带原生类型）：$what。',
        'import java.util.ArrayList;',
        'import java.util.TreeMap;',
        '',
        '@SuppressWarnings({"unchecked", "rawtypes", "cast"})',
        'final class $cls {',
        ...indent(['$cls() {}', '', ...top]),
        '}',
        '',
      ].join('\n');
    }

    if (parts.of(kinds).isNotEmpty) file('LcKinds', '内置的错误种类', parts.of(kinds));
    for (final m in s.order) {
      file('M_${ascii(s.ident[m]!)}', '模块「${m.replaceAll(RegExp(r'[\x00-\x1f\x7f\u0085\u2028\u2029]'), ' ')}」', parts.of(m));
    }
    return {mainFile: _mainText(parts.of(s.entry), body), ...out};
  }
}
