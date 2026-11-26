// 读推断原型的程序（docs/blocks-v5-prototypes/types/*/prog.lc，S 表达式写的语法树），翻成 Dart 的语法树。
// 只给 test/lang_typecheck_proto_test.dart 对照原型用；写法见原型的 infer.py。
import 'package:lopicode/lang/lang.dart';

final RegExp _tok = RegExp(r'\s*(;[^\n]*|\(|\)|"[^"]*"|[^\s()";]+)');

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

typedef _L = List<Object>;

/// 几个模块的程序：`(模块 名字 (用 甲 乙) 声明…)` 一个个排下去；声明外面包 `(公开 …)`＝勾了“公开”；`(变量 名 [类型] 初值)`＝模块顶上的变量；
/// `(入口 名字)` 指明入口（没写＝最后一个模块）。只给核心 2 的测试用。
LProgram lcProgram(String src) {
  final mods = <LModule>[];
  String? entry;
  for (final d in lcParse(src).cast<_L>()) {
    if (d[0] == '入口') {
      entry = d[1] as String;
      continue;
    }
    var rest = d.skip(2);
    var uses = const <String>[];
    if (rest.isNotEmpty && rest.first is _L && (rest.first as _L).isNotEmpty && (rest.first as _L)[0] == '用') {
      uses = [...(rest.first as _L).skip(1).cast<String>()];
      rest = rest.skip(1);
    }
    mods.add(_Reader([...rest]).module(name: d[1] as String, uses: uses));
  }
  return LProgram(mods, entry: entry ?? mods.last.name);
}

/// 原型的一个程序 → 模块。
LModule lcModule(String src) => _Reader(lcParse(src)).module();

