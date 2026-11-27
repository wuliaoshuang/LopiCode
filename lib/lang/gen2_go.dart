/// 规矩版本 2 的生成器·Go（带原生类型，设计 B 第 7、11 节）·类型、转换、式子。语句和声明在 gen2_go_prog.dart。
/// 小库：`lc/lc.go`（rt2_go.dart）。实际落成的映射见 docs/blocks-v5-parts/B-gen-notes.md。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_expr.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

abstract class GoGen2Types extends Gen2 {
  GoGen2Types(super.module, super.r);

  // —— 名字 ——

  String typeName(String name) => 'T_${v2Ident(name)}';

  // “这条线”（lt）：Go 里没有现成的办法知道“我是哪件事”，所以生成的每个函数、方法、匿名函数第一个参数都是 lt，一路传下去。
  // 取消、“一次只让一个做”、格子“正在改”都靠它认（见 rt2_go_host.dart 的 Line）。
  String get line => 'lt';
  String lineParams(String params) => params.isEmpty ? '$line *lc.Line' : '$line *lc.Line, $params';
  String lineArgs(List<String> args) => [line, ...args].join(', ');
  String bodyName(String name) => 'B_${v2Ident(name)}';
  String caseType(String variant, String c) => 'T_${v2Ident(variant)}_${v2Ident(c)}';
  String member(String name) => 'm_${v2Ident(name)}';
  String funcName(String name) => 'f_${v2Ident(name)}';
  String typeVar(String name) => 'P_${v2Ident(name)}';

  @override
  String varCode(V2Var v) {
    if (v.global) return 'g_${v2Ident(v.name)}';
    if (v.info.kind == LVarKind.temp) return 'lcT${v2Ident(v.name)}';
    return v.depth == 0 ? 'v_${v2Ident(v.name)}' : 'v${v.depth}_${v2Ident(v.name)}';
  }

  // —— 类型 ——

  bool isOpen(String? cls) => w.classes[cls]?.decl.isOpen ?? false;

  /// 可空的时候要不要装进指针（整数、小数、文字、是否、记录、枚举、类型变量）；其余的本来就能是 nil。
  bool boxed(LType nn) => const {LKind.integer, LKind.number, LKind.text, LKind.bool, LKind.record, LKind.enumeration, LKind.typeVar}.contains(nn.kind);

  String targs(List<LType> args) => args.isEmpty ? '' : '[${args.map(gt).join(', ')}]';

  /// 类的结构体类型（放字段的那个）。
  String structOf(String cls, List<LType> args) => '${isOpen(cls) ? bodyName(cls) : typeName(cls)}${targs(args)}';

  String gt(LType t) {
    if (t.nullable) {
      final b = gt(t.nonNull);
      return boxed(t.nonNull) ? '*$b' : b;
    }
    switch (t.kind) {
      case LKind.integer:
        return 'int64';
      case LKind.number:
        return 'float64';
      case LKind.text:
        return 'string';
      case LKind.bool:
        return 'bool';
      case LKind.list:
        return '*lc.List[${gt(t.of ?? LType.any)}]';
      case LKind.dict:
        return 'lc.Dict[${gt(t.of ?? LType.any)}]';
      case LKind.future:
        return '*lc.Task[${_taskOf(t.of)}]';
      case LKind.fn:
        if (!t.hasShape) return 'any';
        return 'func(${['*lc.Line', ...t.params.map(gt)].join(', ')})${t.returns.isNul ? '' : ' ${gt(t.returns)}'}';
      case LKind.record || LKind.enumeration || LKind.variant || LKind.interface:
        return '${typeName(t.name ?? '')}${targs(t.args)}';
      case LKind.object:
        final c = w.classes[t.name];
        if (c == null) return 'any';
        return isOpen(c.name) ? '${typeName(c.name)}${targs(t.args)}' : '*${typeName(c.name)}${targs(t.args)}';
      case LKind.typeVar:
        return typeVar(t.name ?? 'T');
      default:
        return 'any';
    }
  }

  @override
  String nulOf(LType type) => type.isNul || type.isNever || type.isHole ? 'nil' : '(${gt(type)})(nil)';

