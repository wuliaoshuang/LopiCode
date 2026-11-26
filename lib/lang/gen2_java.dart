/// 规矩版本 2 的生成器·Java（带原生类型，设计 B 第 7、11 节）·类型、转换、式子。语句和声明在 gen2_java_prog.dart。
/// 小库：`Lc.java`（rt2_java.dart / rt2_java_dyn.dart）。实际落成的映射见 docs/blocks-v5-parts/B-gen-notes.md。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_expr.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

abstract class JavaGen2Types extends Gen2 {
  JavaGen2Types(super.module, super.r);

  // —— 名字 ——

  /// 类型的名字只用英文字母、数字、下划线：Java 每个类型编出一个同名的 .class 文件，文件名里有中文在有些机器上会出问题。
  String ascii(String s) {
    final out = StringBuffer();
    for (final c in s.runes) {
      final plain = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
      out.write(plain ? String.fromCharCode(c) : '_${c.toRadixString(16)}');
    }
    return out.toString();
  }

  String typeName(String name) => 'T_${ascii(name)}';
  String caseType(String variant, String c) => 'T_${ascii(variant)}__${ascii(c)}';
  String member(String name) => 'm_${v2Ident(name)}';
  String funcName(String name) => 'f_${v2Ident(name)}';
  String typeVar(String name) => 'P_${ascii(name)}';

  /// 变量在 Java 里叫什么（不管它是不是装在盒子里）。
  String varBase(V2Var v) {
    if (v.global) return 'g_${v2Ident(v.name)}';
    if (v.info.kind == LVarKind.temp) return 'lcT${v.depth}_${v2Ident(v.name)}';
    return v.depth == 0 ? 'v_${v2Ident(v.name)}' : 'v${v.depth}_${v2Ident(v.name)}';
  }

  /// 被里层匿名函数用到的局部变量装在 Lc.Ref 盒子里（Java 的匿名函数只能用不再改的局部变量）。
  @override
  String varCode(V2Var v) => isCaptured(v) ? '${varBase(v)}.v' : varBase(v);

  // —— 类型 ——

  static const Set<LKind> _prims = {LKind.integer, LKind.number, LKind.bool};
  bool prim(LType t) => !t.nullable && _prims.contains(t.kind);

  String targs(List<LType> args) => args.isEmpty ? '' : '<${args.map(jb).join(', ')}>';

  /// 函数类型：Lc.Fn0…Fn4（有结果）、Lc.Act0…Act4（没结果）。
  String fnType(List<LType> ps, LType ret) {
    if (ps.length > 4) unsupported('参数超过 4 个的函数当值用（Java 的带类型生成路径里还没有）');
    final args = [...ps, if (!ret.isNul) ret];
    return 'Lc.${ret.isNul ? 'Act' : 'Fn'}${ps.length}${targs(args)}';
  }

  /// 放在〈〉里、或者可空时用的写法（整数是 Long）。
  String jb(LType t) {
    switch (t.kind) {
      case LKind.integer:
        return 'Long';
      case LKind.number:
        return 'Double';
      case LKind.text:
        return 'String';
      case LKind.bool:
        return 'Boolean';
      case LKind.list:
        return 'ArrayList<${jb(t.of ?? LType.any)}>';
      case LKind.dict:
        return 'TreeMap<String, ${jb(t.of ?? LType.any)}>';
      case LKind.fn:
        return t.hasShape ? fnType(t.params, t.returns) : 'Object';
      case LKind.record || LKind.enumeration || LKind.variant || LKind.interface:
        return '${typeName(t.name ?? '')}${targs(t.args)}';
      case LKind.object:
        return w.classes.containsKey(t.name) ? '${typeName(t.name!)}${targs(t.args)}' : 'Object';
      case LKind.typeVar:
        return typeVar(t.name ?? 'T');
      default:
        return 'Object';
    }
  }

  /// 变量、参数、返回值的写法（不可空的整数 / 小数 / 是否用 long / double / boolean）。
  String jt(LType t) => !prim(t)
      ? jb(t)
      : switch (t.kind) {
          LKind.integer => 'long',
          LKind.number => 'double',
          _ => 'boolean',
        };

  /// 这种类型的变量一开始放什么。
  String zero(LType t) => !prim(t)
      ? 'null'
      : switch (t.kind) {
          LKind.integer => '0L',
          LKind.number => '0.0',
          _ => 'false',
        };

  @override
  String nulOf(LType type) => type.isNul || type.isNever || type.isHole ? 'null' : '((${jb(type)}) null)';

  // —— 字面量 ——

