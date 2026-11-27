// 核心 3：“要不要等”自动推（typecheck_wait.dart）——各种形状都要推对；放错地方的在检查阶段拦下（T29、T30、T31），
// 能一键修的修完就没有问题了。真编译真跑的在 test/lang_gen2_waits_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/type_fix.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/proto_lc.dart';

const String _host = '''
(宿主 time.sleep ((毫秒 整数)) -> 空)
(宿主 store.update ((名 文字) (改法 (函数 (任意) 任意))) -> 任意)
''';

LTypeResult _check(String src) {
  final r = checkModuleTypes(lcModule('$_host $src'));
  return r;
}

/// 没有错；[yes] 都要等、[no] 都不等。
void _waits(String src, {List<String> yes = const [], List<String> no = const [], bool? escaped}) {
  final r = _check(src);
  expect([for (final i in r.errors) '${i.code} ${i.message}'], isEmpty, reason: src);
  for (final k in yes) {
    expect(r.waitsOf(k), isTrue, reason: '「$k」应该要等\n$src');
  }
  for (final k in no) {
    expect(r.waitsOf(k), isFalse, reason: '「$k」不应该要等\n$src');
  }
  if (escaped != null) expect(r.waitEscaped, escaped, reason: src);
}

/// 只报这一条规则，提示语里有这些字；五种语言都不生成。返回那些问题。
List<LTypeIssue> _only(String src, String code, List<String> parts) {
  final module = lcModule('$_host $src');
  final errors = checkModuleTypes(module).errors;
  final said = [for (final i in errors) '${i.code} ${i.message}'];
  expect(said, isNotEmpty, reason: src);
  expect({for (final i in errors) i.code}, {code}, reason: said.join('\n'));
  for (final p in parts) {
    expect(said.any((s) => s.contains(p)), isTrue, reason: '提示语里要有「$p」：\n${said.join('\n')}');
  }
  for (final l in kGen2Languages) {
    expect(() => gen2ProgramFiles(l, LProgram([module], entry: module.name)), throwsA(isA<LangUnsupported>()), reason: l);
  }
  return errors;
}

/// 用第一个一键修改完以后再查：没有错了。
void _fixed(String src, String code, LFixKind kind) {
  final module = lcModule('$_host $src');
  final r = checkModuleTypes(module);
  final issue = r.errors.firstWhere((i) => i.code == code);
  final fix = issue.fixes.firstWhere((f) => f.kind == kind, orElse: () => fail('「${issue.message}」没有给 ${kind.name} 这种一键修'));
  final next = lApplyFix(module, fix, types: r);
  expect(next, isNotNull, reason: '一键修没改成');
  final after = checkModuleTypes(next!);
  expect([for (final i in after.errors) '${i.code} ${i.message}'], isEmpty, reason: '修完还有错');
}