  // —— 字面量 ——

  @override
  String nullLit() => 'nil';
  @override
  String boolLit(bool v) => '$v';
  @override
  String intLit(int v) => 'int64($v)';
  @override
  String floatLit(double v) => 'float64(${langNumber(v, dotZero: true)})';
  @override
  String textLit(String v) => langQuoted(v);

  @override
  String listLit(LType elem, List<String> items) => 'lc.ListOf[${gt(elem)}](${items.join(', ')})';

  @override
  String dictLit(LType value, List<(String, String)> entries) {
    final type = 'lc.Dict[${gt(value)}]';
    final keys = {for (final e in entries) e.$1};
    // 字面量的键重复了 Go 不让编，改成一句句存。
    if (keys.length == entries.length) return '$type{${[for (final e in entries) '${e.$1}: ${e.$2}'].join(', ')}}';
    return 'func() $type { lcD := $type{}; ${[for (final e in entries) 'lcD[${e.$1}] = ${e.$2}'].join('; ')}; return lcD }()';
  }

  // —— 转换 ——

  String _named(LType t) => textLit('「${t.name ?? ''}」');

  /// “任意”取回成 [to] 的检查函数（func(any) T）。
  String checker(LType to) {
    if (!to.nullable) {
      switch (to.kind) {
        case LKind.integer:
          return 'lc.AsInt';
        case LKind.number:
          return 'lc.AsNum';
        case LKind.text:
          return 'lc.AsText';
        case LKind.bool:
          return 'lc.AsBool';
        default:
          break;
      }
    }
    return 'func(lcV any) ${gt(to)} { return ${fromAny('lcV', to)} }';
  }

  String fromAny(String code, LType to) {
    if (to.isAny) return code;
    if (to.nullable) {
      final b = to.nonNull;
      return boxed(b) ? 'lc.OptFrom($code, ${checker(b)})' : 'lc.NilOr($code, ${checker(b)})';
    }
    switch (to.kind) {
      case LKind.integer:
        return 'lc.AsInt($code)';
      case LKind.number:
        return 'lc.AsNum($code)';
      case LKind.text:
        return 'lc.AsText($code)';
      case LKind.bool:
        return 'lc.AsBool($code)';
      case LKind.fn:
        return to.hasShape ? 'lc.As[${gt(to)}]($code, "函数")' : code;
      case LKind.list:
        return (to.of ?? LType.any).isAny ? 'lc.AsList($code)' : 'lc.ListFrom($code, ${checker(to.of!)})';
      case LKind.dict:
        return (to.of ?? LType.any).isAny ? 'lc.AsDict($code)' : 'lc.DictFrom($code, ${checker(to.of!)})';
      case LKind.record || LKind.enumeration || LKind.variant || LKind.interface || LKind.object:
        return 'lc.As[${gt(to)}]($code, ${_named(to)})';
      case LKind.typeVar:
        return 'lc.As[${gt(to)}]($code, "这种类型的值")';
      default:
        return code;
    }
  }

  String toAny(String code, LType from) {
    if (!from.nullable) {
      if (from.kind == LKind.integer) return 'lc.IntDyn($code)';
      if (from.kind == LKind.number || from.kind == LKind.text || from.kind == LKind.bool) return 'any($code)';
    }
    return 'lc.ToDyn($code)';
  }

  /// 两个都不可空的类型之间。
  String _plain(String code, LType from, LType to) {
    if (from.kind == LKind.integer && to.kind == LKind.number) return 'float64($code)';
    if (from.isNamed && to.isNamed && from.name != to.name && gt(from) != gt(to)) return '${gt(to)}($code)';
    return code;
  }

