// 规矩版本 2 的类型检查里，推断原型没做、这一段新做的部分：T13 / T14 / T15 / T17 / T18、一键修的数据、运行时检查点、
// 边界上的转换、每个运算用哪个小函数、类型的存盘、规矩版本字段、G10 的桥。原型已有的部分见 lang_typecheck_proto_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_type_bridge.dart';

import 'support/proto_lc.dart';

LTypeResult _check(String src) => checkModuleTypes(lcModule(src));
List<String> _said(LTypeResult r) => [for (final i in r.issues) '$i'];
LTypeIssue _one(LTypeResult r, String code) => r.issues.singleWhere((i) => i.code == code);

void main() {
  group('新做的规则', () {
    test('规则表：T01–T28 都在，级别照设计（T12 提醒，T13、T14 警告，其余是错）', () {
      // 核心 2 加了 T19–T21（抛出 / 接住的不是错误、撞了内置错误的名字、这一节“出错时”永远轮不到）
      // 和 T22–T28（类与接口：内部字段、接口当类用、继承绕圈、类本身的和对象的用混、默认值、调父类的创建时、重名）。
      expect(kTypeRules.keys.toList(), [for (var i = 1; i <= 28; i++) 'T${'$i'.padLeft(2, '0')}']);
      for (final r in kTypeRules.values) {
        final want = r.code == 'T12' ? LTypeLevel.hint : (r.code == 'T13' || r.code == 'T14' ? LTypeLevel.warning : LTypeLevel.error);
        expect(r.level, want, reason: r.code);
        expect(r.title, isNotEmpty);
        expect(r.advice, isNotEmpty);
      }
    });

    test('T13：给别人用的函数没标全是警告，不拦生成；标全了不报', () {
      const m = LModule(
        decls: [
          LFuncDecl('加', [LParam('a'), LParam('b', type: LType.integer)], [LReturn(LBinary('+', LName('a'), LName('b')))], isPublic: true),
          LFuncDecl('减', [LParam('a', type: LType.integer)], [LReturn(LName('a'))], isPublic: true, type: LType.integer),
          LFuncDecl('自己用', [LParam('a')], [LReturn(LName('a'))]),
        ],
      );
      final r = checkModuleTypes(m);
      expect(_said(r), ['T13 加：「加」是给别人用的，参数「a」、返回值还没有标类型']);
      expect(r.hasErrors, isFalse);
      expect(r.issues.single.level, LTypeLevel.warning);
    });

    test('T14：标成“任意”的变量里放了带类型的列表，再往里加东西——改不到原来那份', () {
      final r = _check('(主 (设 xs (列 1 2)) (设 装 任意 xs) (加项 装 3) (设 别的 任意 5) (设 活 任意 (转 任意 xs)))');
      expect(_said(r), ['T14 主：「装」是“任意”，里面是原来那个列表（或字典）的一份快照，往里加东西改不到原来那份']);
      expect(r.hasErrors, isFalse);
    });

    test('T14 不乱报：本来就是“任意”的东西（比如读 JSON 得到的）往里加不报', () {
      final r = _check('(函数 f ((d 任意)) (加项 d 1) (存 d "k" 2)) (主 (做 (调 f (列))))');
      expect(_said(r), isEmpty);
    });

    test('T15：永远成不了的“当成”是错；可能成的不报，并记一处运行时检查', () {
      final r = _check('(类 猫 (创建 ())) (类 狗 (创建 ())) (主 (设 n 1) (设 a (转 文字 n)) (设 c (新 猫)) (设 d (转 狗 c)) (设 x 任意 n) (设 y (转 整数 x)))');
      expect(_said(r), ['T15 主：这个值是整数，永远当不成文字', 'T15 主：这个值是猫，永远当不成狗']);
      expect([for (final c in r.checks) '$c'], contains('anyToType→整数'));
    });

    test('T17：继承没勾“可以被继承”的类', () {
      final r = _check('(类 动物 (创建 ())) (类 狗 (继承 动物) (创建 ()))');
      expect(_said(r), ['T17 狗：「狗」继承了「动物」，但「动物」没有勾“可以被继承”']);
    });

    test('T18：重写的方法和父类的对不上（参数个数、参数类型、返回的东西）', () {
      final r = _check('''
(类 动物 可继承 (创建 ())
  (方法 叫 ((次 整数)) -> 文字 (返回 "…"))
  (方法 吃 ((东西 文字)) -> 文字 (返回 东西))
  (方法 腿 () -> 整数 (返回 4)))
(类 狗 (继承 动物) (创建 ())
  (方法 叫 () -> 文字 (返回 "汪"))
  (方法 吃 ((东西 整数)) -> 文字 (返回 "骨头"))
  (方法 腿 () -> 文字 (返回 "四")))''');
      expect(_said(r), ['T18 狗：「狗」的「叫」和「动物」的对不上：父类的收 1 个参数，这里收 0 个', 'T18 狗：「狗」的「吃」和「动物」的对不上：第 1 个参数父类的是文字，这里是整数', 'T18 狗：「狗」的「腿」和「动物」的对不上：父类的返回整数，这里返回文字']);
    });

    test('T16：整数写得太大；正好在边上的不报', () {
      expect(_said(_check('(主 (设 a 9007199254740991) (设 b -9007199254740991))')), isEmpty);
      expect(_said(_check('(主 (设 a 9007199254740992))')), ['T16 主：9007199254740992 太大了，整数最大只能到 9007199254740991']);
    });
  });

  group('一键修（只出数据）', () {
    test('设计 6.2 的七种都能给出来，目标指到要改的那个节点', () {
      LFix fix(String src, String code) => _one(_check(src), code).fixes.first;
      expect(fix('(函数 f ((s 文字)) (返回 s)) (主 (做 (调 f 1)))', 'T01').kind, LFixKind.wrapToText);
      expect(fix('(函数 f ((n 整数)) (返回 n)) (主 (做 (调 f 1.5)))', 'T01').kind, LFixKind.wrapToInt);
      expect(fix('(函数 f ((n 整数)) (返回 n)) (主 (做 (调 f "12")))', 'T01').kind, LFixKind.wrapParseInt);
      expect(fix('(函数 f ((n 整数)) (返回 n)) (主 (设 v (可空 整数) 空) (做 (调 f v)))', 'T02').kind, LFixKind.wrapOrElse);
      expect(fix('(主 (设 n 1) (如果 n (那么 (打印 "x"))))', 'T09').kind, LFixKind.compareNotZero);
      final cases = fix('(枚举 灯 红 黄 绿) (主 (设 l (枚 灯 红)) (分情况 l (红 () (打印 "红"))))', 'T03');
      expect(cases.kind, LFixKind.addMatchCases);
      expect(cases.params['cases'], ['黄', '绿']);
      expect(cases.target, isA<LMatch>());
      final fields = fix('(记录 点 (x 小数) (y 小数)) (主 (设 p (新记 点 (x 1.0))))', 'T04');
      expect(fields.kind, LFixKind.addRecordFields);
      expect(fields.params['fields'], ['y']);
      expect(fields.target, isA<LRecordNew>());
    });

    test('问题能定位到是哪个参数、哪个节点；节点自己带着位置就用它的，没带用包着它的那句的', () {
      const arg = LLit(
        'abc',
        src: LSrc(script: 'r1', block: 'b7', slot: 'n'),
      );
      const call = LCall(LName('f'), [arg], src: LSrc(script: 'r1', block: 'b7'));
      const loose = LLit('x');
      const m = LModule(
        decls: [
          LFuncDecl('f', [LParam('n', type: LType.integer)], [LReturn(LName('n'))]),
        ],
        body: [
          LExprStmt(
            call,
            src: LSrc(script: 'r1', block: 'b7'),
          ),
          LExprStmt(
            LCall(LName('f'), [loose]),
            src: LSrc(script: 'r1', block: 'b9'),
          ),
        ],
      );
      final r = checkModuleTypes(m);
      expect(r.issues.length, 2);
      expect(r.issues[0].node, same(arg));
      expect(r.issues[0].argIndex, 0);
      expect('${r.issues[0].src}', 'r1 › b7 › n');
      expect(r.issues[0].fixes.single.target, same(arg));
      expect(r.issues[1].node, same(loose));
      expect('${r.issues[1].src}', 'r1 › b9');
    });
  });

  group('给生成器的东西', () {
    test('每个式子的类型、每个运算用哪个小函数、要查的地方', () {
      final m = lcModule('''
(主
  (设 a 7) (设 b 2) (设 p 1.5)
  (设 s (+ a b)) (设 q (/ a b)) (设 d (整除 a b)) (设 m (余 a b)) (设 t (* a p))
  (设 xs (列 1 2 3)) (设 第一 (项 xs 0))
  (设 字 (典 ("a" 1))) (设 也许 (取 字 "a"))
  (设 硬 (必有 也许))
  (设 整 (取整 p))
  (设 随便 任意 a) (设 和 (+ 随便 1)))''');
      final r = checkModuleTypes(m);
      expect(r.issues, isEmpty);
      LExpr init(String name) => (m.body.whereType<LLet>().firstWhere((l) => l.name == name)).value;
      expect(
        {
          for (final n in ['s', 'q', 'd', 'm', 't', '第一', '也许', '和']) n: r.opOf(init(n)),
        },
        {'s': 'iadd', 'q': 'fdiv', 'd': 'idiv', 'm': 'imod', 't': 'fmul', '第一': 'listAt', '也许': 'dictGet', '和': 'dadd'},
      );
      expect(r.typeOf(init('s'))!.show(), '整数');
      expect(r.typeOf(init('q'))!.show(), '小数');
      expect(r.typeOf(init('也许'))!.show(), '整数?');
      expect(r.typeOf(init('硬'))!.show(), '整数');
      expect(r.variable('主', '和')!.type, LType.any);
      final kinds = {for (final c in r.checks) c.kind};
      expect(kinds, {LCheckKind.intOverflow, LCheckKind.divideByZero, LCheckKind.listIndex, LCheckKind.must, LCheckKind.floatToInt, LCheckKind.dynamicArith});
      // 整数乘小数：整数那边要先变成小数——放进变量时也一样（变量最后是小数，放进来的是整数）。
      final mul = init('t') as LBinary;
      expect(r.typeOf(mul.l)!.show(), '整数');
      expect('${r.coercionOf(mul.l)}', 'widen:整数→小数');
      expect(r.coercionOf(mul.r), isNull);
      expect(r.coercionOf(init('随便')), isNull, reason: '整数放进任意不用转');
      expect(r.shared, isEmpty);
    });

    test('同一个节点对象在树里出现两次会被点出来（结果是按节点对象记的，这样的树生成器不能直接用）', () {
      const one = LLit(1);
      final r = checkModuleTypes(const LModule(body: [LLet('a', one), LLet('b', LBinary('+', one, LLit(2.5)))]));
      expect(r.shared, [same(one)]);
      // 两个一模一样的空列表（const 写的是同一个对象）分在两句里：各是各的，不会串。
      const empty = LListLit([]);
      final r2 = checkModuleTypes(
        const LModule(
          body: [
            LLet('甲', empty),
            LLet('乙', empty),
            LExprStmt(LRt('listPush', [LName('甲'), LLit('x')])),
            LExprStmt(LRt('listPush', [LName('乙'), LLit(true)])),
          ],
        ),
      );
      expect(r2.variable('主', '甲')!.type.show(), '列表〈文字〉');
      expect(r2.variable('主', '乙')!.type.show(), '列表〈是否〉');
    });

    test('边界上的转换：整数 → 小数、任意 → 确定类型（要查）、列表 → 任意（快照）、任意 → 列表〈整数〉（逐项查）、变可空', () {
      final m = lcModule('''
(函数 要小数 ((x 小数)) (返回 x))
(函数 要整数 ((x 整数)) (返回 x))
(函数 要任意 ((x 任意)) (返回 x))
(函数 要整数们 ((x (列表 整数))) (返回 x))
(函数 要可空 ((x (可空 整数))) (返回 x))
(主
  (设 n 1) (设 xs (列 1 2)) (设 啥 任意 n)
  (做 (调 要小数 n)) (做 (调 要整数 啥)) (做 (调 要任意 xs)) (做 (调 要整数们 啥)) (做 (调 要可空 n))
  (设 慢慢变 1) (改 慢慢变 2.5))''');
      final r = checkModuleTypes(m);
      expect(r.issues, isEmpty);
      final calls = [for (final s in m.body.whereType<LExprStmt>()) (s.expr as LCall).args.single];
      expect([for (final a in calls) '${r.coercionOf(a)}'], ['widen:整数→小数', 'check:任意→整数', 'snapshot:列表〈整数〉→任意', 'checkEach:任意→列表〈整数〉', 'toNullable:整数→整数?']);
      expect([for (final c in r.checks) '$c'], containsAll(['anyToType→整数', 'anyToContainer→列表〈整数〉']));
      // 变量后来变宽成小数：一开始放进去的那个整数也要变成小数。
      final first = m.body.whereType<LLet>().firstWhere((l) => l.name == '慢慢变').value;
      expect('${r.coercionOf(first)}', 'widen:整数→小数');
    });

    test('泛型调用把类型变量定成了什么；匿名函数里的变量记在它自己那一层', () {
      final m = lcModule('(主 (设 xs (列 1 2 3)) (设 ys (调 映射 xs (λ块 (x) (设 两倍 (* x 2)) (返回 (连 两倍))))))');
      final r = checkModuleTypes(m);
      final call = m.body.whereType<LLet>().last.value as LRt;
      expect({for (final e in r.typeArgsOf(call)!.entries) e.key: e.value.show()}, {'T': '整数', 'U': '文字'});
      final scope = r.lambdaScope(call.args[1] as LLambda)!;
      expect(r.variable(scope, '两倍')!.type, LType.integer);
      expect(r.variable(scope, 'x')!.kind, LVarKind.param);
      expect(r.typeOf(call.args[1])!.show(), '(整数) → 文字');
    });

    test('一段段单独的脚本：各有各的变量，看得见声明和宿主给的变量，问题记在脚本名下', () {
      final r = checkTypes(
        decls: [
          const LFuncDecl('加一', [LParam('n', type: LType.integer)], [LReturn(LBinary('+', LName('n'), LLit(1)))]),
        ],
        scripts: [
          const LTypeScript(
            'r1',
            [
              LLet('a', LCall(LName('加一'), [LName('次数')])),
            ],
            vars: {'次数': LType.integer},
          ),
          const LTypeScript('r2', [
            LLet('a', LCall(LName('加一'), [LLit('x')])),
          ]),
        ],
        outer: const {'req': LType.any},
      );
      expect(_said(r), ['T01 r2：「加一」的第 1 个参数要整数，放进来的是文字']);
      expect(r.variable('r1', 'a')!.type, LType.integer);
    });

    test('比大小：整数和小数能比（整数那边先变小数），文字和数字不能比；“等于”两边是什么都不报，交给严格的 eq', () {
      final m = lcModule('(主 (设 a (< 1 2.5)) (设 b (== 1 "1")) (设 c (== 1 1.0)))');
      final r = checkModuleTypes(m);
      expect(r.issues, isEmpty);
      LExpr init(String name) => m.body.whereType<LLet>().firstWhere((l) => l.name == name).value;
      expect(r.opOf(init('a')), 'flt');
      expect('${r.coercionOf((init('a') as LBinary).l)}', 'widen:整数→小数');
      expect(r.opOf(init('b')), 'eq');
      expect(_said(_check('(主 (设 a (< 1 "2")))')).single, startsWith('T06 '));
    });

    test('任何输入都不抛异常：空模块、不认识的名字、套得很深', () {
      expect(checkModuleTypes(const LModule()).issues, isEmpty);
      LExpr deep = const LLit(1);
      for (var i = 0; i < 300; i++) {
        deep = LBinary('+', deep, const LLit(1));
      }
      final r = checkModuleTypes(LModule(body: [LLet('x', deep), const LExprStmt(LNew('没有', [])), const LExprStmt(LSend(LName('x'), '跳', [])), const LMatch(LName('x'), [])]));
      expect(r.variable('主', 'x')!.type, LType.integer);
      expect(r.issues.map((i) => i.code).toSet(), {'T08', 'T01'});
    });
  });

  group('类型的写法和存盘', () {
    test('14 种类型给人看的写法（不出现 int64、List<String> 这类）', () {
      const samples = <(LType, String)>[
        (LType.integer, '整数'),
        (LType.number, '小数'),
        (LType.text, '文字'),
        (LType.boolean, '是否'),
        (LType.nul, '空'),
        (LType(LKind.integer, nullable: true), '整数?'),
        (LType.listOf(LType.text), '列表〈文字〉'),
        (LType.dictOf(LType.integer), '字典〈整数〉'),
        (LType(LKind.record, name: '用户'), '用户'),
        (LType(LKind.enumeration, name: '灯'), '灯'),
        (LType(LKind.variant, name: '形状'), '形状'),
        (LType(LKind.object, name: '栈', args: [LType.integer]), '栈〈整数〉'),
        (LType(LKind.interface, name: '会叫'), '会叫'),
        (LType.func([LType.integer, LType.text, LType.boolean]), '(整数, 文字) → 是否'),
        (LType.func([LType.nul], nullable: true), '(() → 空)?'),
        (LType.variable('T'), 'T'),
        (LType.any, '任意'),
        (LType.never, '永不'),
        (LType(LKind.future, of: LType.text), '稍后的结果〈文字〉'),
      ];
      for (final (t, s) in samples) {
        expect(t.show(), s);
        expect(lTypeFromJson(lTypeToJson(t)), t, reason: s);
      }
    });

    test('老的写法照样：toString 还是“数字”“（可以是空）”，老的合并算法没变', () {
      expect('${LType.number}', '数字');
      expect('${const LType(LKind.list, of: LType.number)}', '列表〈数字〉');
      expect('${const LType(LKind.number, nullable: true)}', '数字（可以是空）');
      expect(LType.number.join(LType.text), LType.any);
      expect(LType.nul.join(LType.text), const LType(LKind.text, nullable: true));
    });

    test('存盘：函数“要不要等”的位置留着；老写法的 of 能读；坏的东西当“任意”，不抛异常', () {
      const f = LType.func([LType.integer, LType.text], waits: true);
      expect(lTypeToJson(f), {
        'k': 'fn',
        'args': [
          {'k': 'int'},
          {'k': 'text'},
        ],
        'waits': true,
      });
      expect(lTypeFromJson(lTypeToJson(f)).waits, isTrue);
      expect(
        lTypeFromJson({
          'k': 'list',
          'of': {'k': 'number'},
        }),
        const LType(LKind.list, of: LType.number),
      );
      expect(lTypeToJson(const LType.dictOf(LType.integer))['args'], [
        {'k': 'text'},
        {'k': 'int'},
      ]);
      for (final bad in [
        null,
        3,
        'x',
        <String, dynamic>{},
        {'k': '没有这种'},
        {'k': 'list', 'args': 'x'},
      ]) {
        expect(lTypeFromJson(bad), anyOf(LType.any, const LType(LKind.list)));
      }
    });
  });

  group('规矩版本', () {
    test('旧文件没有这个字段＝版本 1；版本 1 存盘不写这个字段（和以前一个字节不差）；版本 2 写、读回来还是 2', () {
      final old = BeDocument();
      expect(old.rules, 1);
      expect(old.toJson().containsKey(kLangRulesField), isFalse);
      expect(BeDocument.parse(old.encode()).doc.rules, 1);
      final strict = BeDocument(rules: kLangRulesStrict);
      expect(strict.toJson()[kLangRulesField], 2);
      expect(BeDocument.parse(strict.encode()).doc.rules, 2);
      expect(strict.clone().rules, 2);
    });

    test('坏的值当 1；比现在认识的还新的原样留着', () {
      for (final bad in ['2', 0, -1, 1.5, null, true]) {
        expect(langRulesFromJson(bad), 1);
      }
      expect(langRulesFromJson(7), 7);
      expect(BeDocument(rules: 0).rules, 1);
      expect(langRulesStrict(1), isFalse);
      expect(langRulesStrict(2), isTrue);
    });

    test('新建的入口读开关；两种取值下新建出来的文档都能存、能读回、内容一样', () {
      expect(backendStarterDocument('样本').rules, kLangRulesForNewDocs);
      for (final v in [kLangRulesLoose, kLangRulesStrict]) {
        final doc = backendStarterDocument('样本', rules: v);
        expect(doc.rules, v);
        final back = BeDocument.parse(doc.encode());
        expect(back.note, isNull);
        expect(back.doc.rules, v);
        expect(back.doc.encode(), doc.encode());
      }
      final a = backendStarterDocument('样本', rules: kLangRulesLoose).toJson(), b = backendStarterDocument('样本', rules: kLangRulesStrict).toJson()..remove(kLangRulesField);
      expect('$b', '$a');
    });
  });

  test('G10 的桥：槽的四种类型和语言核心的类型来回换', () {
    expect(lcToLType(LcType.number), LType.number);
    expect(lcToLType(LcType.text), LType.text);
    expect(lcToLType(LcType.boolean), LType.boolean);
    expect(lcToLType(LcType.any), LType.any);
    expect(lcToLType('没有这种'), LType.any);
    expect(lTypeToLc(LType.integer), LcType.number);
    expect(lTypeToLc(LType.number), LcType.number);
    expect(lTypeToLc(const LType.listOf(LType.integer)), LcType.any);
    expect(lTypeToLc(const LType(LKind.text, nullable: true)), LcType.any);
  });
}