void main() {
  group('推：', () {
    test('直接用了要等的宿主接口；调它的也要等；没关系的不等', () {
      _waits(
        '(函数 睡 () (做 (宿 time.sleep 1))) (函数 外 () (做 (调 睡))) (函数 再外 () -> 整数 (做 (调 外)) (返回 1)) (函数 无关 () -> 整数 (返回 2)) (主 (做 (调 再外)) (打印 (调 无关)))',
        yes: ['睡', '外', '再外'],
        no: ['无关'],
        escaped: false,
      );
    });

    test('递归、互相调用：转几圈就不变了', () {
      _waits(
        '(函数 甲 ((n 整数)) -> 整数 (如果 (<= n 0) (那么 (返回 0))) (返回 (调 乙 (- n 1))))'
        '(函数 乙 ((n 整数)) -> 整数 (做 (宿 time.sleep 1)) (返回 (调 甲 n)))'
        '(函数 丙 ((n 整数)) -> 整数 (如果 (<= n 0) (那么 (返回 0))) (返回 (调 丁 (- n 1))))'
        '(函数 丁 ((n 整数)) -> 整数 (返回 (调 丙 n)))'
        '(函数 自己 ((n 整数)) -> 整数 (如果 (<= n 0) (那么 (做 (宿 time.sleep 1)) (返回 0))) (返回 (调 自己 (- n 1))))'
        '(主 (打印 (调 甲 2)) (打印 (调 丙 2)) (打印 (调 自己 2)))',
        yes: ['甲', '乙', '自己'],
        no: ['丙', '丁'],
      );
    });

    test('匿名函数里的事算匿名函数自己的；调它才要等', () {
      const src =
          '(函数 造 () -> (要等函数 () 整数) (返回 (λ块 () (做 (宿 time.sleep 1)) (返回 1))))'
          '(函数 用 () -> 整数 (设 f (调 造)) (返回 (调 f)))'
          '(主 (打印 (调 用)))';
      _waits(src, yes: ['用'], no: ['造'], escaped: false);
      final module = lcModule('$_host $src');
      final r = checkModuleTypes(module);
      final lambdas = <LLambda>[];
      void walk(LExpr e) {
        if (e is LLambda) lambdas.add(e);
        lExprChildrenForTest(e).forEach(walk);
      }

      for (final d in module.decls.whereType<LFuncDecl>()) {
        for (final s in d.body) {
          if (s is LReturn && s.value != null) walk(s.value!);
        }
      }
      expect(lambdas, hasLength(1));
      expect(r.waitsOf(r.lambdaScope(lambdas.single)!), isTrue);
    });

    test('“开始做”里的事算它自己的：开始做不用等，“等”它才要等', () {
      _waits(
        '(函数 只开始 () -> (稍后 整数) (返回 (开始做块 (做 (宿 time.sleep 1)) (返回 1))))'
        '(函数 等它 () -> 整数 (返回 (等 (调 只开始))))'
        '(主 (打印 (调 等它)))',
        yes: ['等它'],
        no: ['只开始'],
      );
    });

    test('方法：子类重写的要等，父类那个也算要等；实现的要等，接口那个也算要等', () {
      const src =
          '(类 动物 可继承 (方法 叫 () -> 文字 (返回 "…")) (方法 名 () -> 文字 (返回 "动物")))'
          '(类 狗 (继承 动物) (方法 叫 () -> 文字 (做 (宿 time.sleep 1)) (返回 "汪")))'
          '(接口 会跑 (跑 () 整数))'
          '(类 马 (实现 会跑) (方法 跑 () -> 整数 (做 (宿 time.sleep 1)) (返回 3)))'
          '(类 龟 (实现 会跑) (方法 跑 () -> 整数 (返回 1)))'
          '(函数 让它叫 ((a 动物)) -> 文字 (返回 (发 a 叫)))'
          '(函数 让它报名 ((a 动物)) -> 文字 (返回 (发 a 名)))'
          '(函数 让它跑 ((r 会跑)) -> 整数 (返回 (发 r 跑)))'
          '(函数 让龟跑 ((r 龟)) -> 整数 (返回 (发 r 跑)))'
          '(主 (打印 (调 让它叫 (新 狗))) (打印 (调 让它报名 (新 狗))) (打印 (调 让它跑 (新 马))) (打印 (调 让龟跑 (新 龟))))';
      _waits(src, yes: ['狗.叫', '动物.叫', '马.跑', '让它叫', '让它跑'], no: ['动物.名', '龟.跑', '让它报名', '让龟跑']);
      final r = _check(src);
      expect(r.ifaceWaits('会跑', '跑'), isTrue);
    });

    test('跨模块：别的模块里的函数要等，这边调它的也要等', () {
      final p = lcProgram(
        '(模块 工具 (宿主 time.sleep ((毫秒 整数)) -> 空) (公开 (函数 慢慢来 () -> 整数 (做 (宿 time.sleep 1)) (返回 7))) (公开 (函数 快 () -> 整数 (返回 8))))'
        '(模块 入口 (用 工具) (函数 用慢的 () -> 整数 (返回 (调 慢慢来))) (函数 用快的 () -> 整数 (返回 (调 快))) (主 (打印 (调 用慢的)) (打印 (调 用快的))))',
      );
      final linked = linkProgram(p);
      expect(linked.issues, isEmpty);
      final r = checkModuleTypes(linked.module!);
      expect(r.errors, isEmpty);
      expect(r.waitsOf('用慢的'), isTrue);
      expect(r.waitsOf('用快的'), isFalse);
    });

    test('明着标的照样算数：标了“要等函数”，里面没有要等的事也按要等', () {
      _waits('(要等函数 标了 () -> 整数 (返回 1)) (函数 调它 () -> 整数 (返回 (调 标了))) (主 (打印 (调 调它)))', yes: ['标了', '调它']);
    });

    test('函数值：要等的函数放进没标的地方以后，调没标的函数值都当成可能要等', () {
      // 没有要等的函数值乱跑：调没标的函数值不用等。
      _waits('(函数 用 ((f (函数 (整数) 整数))) -> 整数 (返回 (调 f 1))) (主 (打印 (调 用 (λ ((x 整数)) (+ x 1)))))', no: ['用'], escaped: false);
      // 有一个要等的匿名函数放进了没标的参数：从此调没标的函数值都可能要等。
      _waits(
        '(函数 用 ((f (函数 (整数) 整数))) -> 整数 (返回 (调 f 1)))'
        '(主 (打印 (调 用 (λ块 ((x 整数)) (做 (宿 time.sleep 1)) (返回 (+ x 1))))))',
        yes: ['用'],
        escaped: true,
      );
      // 参数标了“要等函数”：要等的放进去不算乱跑。
      _waits(
        '(函数 用 ((f (要等函数 (整数) 整数))) -> 整数 (返回 (调 f 1)))'
        '(函数 别的 ((g (函数 (整数) 整数))) -> 整数 (返回 (调 g 1)))'
        '(主 (打印 (调 用 (λ块 ((x 整数)) (做 (宿 time.sleep 1)) (返回 (+ x 1))))) (打印 (调 别的 (λ ((x 整数)) x))))',
        yes: ['用'],
        no: ['别的'],
        escaped: false,
      );
    });

    test('小库里要等的：等最多、等全部、等最先的、一次只让一个做', () {
      _waits(
        '(函数 甲 ((t (稍后 整数))) -> 整数 (返回 (等最多 t 10)))'
        '(函数 乙 ((ts (列表 (稍后 整数)))) -> (列表 整数) (返回 (等全部 ts)))'
        '(函数 丙 ((ts (列表 (稍后 整数)))) -> 整数 (返回 (等最先 ts)))'
        '(函数 丁 () (一次一个 "账本" (打印 "里面")))'
        '(函数 戊 ((t (稍后 整数))) -> 是否 (取消 t) (返回 (被取消了吗)))'
        '(主 (做 (调 丁)))',
        yes: ['甲', '乙', '丙', '丁'],
        no: ['戊'],
      );
    });
  });

  group('拦：', () {
    test('T29 “创建时”里不能等；能一键改成“开始做”', () {
      const src = '(函数 睡 () (做 (宿 time.sleep 1))) (类 甲 (字段 n 整数 0) (创建 () (做 (调 睡)) (改字段 (这) n 1))) (主 (打印 (. (新 甲) n)))';
      _only(src, 'T29', ['「甲」的“创建时”里面有要等的事', '调了要等的「睡」', '新建对象不能等']);
      _fixed(src, 'T29', LFixKind.wrapSpawn);
    });

    test('T29 字段的初始值里不能等', () {
      _only('(函数 取 () -> 整数 (做 (宿 time.sleep 1)) (返回 1)) (类 甲 (字段 n 整数 (调 取))) (主 (打印 (. (新 甲) n)))', 'T29', ['「甲」的字段的初始值', '这里不能等']);
    });

    test('T29 规定了不许等的函数里有要等的事', () {
      _only('(不等函数 快 () -> 整数 (做 (宿 time.sleep 1)) (返回 1)) (主 (打印 (调 快)))', 'T29', ['「快」规定了不许等', '用了「等一会儿」']);
    });

    test('T29 实现 / 重写要一致：接口、父类规定不许等，实现、重写的却要等', () {
      _only('(接口 算的 (算 () 整数 不等)) (类 慢算 (实现 算的) (方法 算 () -> 整数 (做 (宿 time.sleep 1)) (返回 1))) (主 (打印 (发 (新 慢算) 算)))', 'T29', ['「慢算」的「算」里面有要等的事', '接口「算的」规定这个方法不许等', '实现的要和接口的一致']);
      _only('(类 基 可继承 (不等方法 算 () -> 整数 (返回 0))) (类 子 (继承 基) (方法 算 () -> 整数 (做 (宿 time.sleep 1)) (返回 1))) (主 (打印 (发 (新 子) 算)))', 'T29', ['「子」重写的「算」里面有要等的事', '父类「基」规定这个方法不许等', '重写的要和父类的一致']);
      // 反过来没事：接口说要等，实现的不等。
      _waits('(接口 算的 (算 () 整数 要等)) (类 快算 (实现 算的) (方法 算 () -> 整数 (返回 1))) (函数 用 ((a 算的)) -> 整数 (返回 (发 a 算))) (主 (打印 (调 用 (新 快算))))', yes: ['用'], no: ['快算.算']);
    });

    test('T30 要等的函数放进小库的口（筛选、映射）：设计 6.3 的第一个反例', () {
      // 同一段程序以前 Node 得 [1,2,3,4]、Python 得 [3,4]：现在编辑时就拦下。
      const src = '(函数 慢判断 ((x 整数)) -> 是否 (做 (宿 time.sleep 1)) (返回 (> x 2))) (主 (打印 (调 筛选 (列 1 2 3 4) (λ ((x 整数)) (调 慢判断 x)))))';
      _only(src, 'T30', ['只收不用等的函数', '放进来的函数要等', '调了要等的「慢判断」']);
      _only('(函数 慢 ((x 整数)) -> 整数 (做 (宿 time.sleep 1)) (返回 x)) (主 (打印 (调 映射 (列 1 2) 慢)))', 'T30', ['只收不用等的函数']);
    });

    test('T30 “改格子”的改法里不许等；单独一句的能一键改成“开始做”', () {
      const src = '(函数 记一笔 () (做 (宿 time.sleep 1))) (主 (做 (宿 store.update "n" (λ块 ((旧 任意)) (做 (调 记一笔)) (返回 旧)))))';
      _only(src, 'T30', ['只收不用等的函数', '调了要等的「记一笔」']);
      _fixed(src, 'T30', LFixKind.wrapSpawn);
    });

    test('T30 标了“不等函数”的参数；说不准的函数值也拦', () {
      _only('(函数 用 ((f (不等函数 () 整数))) -> 整数 (返回 (调 f))) (主 (打印 (调 用 (λ块 () (做 (宿 time.sleep 1)) (返回 1)))))', 'T30', ['「用」的第 1 个参数只收不用等的函数']);
      // 把自己的参数原样转交给只收不用等的函数的地方：这个参数也跟着只收不用等的函数，在最外面那次调用上报。
      _only(
        '(函数 用 ((f (不等函数 () 整数))) -> 整数 (返回 (调 f)))'
            '(函数 转 ((g (函数 () 整数))) -> 整数 (返回 (调 用 g)))'
            '(主 (打印 (调 转 (λ块 () (做 (宿 time.sleep 1)) (返回 1)))))',
        'T30',
        ['「转」的第 1 个参数只收不用等的函数', '用了「等一会儿」'],
      );
      // 把参数包在匿名函数里调、再把匿名函数放进去：也一样（回头重查一遍推出来的）。
      _only(
        '(函数 改库 ((名 文字) (改法 (函数 (任意) 任意))) -> 任意 (返回 (宿 store.update 名 (λ ((旧 任意)) (调 改法 旧)))))'
            '(主 (打印 (调 改库 "n" (λ块 ((旧 任意)) (做 (宿 time.sleep 1)) (返回 旧)))))',
        'T30',
        ['「改库」的第 2 个参数只收不用等的函数'],
      );
      // 同一个“改库”，放进来的都不用等，可是程序别处有要等的函数被当成值传：不误报。
      _waits(
        '(函数 改库 ((名 文字) (改法 (函数 (任意) 任意))) -> 任意 (返回 (宿 store.update 名 (λ ((旧 任意)) (调 改法 旧)))))'
        '(函数 跑 ((f (函数 () 整数))) -> 整数 (返回 (调 f)))'
        '(主 (打印 (调 改库 "n" (λ ((旧 任意)) 旧))) (打印 (调 跑 (λ块 () (做 (宿 time.sleep 1)) (返回 1)))))',
        yes: ['跑'],
        no: ['改库'],
        escaped: true,
      );
      // 不是参数、说不准的函数值（放在变量里的）：拦。
      _only(
        '(函数 用 ((f (不等函数 () 整数))) -> 整数 (返回 (调 f)))'
            '(主 (设 g (函数 () 整数) (λ块 () (做 (宿 time.sleep 1)) (返回 1))) (打印 (调 用 g)))',
        'T30',
        ['说不准要不要等'],
      );
    });

    test('T31 “等”后面不是“稍后的结果”；一键去掉“等”', () {
      const src = '(函数 取 () -> 整数 (返回 1)) (主 (打印 (等 (调 取))))';
      _only(src, 'T31', ['“等”后面要一个“稍后的结果”', '这里是整数']);
      _fixed(src, 'T31', LFixKind.dropAwait);
      _only('(函数 取 ((t (可空 (稍后 整数)))) -> 整数 (返回 (等 t))) (主 (打印 1))', 'T31', ['可能是空的']);
    });
  });
}

List<LExpr> lExprChildrenForTest(LExpr e) => switch (e) {
  LCall(:final callee, :final args) => [callee, ...args],
  _ => const [],
};
