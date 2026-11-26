/// 语法树的文字写法（S 表达式）→ Dart 的语法树。库的模块文件（`*.lc`）、库积木的“原地展开”模板都用这种写法；
/// 格式说明见 docs/blocks-v5-parts/library-format.md 第 4 节。最早是读推断原型用的（test/support/proto_lc.dart，现在只是转出这个文件）。
///
/// 读坏内容会抛异常（写法不对、括号不配对）；产品里读存盘文件一律走 [lcTryProgram] / [LcReader.guard]，它们把异常换成一句话。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

final RegExp _tok = RegExp(r'\s*(;[^\n]*|\(|\)|"(?:[^"\\]|\\.)*"|[^\s()";]+)');

/// 切成一层层括号。文字（双引号里的）原样留着，**不做转义**：写了反斜杠就是反斜杠（老样例靠这个）。
List<Object> lcParse(String src) {
  final toks = [
    for (final m in _tok.allMatches(src))
      if (!m.group(1)!.startsWith(';')) m.group(1)!,
  ];
  var pos = 0;
  Object rd() {
    final t = toks[pos++];
    if (t != '(') return t;
    final out = <Object>[];
    while (toks[pos] != ')') {
      out.add(rd());
    }
    pos++;
    return out;
  }

  final out = <Object>[];
  while (pos < toks.length) {
    out.add(rd());
  }
  return out;
}

/// 读出来的一层括号。
typedef LcList = List<Object>;

/// 读一个程序，读不了给一句原因（不抛异常）。
({LProgram? program, String? problem}) lcTryProgram(String src) {
  try {
    return (program: lcProgram(src), problem: null);
  } on Object catch (e) {
    return (program: null, problem: lcProblemText(e));
  }
}

/// 读的时候抛出来的东西 → 给人看的一句话。
String lcProblemText(Object e) => e is StateError ? e.message : '写法不对（括号不配对，或者某一句少了东西）';

/// 几个模块的程序：`(模块 名字 (用 甲 乙) 声明…)` 一个个排下去；声明外面包 `(公开 …)`＝勾了“公开”；`(变量 名 [类型] 初值)`＝模块顶上的变量；
/// `(入口 名字)` 指明入口（没写＝最后一个模块）。只给核心 2 的测试用。
LProgram lcProgram(String src) {
  final mods = <LModule>[];
  String? entry;
  for (final d in lcParse(src).cast<LcList>()) {
    if (d[0] == '入口') {
      entry = d[1] as String;
      continue;
    }
    var rest = d.skip(2);
    var uses = const <String>[];
    if (rest.isNotEmpty && rest.first is LcList && (rest.first as LcList).isNotEmpty && (rest.first as LcList)[0] == '用') {
      uses = [...(rest.first as LcList).skip(1).cast<String>()];
      rest = rest.skip(1);
    }
    mods.add(LcReader([...rest]).module(name: d[1] as String, uses: uses));
  }
  return LProgram(mods, entry: entry ?? mods.last.name);
}

/// 原型的一个程序 → 模块。
LModule lcModule(String src) => LcReader(lcParse(src)).module();

class LcReader {
  LcReader(this.prog) {
    for (final d in prog.cast<LcList>()) {
      if (d[0] == '变体') {
        for (final c in d.skip(2).cast<LcList>()) {
          caseOf[c[0] as String] = d[1] as String;
        }
      }
    }
  }
  final List<Object> prog;
  final Map<String, String> caseOf = {};

  /// 正在读的“出错”那一节接到的错误变量（见 stmt 里的“试”）。
  final Set<String> errVars = {};
  var _n = 0;

  /// 模板用的钩子（库积木的“原地展开”，见 lib_expand.dart）：不认识的式子 / 语句先问它，它给了就用它给的。
  LExpr? Function(String head, List<Object> args)? exprHole;
  List<LStmt>? Function(String head, List<Object> args)? stmtHole;

  /// 给了就把这一段里新建的名字（设、常、循环变量）换成它给的新名字，读的时候跟着换（模板展开时防撞名）。
  String Function(String name)? freshName;
  final Map<String, String> renames = {};
  String _decl(Object name) {
    final n = name as String;
    final fresh = freshName;
    return fresh == null ? n : renames[n] ??= fresh(n);
  }

  String _use(Object name) => renames[name] ?? name as String;

