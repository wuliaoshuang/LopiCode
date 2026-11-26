// 核心 2 第 1 段的验收（积木第 5 版）：错误是对象、模块。
//
// 1. test/fixtures/core2/ 下 15 个样例程序（e01–e10 错误，m01–m05 模块）交给规矩版本 2 的生成器，生成 Node / Python / PHP / Go / Java
//    五种语言的整套文件，**真的编译、真的跑**：标准输出和 .expect 逐字节一样；有没接住的错的（.expect 最后一行是“出错：…”）退出码是 1，别的是 0。
// 2. 故意写错的程序在检查阶段就被拦下（规则 T02、T08、T19–T21、M01–M08），五种语言都不生成代码。
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
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/gen2_run.dart';
import 'support/proto_lc.dart';

const String _dir = 'test/fixtures/core2';

bool _isProgram(String name) => name.startsWith('m');

Map<String, String> _files(String language, String name) {
  final src = File('$_dir/$name.lc').readAsStringSync();
  return _isProgram(name) ? gen2ProgramFiles(language, lcProgram(src)) : gen2Files(language, lcModule(src));
}

/// 一个模块的错例：报的问题（规则号＋提示语）。
List<String> _said(String src) => [for (final i in checkModuleTypes(lcModule(src)).errors) '${i.code} ${i.message}'];

/// 几个模块的错例：模块之间的问题；没有的话是合并以后类型检查的问题。
List<String> _saidProgram(String src) {
  final (linked, result) = checkProgramTypes(lcProgram(src));
  return [for (final i in linked.issues) '${i.code} ${i.message}', for (final i in result?.errors ?? const <LTypeIssue>[]) '${i.code} ${i.message}'];
}

const String _http = '(类 HTTP错误 可继承 (继承 错误) (字段 状态码 整数 0) (创建 ((码 整数) (话 文字)) (父创建 话) (改字段 (这) 状态码 码)))';