class _Reader {
  _Reader(this.prog) {
    for (final d in prog.cast<_L>()) {
      if (d[0] == '变体') {
        for (final c in d.skip(2).cast<_L>()) {
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

  static const Map<String, LType> _basic = {'整数': LType.integer, '小数': LType.number, '文字': LType.text, '是否': LType.boolean, '空': LType.nul, '任意': LType.any};

  LType ty(Object s) {
    if (s is String) return _basic[s] ?? LType.ref(s);
    final l = s as _L;
    final h = l[0] as String;
    return switch (h) {
      '可空' => _opt(ty(l[1])),
      '列表' => LType.listOf(ty(l[1])),
      '字典' => LType.dictOf(ty(l[1])),
      '函数' => LType.func([for (final p in l[1] as _L) ty(p), ty(l[2])]),
      '要等函数' => LType.func([for (final p in l[1] as _L) ty(p), ty(l[2])], waits: true),
      '稍后' => LType(LKind.future, of: ty(l[1])),
      _ => LType.ref(h, args: [for (final a in l.skip(1)) ty(a)]),
    };
  }

  static LType _opt(LType t) => LType(t.kind, of: t.of, args: t.args, name: t.name, nullable: t.kind != LKind.any && t.kind != LKind.nul);

  /// 参数：`名`、`(名 类型)`、`(名 类型 默认值)`、`(名 = 默认值)`（没标类型、有默认值）。默认值只能是直接写的值。
  List<LParam> params(Object ps) => [
    for (final p in ps as _L)
      if (p is String)
        LParam(p)
      else if ((p as _L).length == 3 && p[1] == '=')
        LParam(p[0] as String, defaultValue: expr(p[2]) as LLit)
      else
        LParam(p[0] as String, type: ty(p[1]), defaultValue: p.length > 2 ? expr(p[2]) as LLit : null),
  ];

  static const Map<String, String?> _bounds = {'能比较': kBoundComparable};

  LFuncDecl func(_L d, {bool waits = false}) {
    var i = 2;
    final tps = <LTypeParam>[];
    if (d[i] case final _L g when g.isNotEmpty && g[0] == '泛型') {
      for (final x in g.skip(1)) {
        tps.add(x is String ? LTypeParam(x) : LTypeParam((x as _L)[0] as String, bound: _bounds[x[1]] ?? x[1] as String));
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
    void one(_L d, {required bool public}) {
      final name = d.length > 1 && d[1] is String ? d[1] as String : '';
      switch (d[0]) {
        case '公开':
          one(d[1] as _L, public: true);
        case '变量':
          decls.add(d.length == 4 ? LVarDecl(name, expr(d[3]), isPublic: public, type: ty(d[2])) : LVarDecl(name, expr(d[2]), isPublic: public));
        case '记录':
          decls.add(LRecordDecl(name, [for (final f in d.skip(2).cast<_L>()) LTypedField(f[0] as String, ty(f[1]))], isPublic: public));
        case '枚举':
          decls.add(LEnumDecl(name, [...d.skip(2).cast<String>()], isPublic: public));
        case '变体':
          decls.add(
            LVariantDecl(name, [
              for (final c in d.skip(2).cast<_L>()) LVariantCase(c[0] as String, [for (final f in c.skip(1).cast<_L>()) LTypedField(f[0] as String, ty(f[1]))]),
            ], isPublic: public),
          );
        case '接口':
          decls.add(LInterfaceDecl(name, [for (final m in d.skip(2).cast<_L>()) LSignature(m[0] as String, params(m[1]), returns: ty(m[2]), waits: m.length > 3 && m[3] == '要等')], isPublic: public));
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

    for (final d in prog.cast<_L>()) {
      one(d, public: false);
    }
    return LModule(name: name, uses: uses, decls: decls, body: main);
  }

  LClassDecl cls(_L d) {
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
      final l = x as _L;
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

  List<LStmt> stmts(Iterable<Object> list) => [for (final s in list) stmt(s as _L)];
  List<LExpr> exprs(Iterable<Object> list) => [for (final e in list) expr(e)];

  LStmt stmt(_L s) {
    final h = s[0];
    final a = s.sublist(1);
    switch (h) {
      case '设' || '常':
        return a.length == 3 ? LLet(a[0] as String, expr(a[2]), isConst: h == '常', type: ty(a[1])) : LLet(a[0] as String, expr(a[1]), isConst: h == '常');
      case '改':
        return LAssign(LTName(a[0] as String), expr(a[1]));
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
        return LIf([LIfArm(expr(a[0]), stmts((a[1] as _L).skip(1)))], orElse: a.length > 2 ? stmts((a[2] as _L).skip(1)) : const []);
      case '当':
        return LWhile(expr(a[0]), stmts(a.skip(1)));
      case '每个':
        return LForEach(expr(a[1]), a[0] as String, stmts(a.skip(2)));
      case '每对':
        return LForPairs(expr(a[2]), a[0] as String, a[1] as String, stmts(a.skip(3)));
      case '数':
        // 原型里“数 i a b”不含 b；语法树的“从…数到…”含两头，所以数到 b - 1。
        return LForCount(a[0] as String, expr(a[1]), LBinary('-', expr(a[2]), const LLit(1)), const LLit(1), stmts(a.skip(3)));
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
        for (final p in a.cast<_L>()) {
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
        for (final c in a.skip(1).cast<_L>()) {
          if (c[0] == '其余') {
            orElse = stmts(c.skip(1));
          } else {
            arms.add(LMatchArm(c[0] as String, [...(c[1] as _L).cast<String>()], stmts(c.skip(2))));
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
      return errVars.contains(e) ? LField(LName(e), '消息') : LName(e);
    }
    final l = e as _L;
    final h = l[0] as String;
    final a = l.sublist(1);
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
        return LDictLit([for (final x in a.cast<_L>()) LDictEntry(expr(x[0]), expr(x[1]))]);
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
        return LRecordNew(a[0] as String, [for (final f in a.skip(1).cast<_L>()) LFieldInit(f[0] as String, expr(f[1]))]);
      case '改记':
        return LRecordCopy(expr(a[0]), [for (final f in a.skip(1).cast<_L>()) LFieldInit(f[0] as String, expr(f[1]))]);
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
        return spec is String ? LNew(spec, exprs(a.skip(1))) : LNew((spec as _L)[0] as String, exprs(a.skip(1)), typeArgs: [for (final t in spec.skip(1)) ty(t)]);
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
    throw StateError('原型的写法里不认识的式子：$h');
  }
}