  static const Map<String, LType> _basic = {'整数': LType.integer, '小数': LType.number, '文字': LType.text, '是否': LType.boolean, '空': LType.nul, '任意': LType.any};

  LType ty(Object s) {
    if (s is String) return _basic[s] ?? LType.ref(s);
    final l = s as LcList;
    final h = l[0] as String;
    return switch (h) {
      '可空' => _opt(ty(l[1])),
      '列表' => LType.listOf(ty(l[1])),
      '字典' => LType.dictOf(ty(l[1])),
      '函数' => LType.func([for (final p in l[1] as LcList) ty(p), ty(l[2])]),
      '要等函数' => LType.func([for (final p in l[1] as LcList) ty(p), ty(l[2])], waits: true),
      '稍后' => LType(LKind.future, of: ty(l[1])),
      _ => LType.ref(h, args: [for (final a in l.skip(1)) ty(a)]),
    };
  }

  static LType _opt(LType t) => LType(t.kind, of: t.of, args: t.args, name: t.name, nullable: t.kind != LKind.any && t.kind != LKind.nul);

  /// 参数：`名`、`(名 类型)`、`(名 类型 默认值)`、`(名 = 默认值)`（没标类型、有默认值）。默认值只能是直接写的值。
  List<LParam> params(Object ps) => [
    for (final p in ps as LcList)
      if (p is String)
        LParam(_use(p))
      else if ((p as LcList).length == 3 && p[1] == '=')
        LParam(_use(p[0]), defaultValue: expr(p[2]) as LLit)
      else
        LParam(_use(p[0]), type: ty(p[1]), defaultValue: p.length > 2 ? expr(p[2]) as LLit : null),
  ];

  static const Map<String, String?> _bounds = {'能比较': kBoundComparable};

  LFuncDecl func(LcList d, {bool waits = false}) {
    var i = 2;
    final tps = <LTypeParam>[];
    if (d[i] case final LcList g when g.isNotEmpty && g[0] == '泛型') {
      for (final x in g.skip(1)) {
        tps.add(x is String ? LTypeParam(x) : LTypeParam((x as LcList)[0] as String, bound: _bounds[x[1]] ?? x[1] as String));
      }
      i++;
    }
    final ps = params(d[i++]);
    LType? ret;
    if (i < d.length && d[i] == '->') {
      ret = ty(d[i + 1]);
      i += 2;
    }
    return LFuncDecl(d[1] as String, ps, stmts(d.skip(i)), typeParams: tps, type: ret, waits: waits);
  }

  LModule module({String name = '', List<String> uses = const []}) {
    final decls = <LDecl>[];
    var main = <LStmt>[];
    void one(LcList d, {required bool public}) {
      final name = d.length > 1 && d[1] is String ? d[1] as String : '';
      switch (d[0]) {
        case '公开':
          one(d[1] as LcList, public: true);
        case '变量':
          decls.add(d.length == 4 ? LVarDecl(name, expr(d[3]), isPublic: public, type: ty(d[2])) : LVarDecl(name, expr(d[2]), isPublic: public));
        case '记录':
          decls.add(LRecordDecl(name, [for (final f in d.skip(2).cast<LcList>()) LTypedField(f[0] as String, ty(f[1]))], isPublic: public));
        case '枚举':
          decls.add(LEnumDecl(name, [...d.skip(2).cast<String>()], isPublic: public));
        case '变体':
          decls.add(
            LVariantDecl(name, [
              for (final c in d.skip(2).cast<LcList>()) LVariantCase(c[0] as String, [for (final f in c.skip(1).cast<LcList>()) LTypedField(f[0] as String, ty(f[1]))]),
            ], isPublic: public),
          );
        case '接口':
          decls.add(
            LInterfaceDecl(name, [for (final m in d.skip(2).cast<LcList>()) LSignature(m[0] as String, params(m[1]), returns: ty(m[2]), waits: m.length > 3 && m[3] == '要等')], isPublic: public),
          );
        case '别名':
          decls.add(LAliasDecl(name, ty(d[2]), isPublic: public));
        case '函数' || '要等函数':
          // 要等函数＝里面有要等的事（等一会儿、开服务、调别的要等的函数…），写的人明着标。
          final f = func(d, waits: d[0] == '要等函数');
          decls.add(LFuncDecl(f.name, f.params, f.body, isPublic: public, typeParams: f.typeParams, type: f.type, waits: f.waits));
        case '类':
          final c = cls(d);
          decls.add(LClassDecl(c.name, parent: c.parent, interfaces: c.interfaces, fields: c.fields, ctor: c.ctor, methods: c.methods, typeParams: c.typeParams, isOpen: c.isOpen, isPublic: public));
        case '宿主':
          // (宿主 名字 (参数…) -> 返回类型)：宿主函数的签名。
          decls.add(LNativeDecl(name, params(d[2]), type: d.length > 4 ? ty(d[4]) : LType.nul));
        case '主':
          main = stmts(d.skip(1));
      }
    }

    for (final d in prog.cast<LcList>()) {
      one(d, public: false);
    }
    return LModule(name: name, uses: uses, decls: decls, body: main);
  }