  @override
  String nullLit() => 'null';
  @override
  String boolLit(bool v) => '$v';
  @override
  String intLit(int v) => v < 0 ? '(${v}L)' : '${v}L';
  @override
  String floatLit(double v) => v < 0 ? '(${langNumber(v, dotZero: true)})' : langNumber(v, dotZero: true);
  @override
  String textLit(String v) => langQuoted(v);
  @override
  String listLit(LType elem, List<String> items) => 'Lc.<${jb(elem)}>list(${items.join(', ')})';

  @override
  String dictLit(LType value, List<(String, String)> entries) {
    var code = 'Lc.<${jb(value)}>dict()';
    for (final e in entries) {
      code = 'Lc.put($code, ${e.$1}, ${e.$2})';
    }
    return code;
  }

  // —— 转换 ——

  String _named(LType t) => textLit('「${t.name ?? ''}」');
  String _rawClass(LType t) => t.kind == LKind.object && !w.classes.containsKey(t.name) ? 'Object' : typeName(t.name ?? '');

  /// 装进“任意”以后还是原样的那些类型。
  bool _sameInAny(LType t) {
    final n = t.nonNull;
    if (n.isAny || n.isNul) return true;
    return switch (n.kind) {
      LKind.text || LKind.bool || LKind.record || LKind.enumeration || LKind.variant || LKind.interface || LKind.object => true,
      LKind.fn => !n.hasShape,
      LKind.list || LKind.dict => (n.of ?? LType.any).isAny,
      _ => false,
    };
  }

  String toAny(String code, LType from) {
    if (_sameInAny(from)) return prim(from) ? '((Object) $code)' : code;
    if (from.nullable) {
      final v = tmpName('V');
      return 'Lc.opt($code, ($v) -> ${toAny(v, from.nonNull)})';
    }
    switch (from.kind) {
      case LKind.integer:
        return 'Lc.idyn($code)';
      case LKind.number:
        return 'Lc.fdyn($code)';
      case LKind.list || LKind.dict:
        final v = tmpName('V');
        return 'Lc.${from.kind == LKind.list ? 'listDyn' : 'dictDyn'}($code, ($v) -> ${toAny(v, from.of ?? LType.any)})';
      case LKind.fn:
        final f = tmpName('F'), a = tmpName('A');
        final ps = from.params;
        final call = '$f.call(${[for (var i = 0; i < ps.length; i++) fromAny('$a[$i]', ps[i])].join(', ')})';
        final body = from.returns.isNul ? '{ $call; return null; }' : toAny(call, from.returns);
        return 'Lc.dynFn($code, ${ps.length}, ($f, $a) -> $body)';
      default:
        return 'Lc.toDyn($code)';
    }
  }

  String fromAny(String code, LType to) {
    if (to.isAny) return code;
    if (to.nullable) {
      final v = tmpName('V');
      return 'Lc.<${jb(to)}>optFrom($code, ($v) -> ${fromAny(v, to.nonNull)})';
    }
    switch (to.kind) {
      case LKind.integer:
        return 'Lc.asInt($code)';
      case LKind.number:
        return 'Lc.asNum($code)';
      case LKind.text:
        return 'Lc.asText($code)';
      case LKind.bool:
        return 'Lc.asBool($code)';
      case LKind.list || LKind.dict:
        final list = to.kind == LKind.list, elem = to.of ?? LType.any;
        if (elem.isAny) return list ? 'Lc.asList($code)' : 'Lc.asDict($code)';
        final v = tmpName('V');
        return 'Lc.<${jb(elem)}>${list ? 'listFrom' : 'dictFrom'}($code, ($v) -> ${fromAny(v, elem)})';
      case LKind.fn:
        if (!to.hasShape) return code;
        final d = tmpName('D'), ps = to.params;
        final names = [for (var i = 0; i < ps.length; i++) tmpName('Q')];
        final call = '$d.f.call(new Object[] {${[for (var i = 0; i < ps.length; i++) toAny(names[i], ps[i])].join(', ')}})';
        final body = to.returns.isNul ? '{ $call; }' : fromAny(call, to.returns);
        return 'Lc.<${jb(to)}>asFn($code, ($d) -> (${names.join(', ')}) -> $body)';
      case LKind.record || LKind.enumeration || LKind.variant || LKind.interface || LKind.object:
        return 'Lc.<${jb(to)}>as($code, ${_rawClass(to)}.class, ${_named(to)})';
      case LKind.typeVar:
        return 'Lc.<${jb(to)}>unsafe($code)';
      default:
        return code;
    }
  }

  @override
  String convert(String code, LType from, LType to) {
    if (to.isAny) return toAny(code, from);
    if (from.isAny) return fromAny(code, to);
    if (from.isNul) return nulOf(to);
    if (from.nonNull.kind == LKind.integer && to.nonNull.kind == LKind.number) return from.nullable ? 'Lc.widenOpt($code)' : 'Lc.i2f($code)';
    // 其余的（装箱、拆箱、子类当父类用）Java 自己会做。
    return code;
  }