  @override
  String convert(String code, LType from, LType to) {
    if (to.isAny) return toAny(code, from);
    if (from.isAny) return fromAny(code, to);
    if (_fnMismatch(from, to)) {
      // 函数当另一种样子的函数用（比如返回“列表”的当返回“任意”的）：Go 里函数类型要一模一样，包一层。
      final f = tmpName('F'), qs = [for (final _ in to.params) tmpName('Q')];
      final call = '$f(${lineArgs([for (var i = 0; i < qs.length; i++) conv(qs[i], to.params[i], from.params[i])])})';
      // 不返回东西的当“返回任意”的用：做完交回空。
      final body = to.returns.isNul
          ? call
          : from.returns.isNul
          ? '$call; return nil'
          : 'return ${conv(call, from.returns, to.returns)}';
      return 'func($f ${gt(from)}) ${gt(to)} { return func(${lineParams([for (var i = 0; i < qs.length; i++) '${qs[i]} ${gt(to.params[i])}'].join(', '))})${to.returns.isNul ? '' : ' ${gt(to.returns)}'} { $body } }($code)';
    }
    final fb = from.nonNull, tb = to.nonNull;
    if (from.isNul) return nulOf(to);
    if (!from.nullable) {
      final inner = _plain(code, fb, tb);
      return to.nullable && boxed(tb) ? 'lc.Box($inner)' : inner;
    }
    if (!to.nullable) return _plain(boxed(fb) ? '(*$code)' : code, fb, tb);
    if (fb == tb) return code;
    if (fb.kind == LKind.integer && tb.kind == LKind.number) return 'lc.WidenOpt($code)';
    if (fb.isNamed && tb.isNamed && gt(from) != gt(to)) return 'lc.Up[${gt(to)}]($code)';
    return code;
  }

  bool _fnMismatch(LType from, LType to) =>
      !from.nullable && !to.nullable && from.kind == LKind.fn && to.kind == LKind.fn && from.hasShape && to.hasShape && from.params.length == to.params.length && gt(from) != gt(to);

  // —— 运算 ——

  static final RegExp _constFloat = RegExp(r'^\(?-?float64\([-+0-9.eE]+\)\)?$');

  static const Map<String, String> _ops = {
    'iadd': 'IAdd', 'isub': 'ISub', 'imul': 'IMul', 'idiv': 'IDiv', 'imod': 'IMod', 'fdiv': 'FDiv', 'fpow': 'FPow', //
    'dadd': 'DAdd', 'dsub': 'DSub', 'dmul': 'DMul', 'ddiv': 'DDiv', 'dpow': 'DPow', 'didiv': 'DIDiv', 'dmod': 'DMod',
  };