  LClassDecl cls(LcList d) {
    var open = false;
    String? parent;
    var impl = <String>[];
    var tps = <LTypeParam>[];
    final fields = <LFieldDecl>[];
    final methods = <LMethodDecl>[];
    LFuncDecl? ctor;
    for (final x in d.skip(2)) {
      if (x == '可继承') {
        open = true;
        continue;
      }
      final l = x as LcList;
      switch (l[0]) {
        case '泛型':
          tps = [for (final v in l.skip(1)) LTypeParam(v as String)];
        case '继承':
          parent = l[1] as String;
        case '实现':
          impl = [...l.skip(1).cast<String>()];
        case '字段' || '内部字段' || '类字段' || '内部类字段':
          // 内部＝只有这个类和子类能用；类字段＝属于类本身。
          final kind = l[0] as String;
          fields.add(LFieldDecl(l[1] as String, l.length > 3 ? expr(l[3]) : null, type: ty(l[2]), isPrivate: kind.startsWith('内部'), isStatic: kind.endsWith('类字段')));
        case '创建':
          ctor = LFuncDecl('创建', params(l[1]), stmts(l.skip(2)));
        case '方法' || '要等方法':
          methods.add(LMethodDecl(func(l, waits: l[0] == '要等方法')));
        case '类方法':
          methods.add(LMethodDecl(func(l), isStatic: true));
      }
    }
    return LClassDecl(d[1] as String, parent: parent, interfaces: impl, fields: fields, ctor: ctor, methods: methods, typeParams: tps, isOpen: open);
  }

  List<LStmt> stmts(Iterable<Object> list) {
    final out = <LStmt>[];
    for (final s in list) {
      final l = s as LcList;
      final got = l.isNotEmpty && l[0] is String ? stmtHole?.call(l[0] as String, l.sublist(1)) : null;
      if (got != null) {
        out.addAll(got);
      } else {
        out.add(stmt(l));
      }
    }
    return out;
  }

  List<LExpr> exprs(Iterable<Object> list) => [for (final e in list) expr(e)];