  // —— 运算 ——

  @override
  String arith(String op, String a, String b) => switch (op) {
    'fadd' => '($a + $b)',
    'fsub' => '($a - $b)',
    'fmul' => '($a * $b)',
    'iadd' || 'isub' || 'imul' || 'idiv' || 'imod' || 'fdiv' || 'fpow' || 'dadd' || 'dsub' || 'dmul' || 'ddiv' || 'dpow' || 'didiv' || 'dmod' => 'Lc.$op($a, $b)',
    _ => unsupported('不认识的运算 $op'),
  };

  @override
  String neg(String op, String a) => '(-$a)';

  static const Map<String, String> _cmpOps = {'lt': '<', 'le': '<=', 'gt': '>', 'ge': '>='};

  @override
  String compare(String kind, String cmp, String a, String b) {
    final o = _cmpOps[cmp]!;
    return switch (kind) {
      'i' || 'f' => '($a $o $b)',
      't' => '(Lc.cmpText($a, $b) $o 0)',
      'd' => '(Lc.dcmp($a, $b) $o 0)',
      _ => '(Lc.cmp($a, $b) $o 0)',
    };
  }

  @override
  String eqSame(LType type, String a, String b) {
    if (!type.nullable) {
      switch (type.kind) {
        case LKind.integer:
          return 'Lc.ieq($a, $b)';
        case LKind.number:
          return 'Lc.feq($a, $b)';
        case LKind.bool:
          return 'Lc.beq($a, $b)';
        default:
          break;
      }
    }
    final k = type.nonNull.kind;
    if (k == LKind.enumeration || k == LKind.object || k == LKind.interface) return 'Lc.same($a, $b)';
    return 'Lc.eq($a, $b)';
  }

  @override
  String sameEnum(String a, String b) => '($a == $b)';
  @override
  String isNullCode(String code, LType type) => type.isNul ? 'true' : 'Lc.isNull($code)';
  @override
  String notCode(String a) => '(!$a)';
  @override
  String logic(String op, String a, String b) => '($a ${op == 'and' ? '&&' : '||'} $b)';

  /// 两边都先写明类型：一边是 Long、一边是 long 时 Java 会把 Long 拆开，里面是空就崩了。
  @override
  String ternary(String cond, String a, String b, LType type) => prim(type) || type.isNul ? '($cond ? $a : $b)' : '($cond ? (${jb(type)}) $a : (${jb(type)}) $b)';

  @override
  String listAt(String list, String index, LType elem) => 'Lc.at($list, $index)';
  @override
  String dictGet(String dict, String key, LType value) => '$dict.get($key)';
  @override
  String dynGet(String of, String key) => 'Lc.dynGet($of, $key)';
  @override
  String listSetCode(String list, String index, String value, LType elem) => 'Lc.setAt($list, $index, $value)';
  @override
  String dictSetCode(String dict, String key, String value, LType valueType) => '$dict.put($key, $value)';
  @override
  String dynSetCode(String of, String key, String value) => 'Lc.dynSet($of, $key, $value)';

  @override
  String funcValue(LTypedSig f) {
    if (f.info.own.isNotEmpty) unsupported('带类型变量的函数「${f.info.name}」不能直接当值用（Java 里要先定下类型）');
    return '((${fnType(f.params, f.returns)}) Main::${funcName(f.info.name)})';
  }

  @override
  String callNamed(LTypedSig f, List<String> args, List<LType> typeArgs) => '${typeArgs.isEmpty ? '' : 'Main.${targs(typeArgs)}'}${funcName(f.info.name)}(${args.join(', ')})';
  @override
  String callValue(String f, List<String> args, LType ft) => '$f.call(${args.join(', ')})';
  @override
  String dynCall(String f, List<String> args) => 'Lc.dynCall(${[f, ...args].join(', ')})';

  static const Set<String> _rt = {
    'listMap', 'listFilter', 'listReduce', 'listFind', 'listEvery', 'listSome', 'listEach', 'toInt', 'parseInt', 'sqrt', 'floor', 'ceil', 'round', //
    'listJoin', 'split', 'substring', 'startsWith', 'endsWith', 'contains', 'indexOf', 'replace', 'trim', 'upper', 'lower', 'repeatText', 'charAt',
    'codePoints', 'listReverse', 'listConcat', 'listSlice', 'listContains', 'listIndexOf', 'range', 'dictValues', 'dictHas', 'toJson', 'fromJson', 'now', 'isNumeric', 'urlDecode',
  };

  @override
  String hostCall(String fn, List<String> args) => 'Lc.$fn(${args.join(', ')})';