void main() {
  final names = [
    for (final f in Directory(_dir).listSync().whereType<File>())
      // c 开头的是第 2 段（类与接口）的样例，在 lang_gen2_classes_test.dart 里跑。
      if (f.path.endsWith('.lc') && !f.path.split('/').last.startsWith('c')) f.path.split('/').last.replaceAll('.lc', ''),
  ]..sort();

  test('样例都在：10 个错误的、5 个模块的；每个都有 .expect', () {
    expect(names.where((n) => n.startsWith('e')).length, 10);
    expect(names.where(_isProgram).length, 5);
    for (final n in names) {
      expect(File('$_dir/$n.expect').existsSync(), isTrue, reason: n);
    }
  });

  for (final language in kGen2Languages) {
    group('$language：15 个样例生成、真跑，输出逐字节一样，退出码对', () {
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

  test('没接住的错有三个样例（e07、e09、m05），别的都正常结束', () {
    final uncaught = [
      for (final n in names)
        if (File('$_dir/$n.expect').readAsStringSync().trimRight().split('\n').last.startsWith('出错：')) n,
    ];
    expect(uncaught, ['e07-uncaught', 'e09-finally-only-uncaught', 'm05-init-fails']);
  });

  group('错误：写错的在检查阶段被拦', () {
    test('接了不存在的种类', () {
      expect(_said('(主 (试 (做 (打印 1)) (出错时 没这种 e (打印 "x"))))'), ['T19 “出错时”要接的「没这种」不存在：没有叫这个名字的错误种类']);
    });
    test('接的不是错误的种类（普通的类、记录）', () {
      expect(_said('(类 盒子 (创建 ())) (主 (试 (做 (打印 1)) (出错时 盒子 e (打印 "x"))))'), ['T19 “出错时”只能接错误的种类（“错误”或者父类是它的类），「盒子」不是']);
      expect(_said('(记录 点 (x 整数)) (主 (试 (做 (打印 1)) (出错时 点 _ (打印 "x"))))').single, startsWith('T19 '));
    });
    test('读错误对象上没有的字段', () {
      expect(_said('$_http (主 (试 (做 (抛出 (新 HTTP错误 500 "坏"))) (出错时 _ e (打印 (. e 状态码)))))'), ['T08 错误没有「状态码」这一项']);
      expect(_said('$_http (主 (试 (做 (抛出 (新 HTTP错误 500 "坏"))) (出错时 HTTP错误 e (打印 (. e 没这个)))))'), ['T08 HTTP错误没有「没这个」这一项']);
      // 按种类接了就读得到。
      expect(_said('$_http (主 (试 (做 (抛出 (新 HTTP错误 500 "坏"))) (出错时 HTTP错误 e (打印 (. e 状态码)))))'), isEmpty);
    });
    test('错误变量不再是一句话：直接当文字用报错，要读“消息”', () {
      final said = _said('(函数 f () -> 文字 (试 (做 (返回 "a")) (出错时 _ e (返回 e))))');
      expect(said.single, startsWith('T01 '));
      expect(_said('(函数 f () -> 文字 (试 (做 (返回 "a")) (出错时 _ e (返回 (. e 消息)))))'), isEmpty);
    });
    test('抛出的不是一句话也不是错误', () {
      expect(_said('(主 (抛出 42))'), ['T19 “抛出”后面要一句话或者一个错误，放进来的是整数']);
      expect(_said('(类 盒子 (创建 ())) (主 (抛出 (新 盒子)))').single, startsWith('T19 '));
      expect(_said('(函数 f ((e (可空 错误))) (抛出 e))').single, startsWith('T02 '));
    });
    test('这一节永远轮不到：粗的种类排在细的前面、兜底的后面还有', () {
      expect(_said('$_http (主 (试 (做 (打印 1)) (出错时 错误 e (打印 "a")) (出错时 HTTP错误 e (打印 "b"))))').single, startsWith('T21 '));
      expect(_said('(主 (试 (做 (打印 1)) (出错时 _ _ (打印 "a")) (出错时 找不到 _ (打印 "b"))))').single, startsWith('T21 '));
      expect(_said('(主 (试 (做 (打印 1)) (出错时 找不到 _ (打印 "a")) (出错时 找不到 _ (打印 "b"))))').single, startsWith('T21 '));
    });
    test('自己的东西不能叫内置错误的名字；“种类”只能读', () {
      expect(_said('(类 错误 (创建 ())) (主 (打印 1))'), ['T20 「错误」是内置的错误种类，自己的东西换一个名字']);
      expect(_said('(函数 找不到 () -> 整数 (返回 1)) (主 (打印 1))').single, startsWith('T20 '));
      expect(_said('(主 (设 e (新 错误 "x")) (改字段 e 种类 "别的"))'), ['T19 错误的“种类”只能读，不能改']);
    });
    test('被拦下的程序五种语言都不生成', () {
      final module = lcModule('(主 (抛出 42))');
      for (final language in kGen2Languages) {
        expect(() => gen2Files(language, module), throwsA(isA<LangUnsupported>().having((e) => e.what, '原因', contains('类型检查没过'))), reason: language);
      }
    });
  });

  group('模块：写错的在检查阶段被拦', () {
    test('绕圈：把圈画出来，给固定的解法', () {
      expect(_saidProgram('(模块 甲 (用 乙) (公开 (函数 a () -> 整数 (返回 (调 b))))) (模块 乙 (用 丙) (公开 (函数 b () -> 整数 (返回 1)))) (模块 丙 (用 甲)) (模块 主程序 (用 甲) (主 (打印 (调 a))))'), [
        'M03 模块绕圈了：甲 → 乙 → 丙 → 甲。把「甲」和「乙」都要用的东西挪到第三个模块里，让它们都去用它',
      ]);
      expect(_saidProgram('(模块 甲 (用 主程序)) (模块 主程序 (用 甲) (主 (打印 1)))').single, startsWith('M03 模块绕圈了：甲 → 主程序 → 甲'));
    });
    test('没公开的用不了；没说“用到了谁”的用不了', () {
      expect(_saidProgram('(模块 甲 (函数 藏着 () -> 整数 (返回 1))) (模块 主程序 (用 甲) (主 (打印 (调 藏着))))'), ['M06 模块「甲」里的「藏着」没有公开，「主程序」用不了：在「甲」里给它勾上“公开”']);
      expect(_saidProgram('(模块 甲 (公开 (函数 亮着 () -> 整数 (返回 1)))) (模块 主程序 (主 (打印 (调 亮着))))'), ['M05 「亮着」在模块「甲」里，「主程序」还没说用到了它：在「主程序」的“用到了谁”里加上「甲」']);
      // 类型也一样：没公开的类，别的模块不能新建、不能接。
      expect(_saidProgram('(模块 甲 (类 私错 (继承 错误) (创建 ((话 文字)) (父创建 话)))) (模块 主程序 (用 甲) (主 (试 (做 (打印 1)) (出错时 私错 _ (打印 2)))))').single, startsWith('M06 '));
    });
    test('模块名、入口、“用到了谁”写错', () {
      expect(_saidProgram('(模块 甲) (模块 甲) (模块 主程序 (主 (打印 1)))').single, startsWith('M01 '));
      expect(_saidProgram('(入口 没有) (模块 甲 (主 (打印 1)))'), ['M02 找不到入口模块「没有」']);
      expect(_saidProgram('(模块 主程序 (用 不存在) (主 (打印 1)))'), ['M02 模块「主程序」说用到了「不存在」，但是没有叫这个名字的模块']);
      expect(_saidProgram('(模块 主程序 (用 主程序) (主 (打印 1)))').single, startsWith('M02 '));
    });
    test('只有入口有“程序开始时”；入口不能被别的模块用', () {
      expect(_saidProgram('(模块 甲 (主 (打印 "不该有"))) (模块 主程序 (用 甲) (主 (打印 1)))').single, startsWith('M04 模块「甲」不是入口'));
      expect(_saidProgram('(入口 主程序) (模块 主程序 (公开 (函数 f () -> 整数 (返回 1))) (主 (打印 1))) (模块 甲 (用 主程序) (函数 g () -> 整数 (返回 (调 f))))').single, startsWith('M03 入口模块「主程序」不能被别的模块用'));
    });
    test('两个用到的模块公开了同一个名字：分不清', () {
      expect(_saidProgram('(模块 甲 (公开 (函数 算 () -> 整数 (返回 1)))) (模块 乙 (公开 (函数 算 () -> 整数 (返回 2)))) (模块 主程序 (用 甲 乙) (主 (打印 (调 算))))').single, startsWith('M07 「算」在模块「甲」「乙」里都有'));
      // 没去用它就不算错；自己也有一个就用自己的。
      expect(_saidProgram('(模块 甲 (公开 (函数 算 () -> 整数 (返回 1)))) (模块 乙 (公开 (函数 算 () -> 整数 (返回 2)))) (模块 主程序 (用 甲 乙) (函数 算 () -> 整数 (返回 3)) (主 (打印 (调 算))))'), isEmpty);
    });
    test('顶上的变量：初始值用到了排在后面的变量', () {
      expect(_saidProgram('(模块 主程序 (变量 a 整数 (+ b 1)) (变量 b 整数 2) (主 (打印 a)))'), ['M08 「a」的初始值用到了排在它后面的「b」，那时候「b」还没有值：把「b」挪到前面']);
      expect(_saidProgram('(模块 主程序 (变量 a 整数 (+ a 1)) (主 (打印 a)))').single, startsWith('M08 「a」的初始值用到了它自己'));
    });
    test('合并以后类型检查照做：跨模块的调用参数不对也拦', () {
      expect(_saidProgram('(模块 甲 (公开 (函数 加一 ((x 整数)) -> 整数 (返回 (+ x 1))))) (模块 主程序 (用 甲) (主 (打印 (调 加一 "文字"))))').single, startsWith('T01 '));
    });
    test('被拦下的程序五种语言都不生成', () {
      final program = lcProgram('(模块 甲 (用 主程序)) (模块 主程序 (用 甲) (主 (打印 1)))');
      for (final language in kGen2Languages) {
        expect(() => gen2ProgramFiles(language, program), throwsA(isA<LangUnsupported>().having((e) => e.what, '原因', contains('模块检查没过'))), reason: language);
      }
    });
  });

  group('模块：合并的结果', () {
    test('启动顺序：被用到的先，同一层按写的先后，入口最后', () {
      expect(linkProgram(lcProgram(File('$_dir/m01-init-order.lc').readAsStringSync())).order, ['底', '中间', '主程序']);
      expect(linkProgram(lcProgram(File('$_dir/m04-diamond.lc').readAsStringSync())).order, ['底', '左', '右', '主程序']);
    });
    test('重名的顶层东西改叫“模块名·名字”，没撞的不改', () {
      final linked = linkProgram(lcProgram(File('$_dir/m03-same-names.lc').readAsStringSync()));
      expect(linked.names[('甲', '帮忙')], '甲·帮忙');
      expect(linked.names[('乙', '盒子')], '乙·盒子');
      expect(linked.names.keys.map((k) => k.$2).toSet(), {'次数', '盒子', '帮忙'});
      expect(linked.module!.decls.map((d) => d.name), containsAll(['甲算', '乙算', '主程序·次数']));
    });
    test('老的两种写法读出来是一样的“出错时”各节；规则表里新规则都有说法', () {
      const old = LTry([], errorName: 'e', onError: [LBreak()]);
      expect(old.catches.single.name, 'e');
      expect(old.catches.single.kind, isNull);
      expect(const LTry([], handlers: []).catches, isEmpty);
      for (final code in ['T19', 'T20', 'T21']) {
        expect(kTypeRules[code]!.advice, isNotEmpty);
      }
      expect(kModuleRules.keys.toList(), [for (var i = 1; i <= 8; i++) 'M0$i']);
      expect(kErrBuiltinNames, ['错误', '找不到', '类型不对', '数值不对', '超时', '取消了', '读写失败']);
    });
  });
}