  LStmt stmt(LcList s) {
    final h = s[0];
    final a = s.sublist(1);
    switch (h) {
      case '设' || '常':
        final value = expr(a.last);
        return a.length == 3 ? LLet(_decl(a[0]), value, isConst: h == '常', type: ty(a[1])) : LLet(_decl(a[0]), value, isConst: h == '常');
      case '改':
        return LAssign(LTName(_use(a[0])), expr(a[1]));
      case '加项':
        return LExprStmt(LRt('listPush', exprs(a)));
      case '删末项':
        return LExprStmt(LRt('listPop', exprs(a)));
      case '存' || '改项':
        return LAssign(LTIndex(expr(a[0]), expr(a[1])), expr(a[2]));
      case '删键':
        return LExprStmt(LRt('dictRemove', exprs(a)));
      case '改字段':
        return LAssign(LTField(expr(a[0]), a[1] as String), expr(a[2]));
      case '如果':
        return LIf([LIfArm(expr(a[0]), stmts((a[1] as LcList).skip(1)))], orElse: a.length > 2 ? stmts((a[2] as LcList).skip(1)) : const []);
      case '当':
        return LWhile(expr(a[0]), stmts(a.skip(1)));
      case '每个':
        final list = expr(a[1]);
        return LForEach(list, _decl(a[0]), stmts(a.skip(2)));
      case '每对':
        final dict = expr(a[2]);
        return LForPairs(dict, _decl(a[0]), _decl(a[1]), stmts(a.skip(3)));
      case '数':
        // 原型里“数 i a b”不含 b；语法树的“从…数到…”含两头，所以数到 b - 1。
        final from = expr(a[1]), to = expr(a[2]);
        return LForCount(_decl(a[0]), from, LBinary('-', to, const LLit(1)), const LLit(1), stmts(a.skip(3)));
      case '跳出':
        return const LBreak();
      case '继续':
        return const LContinue();
      case '返回':
        return LReturn(a.isEmpty ? null : expr(a[0]));
      case '抛出':
        return LThrow(expr(a[0]));
      case '试':
        // 老写法 (出错 e …)：原型是按“接到一句话”写的；版本 2 接到的是错误对象，所以这一节里读 e 都翻成“e 的消息”。
        // 新写法 (出错时 种类 名字 …)：种类、名字不要就写 _；(不接)＝一节“出错时”都没有（只有“最后”）。
        var body = <LStmt>[], onError = <LStmt>[], last = <LStmt>[];
        String? name;
        List<LCatch>? handlers;
        for (final p in a.cast<LcList>()) {
          if (p[0] == '做') {
            body = stmts(p.skip(1));
          } else if (p[0] == '出错') {
            name = p[1] as String;
            final added = errVars.add(name);
            onError = stmts(p.skip(2));
            if (added) errVars.remove(name);
          } else if (p[0] == '出错时') {
            String? opt(Object x) => x == '_' ? null : x as String;
            (handlers ??= []).add(LCatch(stmts(p.skip(3)), kind: opt(p[1]), name: opt(p[2])));
          } else if (p[0] == '不接') {
            handlers ??= [];
          } else {
            last = stmts(p.skip(1));
          }
        }
        return LTry(body, errorName: name, onError: onError, handlers: handlers, finallyBody: last);
      case '打印':
        return LExprStmt(LRt('log', exprs(a)));
      case '做':
        return LExprStmt(expr(a[0]));
      case '父创建':
        return LExprStmt(LSuperSend.ctor(exprs(a)));
      case '分情况':
        final arms = <LMatchArm>[];
        List<LStmt>? orElse;
        for (final c in a.skip(1).cast<LcList>()) {
          if (c[0] == '其余') {
            orElse = stmts(c.skip(1));
          } else {
            arms.add(LMatchArm(c[0] as String, [...(c[1] as LcList).cast<String>()], stmts(c.skip(2))));
          }
        }
        return LMatch(expr(a[0]), arms, orElse: orElse);
      default:
        return LExprStmt(expr(s));
    }
  }

  static final RegExp _intRe = RegExp(r'^-?\d+$');
  static final RegExp _fltRe = RegExp(r'^-?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$');
  static const Map<String, String> _bin = {'+': '+', '-': '-', '*': '*', '/': '/', '整除': '//', '余': '%', '<': '<', '>': '>', '<=': '<=', '>=': '>=', '==': '==', '!=': '!='};
  static const Map<String, String> _rt = {
    '连': 'join',
    '文': 'toText',
    '取整': 'toInt',
    '拼': 'listJoin',
    '长': 'size',
    '文长': 'size',
    '有键': 'dictHas',
    '键们': 'dictKeys',
    '或空': 'orElse',
    '必有': 'must',
    '切': 'split',
    '截': 'substring',
    '开头是': 'startsWith',
    '解析整数': 'parseInt',
    '码点们': 'codePoints',
    '是数字': 'isNumeric',
    '转JSON': 'toJson',
    '网址解码': 'urlDecode',
    '是类': 'isType',
    '转数': 'toNumber',
    '合并': 'dictMerge',
    '找': 'listFind',
    '接': 'listConcat',
    '列有': 'listContains',
    '换': 'replace',
    '小写': 'lower',
    '位置': 'indexOf',
    '读JSON': 'fromJson',
  };

