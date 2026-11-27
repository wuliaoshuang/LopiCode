/// Dart 的语法树 → 语法树的文字写法（S 表达式）。lc_text.dart 是读，这里是写；两边的写法一一对上。
/// 库的模块文件（`*.lc`）、库积木“原地展开”的模板都靠它从画布存到盘上（积木第 5 版·用户自己写库）。
/// 格式说明见 docs/blocks-v5-parts/library-format.md 第 4 节和第 9 节（转义规矩）。
///
/// 文字的规矩：里面没有双引号、反斜杠、换行的，照老写法 `"…"` 原样写（老写法不做转义，老样例靠这个）；
/// 有的写成 `(字 "…")`，里面 `\\` `\"` `\n` `\r` `\t` 是转义。
///
/// 写不了的东西（注释以外的宿主语句、名字里有空格括号……）抛 [LcWriteProblem]；产品里一律走 [lcTryWriteModule] / [lcTryWrite]。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

class LcWriteProblem implements Exception {
  const LcWriteProblem(this.what);
  final String what;
  @override
  String toString() => what;
}

/// 文字 → 带转义的写法里引号中间的那一段。
String lcEscapeText(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r').replaceAll('\t', r'\t');

/// 带转义的写法里引号中间的那一段 → 文字。不认识的转义原样留着那个字。
String lcUnescapeText(String s) {
  if (!s.contains(r'\')) return s;
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != r'\' || i + 1 >= s.length) {
      out.write(c);
      continue;
    }
    final n = s[++i];
    out.write(switch (n) {
      'n' => '\n',
      'r' => '\r',
      't' => '\t',
      _ => n,
    });
  }
  return out.toString();
}

final RegExp _token = RegExp(r'^[^\s()";]+$');
final RegExp _numLike = RegExp(r'^-?[\d.]');
const Set<String> _reserved = {'空', '是', '否', '->', '=', '_'};

/// 一个字面的值（空 / 是否 / 数 / 文字）的写法。
String lcWriteLiteral(Object? v) {
  switch (v) {
    case null:
      return '空';
    case bool():
      return v ? '是' : '否';
    case int():
      return '$v';
    case double():
      if (v.isNaN || v.isInfinite) throw const LcWriteProblem('有一个数不是正常的数（无穷大或者算不出来的数），存不了');
      return '$v';
    case String():
      return v.contains('"') || v.contains(r'\') || v.contains('\n') || v.contains('\r') ? '(字 "${lcEscapeText(v)}")' : '"$v"';
    default:
      throw const LcWriteProblem('有一个直接写的值不是空、是否、数、文字，存不了');
  }
}

class LcWriter {
  LcWriter({this.exprHook, this.stmtHook});

  /// 模板用的钩子：给了写法就用它给的（把某些节点写成“洞”）。
  final String? Function(LExpr e)? exprHook;
  final String? Function(LStmt s)? stmtHook;

  String name(String n) {
    if (!_token.hasMatch(n) || _numLike.hasMatch(n) || _reserved.contains(n)) throw LcWriteProblem('名字「$n」存不了（名字里不能有空格、括号、引号、分号，不能是数字开头）');
    return n;
  }

  /// 只要求是一个完整的词（“看是哪种情况”里的情况名可以是“空”“整数”这种）。
  String token(String n) => _token.hasMatch(n) ? n : throw LcWriteProblem('名字「$n」存不了（名字里不能有空格、括号、引号、分号）');

  static const Map<LKind, String> _basic = {LKind.integer: '整数', LKind.number: '小数', LKind.text: '文字', LKind.bool: '是否', LKind.nul: '空', LKind.any: '任意'};

  String type(LType t) {
    if (t.nullable && t.kind != LKind.any && t.kind != LKind.nul) return '(可空 ${type(t.nonNull)})';
    final basic = _basic[t.kind];
    if (basic != null) return basic;
    switch (t.kind) {
      case LKind.list:
        return '(列表 ${type(t.of ?? LType.any)})';
      case LKind.dict:
        return '(字典 ${type(t.of ?? LType.any)})';
      case LKind.future:
        return '(稍后 ${type(t.of ?? LType.any)})';
      case LKind.fn:
        final head = t.waits == null ? '函数' : (t.waits! ? '要等函数' : '不等函数');
        return '($head (${t.params.map(type).join(' ')}) ${type(t.returns)})';
      default:
        final n = t.name;
        if (n == null) throw const LcWriteProblem('有一个类型还没定下来，存不了');
        return t.args.isEmpty ? name(n) : '(${name(n)} ${t.args.map(type).join(' ')})';
    }
  }

  String params(List<LParam> ps) => '(${ps.map(_param).join(' ')})';

  String _param(LParam p) {
    if (p.rest) throw LcWriteProblem('参数「${p.name}」是“剩下的全收”，库里存不了');
    final d = p.defaultValue, t = p.type;
    if (t == null) return d == null ? name(p.name) : '(${name(p.name)} = ${lcWriteLiteral(d.value)})';
    return d == null ? '(${name(p.name)} ${type(t)})' : '(${name(p.name)} ${type(t)} ${lcWriteLiteral(d.value)})';
  }

  String _typeParams(List<LTypeParam> tps, {bool bounds = true}) {
    if (tps.isEmpty) return '';
    const boundText = {kBoundComparable: '能比较'};
    return ' (泛型 ${[for (final p in tps) p.bound == null || !bounds ? name(p.name) : '(${name(p.name)} ${boundText[p.bound] ?? p.bound})'].join(' ')})';
  }

  /// 函数 / 方法 / 创建的后半截：`(参数…) [-> 类型] 语句…`。
  String _fnRest(LFuncDecl f, String pad) => '${params(f.params)}${f.type == null ? '' : ' -> ${type(f.type!)}'}${block(f.body, pad)}';

  String _fnHead(LFuncDecl f, String word) => f.waits ? '要等$word' : (f.noWait ? '不等$word' : word);

  /// 一串语句，每句前面换行缩进（空的就是空字符串）。
  String block(List<LStmt> list, String pad) {
    final out = StringBuffer();
    for (final s in list) {
      final text = stmt(s, pad);
      if (text != null) out.write('\n$pad$text');
    }
    return out.toString();
  }

  String decl(LDecl d, {String pad = '  '}) {
    final inner = '$pad  ';
    final String text;
    final bool public;
    switch (d) {
      case LVarDecl():
        public = d.isPublic;
        text = d.type == null ? '(变量 ${name(d.name)} ${expr(d.init)})' : '(变量 ${name(d.name)} ${type(d.type!)} ${expr(d.init)})';
      case LFuncDecl():
        public = d.isPublic;
        text = '(${_fnHead(d, '函数')} ${name(d.name)}${_typeParams(d.typeParams)} ${_fnRest(d, inner)})';
      case LClassDecl():
        public = d.isPublic;
        final parts = <String>[
          if (d.isOpen) '可继承',
          if (d.typeParams.isNotEmpty) _typeParams(d.typeParams, bounds: false).trim(),
          if (d.parent != null) '(继承 ${name(d.parent!)})',
          if (d.interfaces.isNotEmpty) '(实现 ${d.interfaces.map(name).join(' ')})',
          for (final f in d.fields)
            '(${f.isPrivate ? '内部' : ''}${f.isStatic ? '类字段' : '字段'} ${name(f.name)} ${type(f.type ?? LType.any)}${f.init == null ? '' : ' ${expr(f.init!)}'})',
          if (d.ctor != null) '(创建 ${params(d.ctor!.params)}${block(d.ctor!.body, '$inner  ')})',
          for (final m in d.methods)
            if (m.isAbstract)
              throw LcWriteProblem('类「${d.name}」里有只写了样子没写内容的方法，库里存不了')
            else if (m.isStatic)
              '(类方法 ${name(m.fn.name)}${_typeParams(m.fn.typeParams)} ${_fnRest(m.fn, '$inner  ')})'
            else
              '(${_fnHead(m.fn, '方法')} ${name(m.fn.name)}${_typeParams(m.fn.typeParams)} ${_fnRest(m.fn, '$inner  ')})',
        ];
        text = '(类 ${name(d.name)}${parts.map((p) => '\n$inner$p').join()})';
      case LInterfaceDecl():
        public = d.isPublic;
        text =
            '(接口 ${name(d.name)}${[for (final m in d.methods) '\n$inner(${name(m.name)} ${params(m.params)} ${type(m.returns ?? LType.nul)}${m.waits ? ' 要等' : (m.noWait ? ' 不等' : '')})'].join()})';
      case LNativeDecl():
        public = false;
        text = '(宿主 ${name(d.name)} ${params(d.params)} -> ${type(d.type ?? LType.nul)})';
      case LRecordDecl():
        public = d.isPublic;
        if (d.typeParams.isNotEmpty) throw LcWriteProblem('记录「${d.name}」带了泛型，库里存不了');
        text = '(记录 ${name(d.name)}${[for (final f in d.fields) ' (${name(f.name)} ${type(f.type)})'].join()})';
      case LEnumDecl():
        public = d.isPublic;
        text = '(枚举 ${name(d.name)} ${d.cases.map(name).join(' ')})';
      case LVariantDecl():
        public = d.isPublic;
        text = '(变体 ${name(d.name)}${[for (final c in d.cases) ' (${name(c.name)}${[for (final f in c.fields) ' (${name(f.name)} ${type(f.type)})'].join()})'].join()})';
      case LAliasDecl():
        public = d.isPublic;
        text = '(别名 ${name(d.name)} ${type(d.target)})';
    }
    return public ? '(公开 $text)' : text;
  }

  /// 一个模块：`(模块 名 (用 …) 声明…)`。[main]＝许不许带“程序开始时”（库的模块不许；写整个程序的时候许）。
  String module(LModule m, {bool main = false}) {
    if (m.body.isNotEmpty && !main) throw LcWriteProblem('模块「${m.name}」里有“程序开始时”，库的模块不许有');
    return '(模块 ${name(m.name)}${m.uses.isEmpty ? '' : ' (用 ${m.uses.map(name).join(' ')})'}${[for (final d in m.decls) '\n  ${decl(d)}'].join()}${m.body.isEmpty ? '' : '\n  (主${block(m.body, '    ')})'})\n';
  }

  /// 几个模块的程序（[lcProgram] 读的那种）。
  String program(LProgram p) => '${[for (final m in p.modules) module(m, main: true)].join()}(入口 ${name(p.entry)})\n';

  String _catchPart(String? x) => x == null ? '_' : name(x);

  /// 一句语句；注释不写（返回 null）。
  String? stmt(LStmt s, String pad) {
    final hooked = stmtHook?.call(s);
    if (hooked != null) return hooked;
    final inner = '$pad  ';
    String body(List<LStmt> list) => block(list, inner);
    switch (s) {
      case LNote():
        return null;
      case LLet():
        if (s.kind == LNameKind.temp) return '(临设 ${name(s.name)} ${expr(s.value)})';
        if (s.kind == LNameKind.host) throw const LcWriteProblem('用到了宿主给的名字，库里存不了');
        final t = s.type;
        return '(${s.isConst ? '常' : '设'} ${name(s.name)}${t == null ? '' : ' ${type(t)}'} ${expr(s.value)})';
      case LAssign(:final target, :final value):
        return switch (target) {
          LTName(name: final n) => '(改 ${name(n)} ${expr(value)})',
          LTIndex(:final of, :final key) => '(存 ${expr(of)} ${expr(key)} ${expr(value)})',
          LTField(:final of, name: final n) => '(改字段 ${expr(of)} ${name(n)} ${expr(value)})',
        };
      case LExprStmt(expr: final e):
        if (e is LSuperSend && e.isCtor) return '(父创建${_args(e.args)})';
        return '(做 ${expr(e)})';
      case LIf():
        return '(若${[for (final a in s.arms) '\n$inner(${expr(a.cond)}${block(a.body, '$inner  ')})'].join()}${s.orElse.isEmpty ? '' : '\n$inner(否则${block(s.orElse, '$inner  ')})'})';
      case LWhile():
        return s.cond == null ? '(一直${body(s.body)})' : '(当 ${expr(s.cond!)}${body(s.body)})';
      case LForCount():
        return '(从数 ${name(s.name)} ${expr(s.from)} ${expr(s.to)} ${expr(s.step)}${body(s.body)})';
      case LForEach():
        if (s.reuse) return '(每个旧 ${name(s.item)} ${expr(s.list)}${body(s.body)})';
        if (s.index != null) return '(每个带号 ${name(s.item)} ${name(s.index!)} ${expr(s.list)}${body(s.body)})';
        return '(每个 ${name(s.item)} ${expr(s.list)}${body(s.body)})';
      case LForPairs():
        return '(每对 ${name(s.key)} ${name(s.value)} ${expr(s.dict)}${body(s.body)})';
      case LRepeat():
        return '(重复 ${expr(s.times)}${body(s.body)})';
      case LBreak():
        return '(跳出)';
      case LContinue():
        return '(继续)';
      case LReturn():
        return s.value == null ? '(返回)' : '(返回 ${expr(s.value!)})';
      case LThrow():
        return '(抛出 ${expr(s.message)})';
      case LTry():
        final catches = s.catches;
        return '(试\n$inner(做${block(s.body, '$inner  ')})'
            '${catches.isEmpty ? '\n$inner(不接)' : [for (final c in catches) '\n$inner(出错时 ${_catchPart(c.kind)} ${_catchPart(c.name)}${block(c.body, '$inner  ')})'].join()}'
            '${s.finallyBody.isEmpty ? '' : '\n$inner(最后${block(s.finallyBody, '$inner  ')})'})';
      case LHost():
        throw const LcWriteProblem('用到了只有旧的接口服务才有的积木，库里存不了');
      case LMatch():
        return '(分情况 ${expr(s.subject)}'
            '${[for (final a in s.arms) '\n$inner(${token(a.caseName)} (${a.binds.map(name).join(' ')})${block(a.body, '$inner  ')})'].join()}'
            '${s.orElse == null ? '' : '\n$inner(其余${block(s.orElse!, '$inner  ')})'})';
    }
  }

  String _args(List<LExpr> list) => [for (final e in list) ' ${expr(e)}'].join();

  static const Map<String, String> _bin = {'+': '+', '-': '-', '*': '*', '/': '/', '//': '整除', '%': '余', '<': '<', '>': '>', '<=': '<=', '>=': '>=', '==': '==', '!=': '!='};

  String _inits(List<LFieldInit> fields) => [for (final f in fields) ' (${name(f.name)} ${expr(f.value)})'].join();

  String expr(LExpr e) {
    final hooked = exprHook?.call(e);
    if (hooked != null) return hooked;
    switch (e) {
      case LLit(:final value):
        return lcWriteLiteral(value);
      case LListLit(:final items):
        return '(列${_args(items)})';
      case LDictLit(:final entries):
        return '(典${[for (final x in entries) ' (${expr(x.key)} ${expr(x.value)})'].join()})';
      case LName(name: final n, :final kind):
        return switch (kind) {
          LNameKind.variable => name(n),
          LNameKind.temp => '(临 ${name(n)})',
          LNameKind.host => throw const LcWriteProblem('用到了“这次请求”这种宿主给的名字，库里存不了'),
        };
      case LField(:final of, name: final n):
        return '(. ${expr(of)} ${name(n)})';
      case LIndex(:final of, :final key):
        return '(项 ${expr(of)} ${expr(key)})';
      case LUnary(:final op, :final x):
        return op == 'not' ? '(非 ${expr(x)})' : (op == '-' ? '(负 ${expr(x)})' : '(一元 "$op" ${expr(x)})');
      case LBinary(:final op, :final l, :final r):
        final word = _bin[op];
        return word != null ? '($word ${expr(l)} ${expr(r)})' : '(二元 "$op" ${expr(l)} ${expr(r)})';
      case LLogic(:final op, :final l, :final r):
        return '(${op == 'and' ? '且' : '或'} ${expr(l)} ${expr(r)})';
      case LCond(:final cond, :final then, :final orElse):
        return '(三元 ${expr(cond)} ${expr(then)} ${expr(orElse)})';
      case LCall(:final callee, :final args):
        return '(调用 ${expr(callee)}${_args(args)})';
      case LSend(:final obj, :final method, :final args):
        return '(发 ${expr(obj)} ${name(method)}${_args(args)})';
      case LSuperSend(:final method, :final args):
        if (e.isCtor) throw const LcWriteProblem('“先做父类的创建”只能单独放一句');
        return '(父 ${name(method)}${_args(args)})';
      case LNew(:final cls, :final args, :final typeArgs):
        return typeArgs.isEmpty ? '(新 ${name(cls)}${_args(args)})' : '(新 (${name(cls)} ${typeArgs.map(type).join(' ')})${_args(args)})';
      case LIsA(:final x, :final cls):
        return '(是 ${name(cls)} ${expr(x)})';
      case LLambda():
        final head = e.waits ? '要等λ' : 'λ';
        return e.expr != null ? '($head ${params(e.params)} ${expr(e.expr!)})' : '($head块 ${params(e.params)}${block(e.body, '    ')})';
      case LThis():
        return '(这)';
      case LAwait(:final x):
        return '(等 ${expr(x)})';
      case LSpawn(:final body):
        return '(开始做块${block(body, '    ')})';
      case LRt(:final fn, :final args):
        return '(库 ${name(fn)}${_args(args)})';
      case LNative(name: final n, :final args):
        return '(宿 ${name(n)}${_args(args)})';
      case LRecordNew(:final record, :final fields):
        return '(新记 ${name(record)}${_inits(fields)})';
      case LRecordCopy(:final of, :final fields):
        return '(改记 ${expr(of)}${_inits(fields)})';
      case LEnumValue(:final enumName, :final caseName):
        return '(枚 ${name(enumName)} ${name(caseName)})';
      case LVariantNew(:final variant, :final caseName, :final args):
        return '(造于 ${name(variant)} ${name(caseName)}${_args(args)})';
      case LCast(:final x, :final to):
        return '(转 ${type(to)} ${expr(x)})';
      case LAscribe(:final x, :final to):
        return '(标 ${type(to)} ${expr(x)})';
    }
  }
}

/// 一个模块 → 文字写法。写不了给一句原因（不抛异常）。
({String? text, String? problem}) lcTryWriteModule(LModule m) => lcTryWrite(() => LcWriter().module(m));

/// 包一层：把写的时候抛出来的东西换成一句话。
({String? text, String? problem}) lcTryWrite(String Function() write) {
  try {
    return (text: write(), problem: null);
  } on LcWriteProblem catch (e) {
    return (text: null, problem: e.what);
  } on Object catch (e) {
    return (text: null, problem: '存不了（$e）');
  }
}

/// 类型 → 文字写法；写不了返回 null。
String? lcTypeText(LType t) => lcTryWrite(() => LcWriter().type(t)).text;