  @override
  String rtCall(String fn, List<String> args, List<LType> types, LType ret, LRt e) {
    if (fn == 'dictKeys') return 'Lc.keys(${args.join(', ')})';
    if (!_rt.contains(fn)) unsupported('小库函数「$fn」在 Java 的带类型生成路径里还没有', e);
    return 'Lc.$fn(${args.join(', ')})';
  }

  @override
  String text(String code, LType type) {
    if (type.nullable) return 'Lc.dtext($code)';
    return switch (type.kind) {
      LKind.text => code,
      LKind.integer => 'Lc.itext($code)',
      LKind.number => 'Lc.fmtNum($code)',
      LKind.bool => 'Lc.boolText($code)',
      _ => 'Lc.dtext($code)',
    };
  }

  @override
  String concat(List<String> parts) => parts.length == 1 ? parts.first : '(${parts.join(' + ')})';
  @override
  String logCode(String text) => 'Lc.log($text)';
  @override
  String sizeCode(String code, LType type) => switch (type.kind) {
    LKind.text => 'Lc.textLen($code)',
    LKind.list || LKind.dict => 'Lc.len($code)',
    _ => 'Lc.dynSize($code)',
  };

  /// 用“是不是这种类型”顺手起个名字：空的时候不成立，[def] 只在那时才算（和别的语言一样）。
  @override
  String orElseCode(String code, LType type, String def, LType want) {
    final p = tmpName('P'), cast = prim(want) ? '' : '(${jb(want)}) ';
    return '($code instanceof ${jb(type.nonNull)} $p ? $cast$p : $cast$def)';
  }

  @override
  String mustCode(String code, LType type) => 'Lc.must($code)';
  @override
  String pushCode(String list, String value, LType listType) => '$list.add($value)';
  @override
  String popCode(String list, LType listType) => 'Lc.pop($list)';
  @override
  String dictRemoveCode(String dict, String key, LType dictType) => '$dict.remove($key)';
  @override
  String dynRt(String fn, List<String> args) => 'Lc.dyn${fn[0].toUpperCase()}${fn.substring(1)}(${args.join(', ')})';

  // —— 记录、枚举、变体、类 ——

  @override
  String recordNew(LRecordDecl d, LType type, List<String> values) => 'new ${jb(type)}(${values.join(', ')})';

  /// 记录在 Java 里是 record（不能改）：“复制并改”调它的 w_字段（交回一份改过的）。
  @override
  String recordCopy(LRecordDecl d, LType type, String of, Map<String, String> changes) => [of, for (final e in changes.entries) '.w_${v2Ident(e.key)}(${e.value})'].join();

  @override
  String fieldGet(String of, LType ofType, String name, LField e) => ofType.kind == LKind.record ? '$of.${member(name)}()' : '$of.${member(name)}';

  @override
  String setFieldLine(String obj, LType objType, String name, String value, LTField target) =>
      objType.kind == LKind.record ? assignLine(obj, '$obj.w_${v2Ident(name)}($value)') : assignLine('$obj.${member(name)}', value);

  @override
  String enumCode(LEnumDecl d, String caseName) => '${typeName(d.name)}.c_${v2Ident(caseName)}';
  @override
  String variantNew(LVariantDecl d, LVariantCase c, List<String> args) => 'new ${caseType(d.name, c.name)}(${args.join(', ')})';
  @override
  String isCase(String v, LVariantDecl d, LVariantCase c) => '($v instanceof ${caseType(d.name, c.name)})';
  @override
  String caseField(String v, LVariantDecl d, LVariantCase c, int i) => '((${caseType(d.name, c.name)}) $v).${member(c.fields[i].name)}()';

  @override
  String newObject(LClassInfo c, LType type, List<String> args) => '${typeName(c.name)}.${targs(type.args)}lcNew_${ascii(c.name)}(${args.join(', ')})';
  @override
  String selfCode() => fn.owner == null ? unsupported('这里没有“我自己”') : 'this';
  @override
  String send(String obj, LType objType, String method, List<String> args, LSend e) => '$obj.${member(method)}(${args.join(', ')})';
  @override
  String superCall(String method, List<String> args) => 'super.${member(method)}(${args.join(', ')})';

  @override
  String superCtor(List<String> args) {
    final c = fn.owner!;
    return 'super.lcInit_${ascii(c.decl.parent ?? '')}(${args.join(', ')});\nthis.lcF_${ascii(c.name)}()';
  }

  @override
  String isA(String code, LType type, String cls) {
    if (!w.interfaces.containsKey(cls) && !w.classes.containsKey(cls)) unsupported('没有叫「$cls」的类');
    return '(((Object) $code) instanceof ${typeName(cls)})';
  }

  @override
  String downcast(String code, LType from, LType to) => 'Lc.<${jb(to)}>as($code, ${_rawClass(to)}.class, ${_named(to)})';
}
