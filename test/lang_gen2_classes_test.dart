// 核心 2 第 2 段的验收（积木第 5 版）：类与接口。
//
// 1. test/fixtures/core2/ 下 c 开头的 14 个样例程序（c01–c12 单模块，c13、c14 多模块）交给规矩版本 2 的生成器，生成 Node / Python / PHP / Go / Java
//    五种语言的整套文件，**真的编译、真的跑**：标准输出和 .expect 逐字节一样；有没接住的错的（c10）退出码是 1，别的是 0。
// 2. 故意写错的程序在检查阶段就被拦下（T01、T07、T08、T11、T17、T18、T19、T22–T28），不生成代码。
// 3. 宿主接口的声明和宿主给的对不上、用了还没有的宿主接口：生成的时候说清楚。
//
// 要调外部程序：缺哪种语言的编译器就跳过那种语言并打印原因。样例的写法见 test/support/proto_lc.dart。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _dir = 'test/fixtures/core2';

bool _isProgram(String name) => name.startsWith('c13') || name.startsWith('c14');

Map<String, String> _files(String language, String name) {
  final src = File('$_dir/$name.lc').readAsStringSync();
  return _isProgram(name) ? gen2ProgramFiles(language, lcProgram(src)) : gen2Files(language, lcModule(src));
}

/// 一个模块的错例：报的问题（规则号＋提示语）。
List<String> _said(String src) => [for (final i in checkModuleTypes(lcModule(src)).errors) '${i.code} ${i.message}'];

/// 只有这一条规则号（可以报好几次），而且提示语里有这些字。
void _only(String src, String code, List<String> parts) {
  final said = _said(src);
  expect(said, isNotEmpty, reason: src);
  expect({for (final s in said) s.split(' ').first}, {code}, reason: said.join('\n'));
  for (final p in parts) {
    expect(said.any((s) => s.contains(p)), isTrue, reason: '提示语里要有「$p」：\n${said.join('\n')}');
  }
  // 检查没过的，五种语言都不生成。
  for (final l in kGen2Languages) {
    expect(() => gen2Files(l, lcModule(src)), throwsA(isA<LangUnsupported>()), reason: l);
  }
}

const String _animal = '(类 动物 可继承 (字段 名 文字 "") (创建 ((名 文字)) (改字段 (这) 名 名)) (方法 叫 ((几声 整数 1)) -> 文字 (返回 "…")))';
const String _iface = '(接口 会叫 (叫 () 文字) (跑 ((步 整数)) 整数))';