  @override
  String arith(String op, String a, String b) => switch (op) {
    // 两边都是写死的小数：Go 会在编译时算，算出界（1e308 * 10.5）直接编译不过。交给小库在运行时算（得到无穷大，和别的语言一样）。
    'fadd' || 'fsub' || 'fmul' when _constFloat.hasMatch(a) && _constFloat.hasMatch(b) =>
      'lc.F${op == 'fadd'
          ? 'Add'
          : op == 'fsub'
          ? 'Sub'
          : 'Mul'}($a, $b)',
    'fadd' => '($a + $b)',
    'fsub' => '($a - $b)',
    'fmul' => '($a * $b)',
    _ => 'lc.${_ops[op] ?? unsupported('不认识的运算 $op')}($a, $b)',
  };

  @override
  String neg(String op, String a) => '(-$a)';

  static const Map<String, String> _cmpOps = {'lt': '<', 'le': '<=', 'gt': '>', 'ge': '>='};

  @override
  String compare(String kind, String cmp, String a, String b) {
    final o = _cmpOps[cmp]!;
    return switch (kind) {
      'i' || 'f' || 't' => '($a $o $b)',
      'd' => '(lc.DCmp($a, $b) $o 0)',
      _ => '(lc.Cmp($a, $b) $o 0)',
    };
  }

  static const Set<LKind> _comparable = {LKind.integer, LKind.number, LKind.text, LKind.bool, LKind.enumeration};

  @override
  String eqSame(LType type, String a, String b) {
    final n = type.nonNull;
    if (type.isAny) return 'lc.Eq($a, $b)';
    if (_comparable.contains(n.kind)) return type.nullable ? 'lc.OptEq($a, $b)' : '($a == $b)';
    if (n.kind == LKind.object || n.kind == LKind.interface) return '($a == $b)';
    if (n.kind == LKind.record && !type.nullable) return '$a.LcEq($b)';
    return 'lc.Eq($a, $b)';
  }

  @override
  String sameEnum(String a, String b) => '($a == $b)';
  @override
  String isNullCode(String code, LType type) => type.isNul ? 'true' : '($code == nil)';
  @override
  String notCode(String a) => '(!$a)';
  @override
  String logic(String op, String a, String b) => '($a ${op == 'and' ? '&&' : '||'} $b)';
  @override
  String ternary(String cond, String a, String b, LType type) => 'func() ${gt(type)} { if $cond { return $a }; return $b }()';

  /// 取出来的结果（“项的类型或空”）要不要另装指针。
  bool _boxResult(LType elem) => !elem.nullable && boxed(elem);

  @override
  String listAt(String list, String index, LType elem) => '$list.At($index)';
  @override
  String dictGet(String dict, String key, LType value) => 'lc.${_boxResult(value) ? 'Get' : 'GetNil'}($dict, $key)';
  @override
  String dynGet(String of, String key) => 'lc.DynGet($of, $key)';
  @override
  String listSetCode(String list, String index, String value, LType elem) => '$list.Set($index, $value)';
  @override
  String dictSetCode(String dict, String key, String value, LType valueType) => '$dict[$key] = $value';
  @override
  String dynSetCode(String of, String key, String value) => 'lc.DynSet($of, $key, $value)';

  @override
  String funcValue(LTypedSig f) {
    if (f.info.own.isNotEmpty) unsupported('带类型变量的函数「${f.info.name}」不能直接当值用（Go 里要先定下类型）');
    return funcName(f.info.name);
  }

  @override
  String callNamed(LTypedSig f, List<String> args, List<LType> typeArgs) => '${funcName(f.info.name)}${targs(typeArgs)}(${lineArgs(args)})';
  @override
  String callValue(String f, List<String> args, LType ft) => '$f(${lineArgs(args)})';
  @override
  String dynCall(String f, List<String> args) => 'lc.DynCall(${lineArgs([f, ...args])})';

  static const Map<String, String> _rt = {
    'listMap': 'Map', 'listFilter': 'Filter', 'listReduce': 'Reduce', 'listEvery': 'Every', 'listSome': 'Any', 'listEach': 'Each', //
    'toInt': 'ToInt', 'parseInt': 'ParseInt', 'sqrt': 'Sqrt', 'floor': 'Floor', 'ceil': 'Ceil', 'round': 'Round', 'listJoin': 'Join',
    'split': 'Split', 'substring': 'Substring', 'startsWith': 'StartsWith', 'endsWith': 'EndsWith', 'contains': 'Contains',
    'indexOf': 'IndexOf', 'replace': 'Replace', 'trim': 'Trim', 'upper': 'Upper', 'lower': 'Lower', 'repeatText': 'RepeatText',
    'charAt': 'CharAt', 'codePoints': 'CodePoints', 'listReverse': 'Reverse', 'listConcat': 'Concat', 'listSlice': 'Slice',
    'listContains': 'ListContains', 'listIndexOf': 'ListIndexOf', 'range': 'Range', 'dictKeys': 'DictKeys', 'dictValues': 'DictValues',
    'dictHas': 'DictHas', 'toJson': 'ToJson', 'fromJson': 'FromJson', 'now': 'Now', 'isNumeric': 'IsNumeric', 'urlDecode': 'UrlDecode',
    'isType': 'IsType', 'toNumber': 'ToNumber', 'dictMerge': 'DictMerge', 'abs': 'Abs', 'max': 'MaxOf', 'min': 'MinOf', 'random': 'Random',
    'copy': 'Copy', 'template': 'Template', 'toBool': 'ToBool', 'listInsert': 'Insert', 'listRemove': 'RemoveAt', 'listSort': 'Sort',
    'dictPairs': 'DictPairs', 'awaitMax': 'WaitMax', 'awaitAll': 'WaitAll', 'awaitAny': 'WaitAny', 'cancel': 'Cancel', 'cancelled': 'Cancelled',
    'lockEnter': 'LockEnter', 'lockLeave': 'LockLeave',
  };

  // 这些小库函数要知道“这条线”：收函数的（要把 lt 接着传给那个函数）和“稍后的结果”那几个。
  static const Set<String> _rtLine = {'listMap', 'listFilter', 'listReduce', 'listEvery', 'listSome', 'listEach', 'awaitMax', 'awaitAll', 'awaitAny', 'cancelled', 'lockEnter', 'lockLeave'};

  @override
  String nativeCall(String ident, List<String> args) => '$ident(${args.join(', ')})';
  @override
  String hostCall(String fn, List<String> args) => 'lc.${fn[0].toUpperCase()}${fn.substring(1)}(${_hostLine.contains(fn) ? lineArgs(args) : args.join(', ')})';

  // 这几个宿主接口要知道“这条线”：会等的（被取消了要叫得醒）、收函数的、认“谁正在改”的。
  static const Set<String> _hostLine = {'hostSleep', 'hostServe', 'hostFetch', 'storeUpdate'};

  // “稍后的结果”里放什么：不返回东西的函数放 any（里面是 nil）。
  String _taskOf(LType? of) => of == null || of.isNul ? 'any' : gt(of);
  @override
  String spawnCode(String f, LType ft) => ft.returns.isNul ? 'lc.Spawn($line, func($line *lc.Line) any { $f($line); return nil })' : 'lc.Spawn($line, $f)';
  @override
  String waitCode(String task, LType of) => 'lc.Wait($line, $task)';

  @override
  String rtCall(String fn, List<String> args, List<LType> types, LType ret, LRt e) {
    // “任意”进来的：数字那三个、排序没法按类型挑实现，换成运行时再查的那一份。
    if (const {'abs', 'max', 'min'}.contains(fn) && ret.isAny) return 'lc.Dyn${_rt[fn]!.replaceAll('Of', '')}(${args.join(', ')})';
    if (fn == 'listSort' && (ret.of?.isAny ?? true)) return 'lc.DynSort(${args.join(', ')})';
    if (fn == 'copy') return 'lc.Copy[${gt(types[0])}](${args.join(', ')})'; // 放进来的是“空”的时候 Go 自己推不出类型
    if (fn == 'listFind') return 'lc.${_boxResult(ret.nonNull) ? 'Find' : 'FindNil'}(${lineArgs(args)})';
    final name = _rt[fn] ?? unsupported('小库函数「$fn」在 Go 的带类型生成路径里还没有', e);
    return 'lc.$name(${_rtLine.contains(fn) ? lineArgs(args) : args.join(', ')})';
  }

  @override
  String text(String code, LType type) {
    if (type.nullable) return 'lc.DText($code)';
    return switch (type.kind) {
      LKind.text => code,
      LKind.integer => 'lc.IntText($code)',
      LKind.number => 'lc.FmtNum($code)',
      LKind.bool => 'lc.BoolText($code)',
      _ => 'lc.DText($code)',
    };
  }

  @override
  String concat(List<String> parts) => parts.length == 1 ? parts.first : '(${parts.join(' + ')})';
  @override
  String logCode(String text) => 'lc.Log($text)';
  @override
  String sizeCode(String code, LType type) => switch (type.kind) {
    LKind.text => 'lc.TextLen($code)',
    LKind.list => '$code.Len()',
    LKind.dict => 'lc.DictLen($code)',
    _ => 'lc.DynSize($code)',
  };

  @override
  String orElseCode(String code, LType type, String def, LType want) {
    final deref = boxed(type.nonNull) && !want.nullable;
    return 'func() ${gt(want)} { if lcP := $code; lcP != nil { return ${deref ? '*lcP' : 'lcP'} }; return $def }()';
  }

  @override
  String mustCode(String code, LType type) => !type.isAny && boxed(type.nonNull) ? 'lc.Must($code)' : 'lc.MustNil($code)';
  @override
  String pushCode(String list, String value, LType listType) => '$list.Push($value)';
  @override
  String popCode(String list, LType listType) => 'lc.${_boxResult(listType.of ?? LType.any) ? 'Pop' : 'PopNil'}($list)';
  @override
  String dictRemoveCode(String dict, String key, LType dictType) => 'delete($dict, $key)';
  @override
  String dynRt(String fn, List<String> args) => 'lc.Dyn${fn[0].toUpperCase()}${fn.substring(1)}(${args.join(', ')})';

  // —— 记录、枚举、变体、类 ——

  @override
  String recordNew(LRecordDecl d, LType type, List<String> values) => '${gt(type)}{${[for (var i = 0; i < d.fields.length; i++) '${member(d.fields[i].name)}: ${values[i]}'].join(', ')}}';

  @override
  String recordCopy(LRecordDecl d, LType type, String of, Map<String, String> changes) {
    final g = gt(type);
    return 'func(lcR $g) $g { ${[for (final e in changes.entries) 'lcR.${member(e.key)} = ${e.value}'].join('; ')}; return lcR }($of)';
  }

  /// 取 / 改对象的字段：能被继承的类的变量是接口，要先换成“体”。
  String _fieldOf(String of, LType ofType, String name, bool onThis) {
    if (onThis) return 'o.${member(name)}';
    final owner = fieldOwner(ofType, name);
    if (ofType.kind == LKind.object && isOpen(ofType.name) && owner != null) return '$of.lcAs_${v2Ident(owner.name)}().${member(name)}';
    return '$of.${member(name)}';
  }

  @override
  String fieldGet(String of, LType ofType, String name, LField e) => _fieldOf(of, ofType, name, e.of is LThis);
  @override
  String setFieldLine(String obj, LType objType, String name, String value, LTField target) => assignLine(_fieldOf(obj, objType, name, target.of is LThis), value);
  @override
  String enumCode(LEnumDecl d, String caseName) => '${typeName(d.name)}_c_${v2Ident(caseName)}';
  @override
  String variantNew(LVariantDecl d, LVariantCase c, List<String> args) => '${typeName(d.name)}(${caseType(d.name, c.name)}{${args.join(', ')}})';
  @override
  String isCase(String v, LVariantDecl d, LVariantCase c) => 'lc.Is[${caseType(d.name, c.name)}]($v)';
  @override
  String caseField(String v, LVariantDecl d, LVariantCase c, int i) => '$v.(${caseType(d.name, c.name)}).${member(c.fields[i].name)}';

  @override
  String newObject(LClassInfo c, LType type, List<String> args) {
    final made = 'New_${v2Ident(c.name)}${targs(type.args)}(${lineArgs(args)})';
    return isOpen(c.name) ? '${gt(type)}($made)' : made;
  }

  @override
  String selfCode() {
    final c = fn.owner ?? unsupported('这里没有“我自己”');
    if (!isOpen(c.name)) return 'o';
    return c.decl.parent == null ? 'o.self' : 'o.self.(${gt(selfType)})';
  }

  @override
  String send(String obj, LType objType, String method, List<String> args, LSend e) => '$obj.${member(method)}(${lineArgs(args)})';

  String _parentBody() {
    final c = fn.owner!;
    return bodyName(c.decl.parent ?? '');
  }

  @override
  String superCall(String method, List<String> args) => 'o.${_parentBody()}.${member(method)}(${lineArgs(args)})';
  @override
  String superCtor(List<String> args) => 'func() { o.${_parentBody()}.lcInit(${lineArgs(args)}); o.lcF_${v2Ident(fn.owner!.name)}($line) }()';

  String _classType(String cls, LType like, LNode? node) {
    if (w.interfaces.containsKey(cls)) return typeName(cls);
    final c = w.classes[cls] ?? unsupported('没有叫「$cls」的类', node);
    if (c.typeVars.isEmpty) return gt(LType(LKind.object, name: cls));
    if (like.nonNull.name == cls) return gt(like.nonNull);
    unsupported('“是不是「$cls」”：带类型变量的类在 Go 里要知道具体类型才能判断');
  }

  @override
  String isA(String code, LType type, String cls) => 'lc.Is[${_classType(cls, type, null)}]($code)';
  @override
  String downcast(String code, LType from, LType to) => 'lc.As[${gt(to)}]($code, ${_named(to)})';
}