  LExpr expr(Object e) {
    if (e is String) {
      if (e.startsWith('"')) return LLit(e.substring(1, e.length - 1));
      if (_intRe.hasMatch(e)) return LLit(int.parse(e));
      if (_fltRe.hasMatch(e)) return LLit(double.parse(e));
      if (e == '空') return const LLit(null);
      if (e == '是' || e == '否') return LLit(e == '是');
      return errVars.contains(e) ? LField(LName(e), '消息') : LName(_use(e));
    }
    final l = e as LcList;
    final h = l[0] as String;
    final a = l.sublist(1);
    final hole = exprHole?.call(h, a);
    if (hole != null) return hole;
    final bin = _bin[h];
    if (bin != null) return a.skip(2).fold(LBinary(bin, expr(a[0]), expr(a[1])), (acc, x) => LBinary(bin, acc, expr(x)));
    if (h.startsWith('任') && _bin.containsKey(h.substring(1))) {
      return LBinary(_bin[h.substring(1)]!, LAscribe(expr(a[0]), LType.any), LAscribe(expr(a[1]), LType.any));
    }
    final rt = _rt[h];
    if (rt != null) return LRt(rt, exprs(a));
    switch (h) {
      case '且' || '或':
        return a.skip(2).fold(LLogic(h == '且' ? 'and' : 'or', expr(a[0]), expr(a[1])), (acc, x) => LLogic(h == '且' ? 'and' : 'or', acc, expr(x)));
      case '非':
        return LUnary('not', expr(a[0]));
      case '是空' || '非空':
        return LBinary(h == '是空' ? '==' : '!=', expr(a[0]), const LLit(null));
      case '标':
        return LAscribe(expr(a[1]), ty(a[0]));
      case '转':
        return LCast(expr(a[1]), ty(a[0]));
      case '列':
        return LListLit(exprs(a));
      case '典':
        return LDictLit([for (final x in a.cast<LcList>()) LDictEntry(expr(x[0]), expr(x[1]))]);
      case '项' || '取':
        return LIndex(expr(a[0]), expr(a[1]));
      case '试算':
        final name = '错${_n++}';
        return LCall(
          LLambda(const [], [
            LTry(
              [
                LReturn(LRt('toText', [expr(a[0])])),
              ],
              errorName: name,
              onError: [LReturn(LField(LName(name), '消息'))],
            ),
          ]),
          const [],
        );
      case 'λ' || '要等λ':
        return LLambda.short(params(a[0]), expr(a[1]), waits: h == '要等λ');
      case 'λ块' || '要等λ块':
        return LLambda(params(a[0]), stmts(a.skip(1)), waits: h == '要等λ块');
      case '开始做':
        // (开始做 f)：马上开始做 f（不带参数的函数），结果是“稍后的结果”。(开始做块 语句…) 是把语句包成要等的匿名函数。
        return LSpawn([LReturn(LCall(expr(a[0]), const []))]);
      case '开始做块':
        return LSpawn([LReturn(LCall(LLambda(const [], stmts(a), waits: true), const []))]);
      case '等':
        return LAwait(expr(a[0]));
      case '调':
        final f = a[0];
        final args = exprs(a.skip(1));
        if (f == '映射') return LRt('listMap', args);
        if (f == '筛选') return LRt('listFilter', args);
        if (f == '归并') return LRt('listReduce', [args[0], args[2], args[1]]);
        return LCall(expr(f), args);
      case '新记':
        return LRecordNew(a[0] as String, [for (final f in a.skip(1).cast<LcList>()) LFieldInit(f[0] as String, expr(f[1]))]);
      case '改记':
        return LRecordCopy(expr(a[0]), [for (final f in a.skip(1).cast<LcList>()) LFieldInit(f[0] as String, expr(f[1]))]);
      case '.':
        return LField(expr(a[0]), a[1] as String);
      case '这':
        return const LThis();
      case '枚':
        return LEnumValue(a[0] as String, a[1] as String);
      case '造':
        return LVariantNew(caseOf[a[0]] ?? '', a[0] as String, exprs(a.skip(1)));
      case '新':
        final spec = a[0];
        return spec is String ? LNew(spec, exprs(a.skip(1))) : LNew((spec as LcList)[0] as String, exprs(a.skip(1)), typeArgs: [for (final t in spec.skip(1)) ty(t)]);
      case '发':
        return LSend(expr(a[0]), a[1] as String, exprs(a.skip(2)));
      case '父':
        return LSuperSend(a[0] as String, exprs(a.skip(1)));
      case '是':
        return LIsA(expr(a[1]), a[0] as String);
      case '宿':
        return LNative(a[0] as String, exprs(a.skip(1)));
      case '库':
        // (库 名字 参数…)：直接按名字调小库函数（没有专门写法的那些）。
        return LRt(a[0] as String, exprs(a.skip(1)));
    }
    throw StateError('不认识的式子：$h');
  }
}