void main() {
  final names = [
    for (final f in Directory(_dir).listSync().whereType<File>())
      if (f.path.endsWith('.lc') && f.path.split('/').last.startsWith('c')) f.path.split('/').last.replaceAll('.lc', ''),
  ]..sort();

  test('样例都在：14 个类与接口的（c01–c14），每个都有 .expect；只有 c10 最后是没接住的错', () {
    expect(names.length, 14);
    expect([for (final n in names) n.substring(0, 3)], [for (var i = 1; i <= 14; i++) 'c${'$i'.padLeft(2, '0')}']);
    for (final n in names) {
      expect(File('$_dir/$n.expect').existsSync(), isTrue, reason: n);
    }
    final uncaught = [
      for (final n in names)
        if (File('$_dir/$n.expect').readAsStringSync().trimRight().split('\n').last.startsWith('出错：')) n,
    ];
    expect(uncaught, ['c10-errors-in-classes']);
  });

  for (final language in kGen2Languages) {
    group('$language：14 个样例生成、真跑，输出逐字节一样，退出码对', () {
      final skip = gen2SkipReason(language);
      for (final n in names) {
        test(n, () async {
          final files = _files(language, n);
          expect(files, isNotEmpty);
          if (skip != null) {
            // ignore: avoid_print — 跳过的原因要让跑测试的人看见
            print('跳过：$skip');
            markTestSkipped(skip);
            return;
          }
          final run = await gen2RunFiles(language, files);
          expect(run.problem, isNull, reason: '$language / $n 没跑成');
          final want = File('$_dir/$n.expect').readAsBytesSync();
          expect(utf8.decode(run.stdout, allowMalformed: true), utf8.decode(want), reason: '$language / $n 的输出不一样');
          expect(run.stdout, want, reason: '$language / $n 的输出字节不一样');
          final uncaught = utf8.decode(want).trimRight().split('\n').last.startsWith('出错：');
          expect(run.exitCode, uncaught ? 1 : 0, reason: '$language / $n 的退出码');
        });
      }
    });
  }

  group('类：写错的在检查阶段被拦', () {
    test('调不存在的方法、读不存在的字段（T08）', () {
      _only('$_animal (主 (设 a (新 动物 "x")) (打印 (发 a 飞)))', 'T08', ['动物没有「飞」这个方法']);
      _only('$_animal (主 (设 a (新 动物 "x")) (打印 (. a 岁)))', 'T08', ['动物没有「岁」这一项']);
      _only('$_animal (主 (打印 (发 动物 造)))', 'T08', ['「动物」这个类本身没有「造」这个方法']);
      _only('$_animal (主 (打印 (. 动物 总数)))', 'T08', ['「动物」这个类本身没有「总数」这一项']);
      _only('$_animal (主 (设 a (新 动物 "x")) (打印 (是 没这个类 a)))', 'T08', ['没有叫「没这个类」的类或接口']);
      _only('(类 子 (继承 没这个) (创建 ())) (主 (打印 1))', 'T08', ['没有叫「没这个」的类']);
    });

    test('继承了没勾“可以被继承”的类（T17）', () {
      _only('(类 甲 (创建 ())) (类 乙 (继承 甲) (创建 ())) (主 (打印 1))', 'T17', ['「甲」没有勾“可以被继承”']);
    });

    test('重写的方法和父类的对不上：参数个数、参数类型、返回类型、默认值（T18）', () {
      _only('$_animal (类 狗 (继承 动物) (方法 叫 () -> 文字 (返回 "汪"))) (主 (打印 1))', 'T18', ['「狗」的「叫」和「动物」的对不上', '父类的收 1 个参数，这里收 0 个']);
      _only('$_animal (类 狗 (继承 动物) (方法 叫 ((几声 文字 "一")) -> 文字 (返回 "汪"))) (主 (打印 1))', 'T18', ['第 1 个参数父类的是整数，这里是文字']);
      _only('$_animal (类 狗 (继承 动物) (方法 叫 ((几声 整数 1)) -> 整数 (返回 1))) (主 (打印 1))', 'T18', ['父类的返回文字，这里返回整数']);
      _only('$_animal (类 狗 (继承 动物) (方法 叫 ((几声 整数 2)) -> 文字 (返回 "汪"))) (主 (打印 1))', 'T18', ['第 1 个参数的默认值和父类的不一样']);
      _only('$_animal (类 狗 (继承 动物) (方法 叫 ((几声 整数)) -> 文字 (返回 "汪"))) (主 (打印 1))', 'T18', ['第 1 个参数的默认值和父类的不一样']);
      // 一模一样就行；隔一层重写也查。
      expect(_said('$_animal (类 狗 可继承 (继承 动物)) (类 小狗 (继承 狗) (方法 叫 ((几声 整数 1)) -> 文字 (返回 "汪"))) (主 (打印 (发 (新 小狗 "x") 叫)))'), isEmpty);
      _only('$_animal (类 狗 可继承 (继承 动物)) (类 小狗 (继承 狗) (方法 叫 () -> 文字 (返回 "汪"))) (主 (打印 1))', 'T18', ['「小狗」的「叫」和「动物」的对不上']);
    });

    test('在类的外面读、改内部的字段（T22）；自己和子类里面可以', () {
      const box = '(类 盒 可继承 (内部字段 值 整数 0) (内部类字段 个数 整数 0) (创建 ()) (方法 看 () -> 整数 (返回 (. (这) 值))))';
      _only('$box (主 (设 b (新 盒)) (打印 (. b 值)))', 'T22', ['「盒」的「值」是内部的']);
      _only('$box (主 (设 b (新 盒)) (改字段 b 值 3))', 'T22', ['「盒」的「值」是内部的']);
      _only('$box (主 (打印 (. 盒 个数)))', 'T22', ['「盒」的「个数」是内部的']);
      _only('$box (类 别人 (方法 偷看 ((b 盒)) -> 整数 (返回 (. b 值)))) (主 (打印 1))', 'T22', ['只有「盒」自己和它的子类里面能用']);
      _only('$box (函数 偷看 ((b 盒)) -> 整数 (返回 (. b 值))) (主 (打印 1))', 'T22', const []);
      expect(_said('$box (类 小盒 (继承 盒) (方法 改 ((别的 盒)) (改字段 (这) 值 (+ (. 别的 值) (. 盒 个数))))) (主 (打印 (发 (新 小盒) 看)))'), isEmpty);
      expect(_said('$box (类 小盒 (继承 盒) (方法 数 () -> 整数 (设 f (λ () (. (这) 值))) (返回 (调 f)))) (主 (打印 (发 (新 小盒) 数)))'), isEmpty);
    });

    test('把接口当类用、把类当接口用（T23）', () {
      _only('$_iface (主 (设 x (新 会叫)))', 'T23', ['「会叫」是接口，不能新建']);
      _only('$_iface (类 狗 (继承 会叫) (创建 ())) (主 (打印 1))', 'T23', ['「会叫」是接口，不能当父类']);
      _only('$_animal (类 狗 (实现 动物) (创建 ())) (主 (打印 1))', 'T23', ['「动物」是类，不是接口']);
    });

    test('继承绕圈（T24）：两个类、三个类、自己继承自己', () {
      _only('(类 甲 可继承 (继承 乙) (创建 ())) (类 乙 可继承 (继承 甲) (创建 ())) (主 (打印 1))', 'T24', ['继承绕圈了：甲 → 乙 → 甲']);
      _only('(类 甲 可继承 (继承 丙)) (类 乙 可继承 (继承 甲)) (类 丙 可继承 (继承 乙)) (主 (打印 1))', 'T24', ['甲 → 丙 → 乙 → 甲']);
      _only('(类 甲 可继承 (继承 甲)) (主 (打印 1))', 'T24', ['甲 → 甲']);
    });

    test('类本身的和对象自己的用混了（T25）', () {
      const tool = '(类 工具 (类字段 次 整数 0) (字段 名 文字 "") (类方法 加一 ((n 整数)) -> 整数 (返回 (+ n 1))) (方法 说 () -> 文字 (返回 "hi")) (创建 ()))';
      _only('$tool (主 (设 t (新 工具)) (打印 (发 t 加一 1)))', 'T25', ['「加一」是「工具」这个类本身的方法']);
      _only('$tool (主 (打印 (发 工具 说)))', 'T25', ['「说」是每个对象自己的方法']);
      _only('$tool (主 (打印 (. 工具 名)))', 'T25', ['「名」是每个对象自己的字段']);
      _only('(类 工具 (字段 名 文字 "") (类方法 坏 () -> 文字 (返回 (. (这) 名))) (创建 ())) (主 (打印 1))', 'T25', ['“我自己”只能用在类的方法和“创建时”里']);
      _only('(主 (打印 (文 (这))))', 'T25', const []);
      // 名字被变量挡住了，就是那个变量。
      expect(_said('$tool (主 (设 工具 (新 工具)) (打印 (发 工具 说)))'), isEmpty);
    });

    test('参数的默认值写得不对（T26）', () {
      _only('(函数 f ((a 整数 1) (b 整数)) -> 整数 (返回 a)) (主 (打印 1))', 'T26', ['参数「b」没有默认值，要排在有默认值的参数前面']);
      _only('(函数 g ((a 整数 "x")) -> 整数 (返回 a)) (主 (打印 1))', 'T26', ['参数「a」是整数，默认值却是文字']);
      _only('(类 甲 (创建 ((a 文字 空)))) (主 (打印 1))', 'T26', ['参数「a」是文字，默认值却是空']);
      // 整数的默认值放进小数的参数、空放进可空的参数：可以。
      expect(_said('(函数 h ((a 小数 1) (b (可空 文字) 空)) -> 小数 (返回 a)) (主 (打印 (调 h)))'), isEmpty);
      // 少给了没有默认值的参数，还是原来那条（T07）。
      expect(_said('(函数 f ((a 整数) (b 整数 1)) -> 整数 (返回 a)) (主 (打印 (调 f)))').single, startsWith('T07 '));
      expect(_said('$_animal (主 (打印 (发 (新 动物) 叫)))').single, startsWith('T07 '));
    });

    test('“调父类的创建时”放的地方不对、该调没调（T27）', () {
      const p = '(类 父 可继承 (字段 n 整数 0) (创建 ((n 整数)) (改字段 (这) n n)))';
      _only('$p (类 子 (继承 父) (创建 () (打印 1))) (主 (打印 1))', 'T27', ['「父」的“创建时”要参数，「子」的“创建时”第一句要先“调父类的创建时”']);
      _only('$p (类 子 (继承 父) (创建 () (打印 1) (父创建 2))) (主 (打印 1))', 'T27', ['要放在「子」的“创建时”的第一句，而且只能调一次']);
      _only('$p (类 子 (继承 父) (创建 () (父创建 2) (父创建 3))) (主 (打印 1))', 'T27', ['只能调一次']);
      _only('$p (类 子 (继承 父) (方法 坏 () (父创建 1))) (主 (打印 1))', 'T27', ['只能写在「子」的“创建时”里']);
      // 父类的“创建时”不要参数（或者都有默认值的不算——要参数就得调）：不调也行。
      expect(_said('(类 父 可继承 (创建 ())) (类 子 (继承 父) (创建 () (打印 1))) (主 (打印 1))'), isEmpty);
      // 子类自己没写“创建时”：沿用父类的。
      expect(_said('$p (类 子 (继承 父)) (主 (打印 (. (新 子 3) n)))'), isEmpty);
    });

    test('类里有重名的东西（T28）', () {
      _only('(类 甲 (字段 m 整数 0) (方法 m () -> 整数 (返回 1))) (主 (打印 1))', 'T28', ['「甲」里有两个东西都叫「m」']);
      _only('(类 甲 (类字段 m 整数 0) (字段 m 整数 0)) (主 (打印 1))', 'T28', ['都叫「m」']);
      _only('(类 甲 (方法 m () -> 整数 (返回 1)) (类方法 m () -> 整数 (返回 1))) (主 (打印 1))', 'T28', ['都叫「m」']);
      _only('(类 父 可继承 (字段 n 整数 0)) (类 子 (继承 父) (字段 n 整数 0)) (主 (打印 1))', 'T28', ['「子」的字段「n」和「父」里的重名了']);
    });
  });

  group('接口：写错的在检查阶段被拦', () {
    test('没实现全、参数个数 / 类型 / 返回 / 默认值对不上（T11）', () {
      _only('$_iface (类 狗 (实现 会叫) (方法 叫 () -> 文字 (返回 "汪"))) (主 (打印 1))', 'T11', ['「狗」说自己是「会叫」，但是没有「跑」这个方法']);
      _only('$_iface (类 狗 (实现 会叫) (方法 叫 () -> 文字 (返回 "汪")) (方法 跑 () -> 整数 (返回 1))) (主 (打印 1))', 'T11', ['「狗」的「跑」要收 1 个参数，现在收 0 个']);
      _only('$_iface (类 狗 (实现 会叫) (方法 叫 () -> 文字 (返回 "汪")) (方法 跑 ((步 文字)) -> 整数 (返回 1))) (主 (打印 1))', 'T11', ['第 1 个参数接口「会叫」的是整数，这里是文字']);
      _only('$_iface (类 狗 (实现 会叫) (方法 叫 () -> 整数 (返回 1)) (方法 跑 ((步 整数)) -> 整数 (返回 1))) (主 (打印 1))', 'T11', ['「狗」的「叫」要返回文字']);
      _only('$_iface (类 狗 (实现 会叫) (方法 叫 () -> 文字 (返回 "汪")) (方法 跑 ((步 整数 3)) -> 整数 (返回 1))) (主 (打印 1))', 'T11', ['第 1 个参数的默认值和接口「会叫」的不一样']);
      _only('(类 狗 (实现 没这个接口)) (主 (打印 1))', 'T08', ['没有叫「没这个接口」的接口']);
      // 方法在父类里也算实现了。
      expect(_said('$_iface (类 兽 可继承 (方法 叫 () -> 文字 (返回 "吼"))) (类 狗 (继承 兽) (实现 会叫) (方法 跑 ((步 整数)) -> 整数 (返回 步))) (主 (设 x (标 会叫 (新 狗))) (打印 (发 x 叫)))'), isEmpty);
    });

    test('按接口用的时候，调接口里没有的方法、放进没实现它的类（T08、T01）', () {
      const dog = '(类 狗 (实现 会叫) (方法 叫 () -> 文字 (返回 "汪")) (方法 跑 ((步 整数)) -> 整数 (返回 步)) (方法 摇尾巴 () -> 文字 (返回 "摇")))';
      _only('$_iface $dog (主 (设 x (标 会叫 (新 狗))) (打印 (发 x 摇尾巴)))', 'T08', ['会叫没有「摇尾巴」这个方法']);
      expect(_said('$_iface (类 石头) (主 (设 x (标 会叫 (新 石头))))').single, startsWith('T01 '));
    });

    test('接口不能当“出错时”要接的种类（T19）：接住的一定是“错误”或者它的子类，接口保证不了它有“消息”“种类”', () {
      _only('$_iface (主 (试 (做 (打印 1)) (出错时 会叫 e (打印 "x"))))', 'T19', ['「会叫」不是']);
      // 要按“实现了某个接口”来分，就先接“错误”，再问“是不是”。
      expect(
        _said(
          '(接口 能重试 (几次 () 整数)) (类 网断了 (继承 错误) (实现 能重试) (创建 () (父创建 "网断了")) (方法 几次 () -> 整数 (返回 3))) '
          '(主 (试 (做 (抛出 (新 网断了))) (出错时 错误 e (如果 (是 能重试 e) (那么 (打印 (发 (转 能重试 e) 几次)))))))',
        ),
        isEmpty,
      );
    });
  });

  group('内置错误、宿主接口', () {
    test('内置错误的“创建时”可以不给那句话（默认是空的一句话）；给了照旧', () {
      final ctor = langErrorPrelude().first.ctor!;
      expect(ctor.params.single.defaultValue, isA<LLit>());
      expect(ctor.params.single.defaultValue!.value, '');
      expect(_said('(主 (试 (做 (抛出 (新 找不到))) (出错时 找不到 e (打印 (. e 消息)))))'), isEmpty);
      expect(_said('(主 (试 (做 (抛出 (新 找不到 "丢了"))) (出错时 找不到 e (打印 (. e 消息)))))'), isEmpty);
    });

    test('宿主接口的清单：四个不用等的；每个都有小库里的名字', () {
      expect(kHostV2.keys.toList(), ['sys.print', 'time.now', 'store.read', 'store.update']);
      expect(kHostV2Code.keys.toSet(), kHostV2.keys.toSet());
    });

    test('宿主接口：没声明、声明和宿主给的对不上、还没有的——生成的时候说清楚', () {
      String why(String src) {
        try {
          gen2Files('node', lcModule(src));
        } on LangUnsupported catch (e) {
          return e.message;
        }
        return '';
      }

      expect(why('(宿主 time.now () -> 整数) (主 (打印 (宿 time.now)))'), '');
      expect(why('(宿主 time.now () -> 小数) (主 (打印 (宿 time.now)))'), contains('宿主接口「time.now」的声明和宿主给的对不上：应该是 () → 整数'));
      expect(why('(宿主 time.sleep ((毫秒 整数)) -> 空) (主 (做 (宿 time.sleep 1)))'), contains('宿主接口「time.sleep」这里还没有'));
      expect(why('(主 (打印 (文 (宿 time.now))))'), contains('宿主接口「time.now」用之前要先声明'));
      // 参数不对，检查阶段就拦（按声明查）。
      expect(_said('(宿主 sys.print ((话 文字) (通道 文字)) -> 空) (主 (做 (宿 sys.print 1 "out")))').single, startsWith('T01 '));
    });

    test('规则表：T22–T28 都登记了，都是“错”', () {
      for (var i = 22; i <= 28; i++) {
        expect(kTypeRules['T$i']?.level, LTypeLevel.error, reason: 'T$i');
      }
    });
  });
}
